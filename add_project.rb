#!/usr/bin/env ruby

require 'xcodeproj'
require 'optparse'

module TargetType
  SOURCE = 'Sources'.freeze
  TEST = 'Tests'.freeze
end

def parse_args
  project = {
      name: '',
      workspace: '',
      org: '',
  }
  OptionParser.new do |opt|
    opt.on('--name VALUE', 'project name') do |v|
      if v == ''
        puts "error: required project name"
        exit 1
      end

      project[:name] = v
    end

    opt.on('--workspace VALUE', 'workspace path') do |v|
      if v == ''
        puts "error: required workspace path"
        exit 1
      end

      unless File.exist?(v)
        puts "error: workspace path #{v} is not found"
        exit 1
      end

      unless File.extname(v) != 'workspace'
        puts "error: --workspace is required .workspace(actual #{v})"
        exit 1
      end

      project[:workspace] = v
    end

    opt.on('--org VALUE', 'organization identifier') do |v|
      if v == ''
        puts 'error: required organization identifier'
        exit 1
      end

      project[:org] = v
    end

    opt.parse ARGV
  end

  project
end

# @param [String] name
# @param [String] workspace_dir
# @param [String] org
# @return [Xcodeproj::Project]
def new_project(name, workspace_dir, org)
  path = "#{workspace_dir}/#{name}.xcodeproj"
  project = Xcodeproj::Project.new(path, false, Xcodeproj::Constants::LAST_KNOWN_OBJECT_VERSION)

  target = new_target(project, name, org)
  new_test_target(project, target, org)

  project.frameworks_group.remove_from_project

  project
end

# @param [Xcodeproj::Project] project
# @param [String] name
# @param [String] org
# @return [Xcodeproj::Project::Object::PBXNativeTarget]
def new_target(project, name, org)
  target = project.new_target(:framework, name, :ios, nil, nil, :swift)
  group_path = get_directory_path(project, TargetType::SOURCE, name)
  group = new_group(group_path, project)
  # project.main_group << group
  plist_path = new_plist project, target, TargetType::SOURCE
  r = Xcodeproj::Project::Object::FileReferencesFactory.new_reference(group, plist_path.relative_path_from(group.real_path), :group)
  target.build_configurations.each do |c|
    c.build_settings["INFOPLIST_FILE"] = plist_path.relative_path_from(project.path.dirname)
  end
  p = new_header target.name, Pathname(group_path)
  r = Xcodeproj::Project::Object::FileReferencesFactory.new_reference(group, p.relative_path_from(group.real_path), :group)
  fs = target.add_file_references [r]
  fs.each do |f|
    f.settings = {:ATTRIBUTES => [:Public]}
  end

  target.build_configurations.each do |c|
    c.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = "#{org}.#{name}"
    c.build_settings['ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES'] = 'YES'
  end

  target.frameworks_build_phase.clear

  target
end

# @param [Xcodeproj::Project] project
# @param [Xcodeproj::Project::Object::PBXNativeTarget] target
# @param [String] org
# @return [Xcodeproj::Project::Object::PBXNativeTarget]
def new_test_target(project, target, org)
  name = "#{target.name}Test"
  product_ref = project.products_group.new_reference("#{name}.xctest", :built_products)
  product_ref.set_explicit_file_type
  test_target = project.new_target(:framework, name, :ios, nil, project.new(Xcodeproj::Project::Object::PBXGroup), :swift)
  test_target.build_configuration_list = Xcodeproj::Project::ProjectHelper.configuration_list(project, :ios, nil, nil, :swift)
  test_target.product_reference = product_ref
  test_target.add_dependency(target)

  group = new_group(get_directory_path(project, TargetType::TEST, name), project)
  # project.main_group << group
  p = new_plist project, test_target, TargetType::TEST
  r = Xcodeproj::Project::Object::FileReferencesFactory.new_reference(group, p, :group)
  test_target.product_type = Xcodeproj::Constants::PRODUCT_TYPE_UTI[:unit_test_bundle]

  p = project.new(Xcodeproj::Project::PBXFrameworksBuildPhase)
  dependency_ref = target.product_reference
  p.add_file_reference(dependency_ref)
  test_target.build_phases << p

  test_target.build_configurations.each do |c|
    c.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = "#{org}.#{name}"
    c.build_settings['ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES'] = 'YES'
  end


  test_target.frameworks_build_phase.clear

  test_target
end

# @param [Pathname] path
# @param [Xcodeproj::Project] project
# @return [Xcodeproj::Project::Object::PBXGroup]
def new_group(path, project)
  FileUtils.mkdir_p(path) unless File.exist?(path)
  name = File.basename(path)
  project.new_group(name, path, :group)
end

# @param [Xcodeproj::Project] project
# @param [Xcodeproj::Project::Object::PBXNativeTarget] target
# @param [TargetType] target_type
# @return [Pathname]
def new_plist(project, target, target_type)
  path = get_directory_path(project, target_type, target.name)
  FileUtils.mkdir_p(path) unless File.exist?(path)
  ppath = Pathname File.join(path, 'Info.plist')
  File.open(ppath, 'w') do |f|
    t = target_type == TargetType::TEST ? :test : :framework
    plist_string = new_plist_string(t)
    f.write(plist_string)
    ppath
  end
end

# @param [Symbol] type
# @return [String]
def new_plist_string(type)
  name = case type
         when :framework then
           'Info_Framework.plist'
         else
           'Info_Test_Framework.plist'
         end

  File.open(File.join(__dir__, 'templates', name), 'r') do |f|
    return f.read
  end
end

# @param [String] name
# @param [Pathname] path
# @return [Pathname]
def new_header(name, path)
  File.open(File.join(__dir__, 'templates', 'Template.h'), 'r') do |f|
    h = f.read.gsub(/{{PROJECT_NAME}}/, name)
    file_path = path.join("#{name}.h")
    File.open(file_path, 'w') do |f|
      f.write(h)
      file_path
    end
  end
end

# @param [Xcodeproj::Project] project
# @param [TargetType] type
# @param [String] name
# @return [Pathname]
def get_directory_path(project, type, name)
  Pathname File.join(File.dirname(project.path), type, name)
end

p = parse_args
workspace_path = p[:workspace]
workspace_dir = File.dirname workspace_path

workspace = Xcodeproj::Workspace.new_from_xcworkspace(workspace_path)
project = new_project(p[:name], workspace_dir, p[:org])
workspace << Xcodeproj::Workspace::FileReference.new(project.path.relative_path_from(project.path.dirname), 'group')


project.save project.path
workspace.save_as(workspace_path)
