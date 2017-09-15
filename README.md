# cfn-make

Makefile for CloudFormation stack deployments.

## Motivation

## Usage

```yaml
# mystack.config.yml

StackName: MyBucket

TemplateBody: !Stringify
  Paramters:
    BucketName:
      Type: String
  Resources:
    Bucket:
      Type: AWS::S3::Bucket
      Properties:
        BucketName: !Ref BucketName

Parameter:
  - ParameterKey: BucketName
    ParameterValue: MyBucket

```

```
export CONFIG=mystack.config.yml AWS_DEFAULT_REGION=us-east-1
make create
```

## Customization

Every build step has hooks that 

![Graph](graph.svg)
