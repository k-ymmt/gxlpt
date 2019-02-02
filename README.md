# gxlpt
Xcode の Library Project を自動生成するツール

## Usage

以下のフォルダ構成のとき、

```
.
|-- Gemfile
|-- Gemfile.lock
|-- add_project.rb
`-- example
  `-- Example.xcworkspace

```

以下のコマンドを実行することで

```
$ ./add_project.rb --name Sample --workspace ./example/Example.xcworkspace --org com.example
```

example/が以下のようになります。

```
.
|-- Example.xcworkspace
|
|-- Sample.xcodeproj
|   `-- project.pbxproj
|-- Sources
|   `-- Sample
|       |-- Info.plist
|       `-- Sample.h
`-- Tests
    `-- SampleTest
        `-- Info.plist
```

## Arguments

|argument | description |
|----|---|
| name | project name |
| workspace | xcode workspace path |
| org | project bundle identifier(if --org com.example --name Sample, generated project bundle identifier is `com.example.Sample`.) |
