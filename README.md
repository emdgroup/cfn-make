# cfn-make

Makefile for CloudFormation stack deployments.

## Motivation

## Usage

```yaml
# mystack.template.yml

Parameters:
  BucketName:
    Type: String
Resources:
  Bucket:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: !Ref BucketName
Outputs:
  Arn: { Value: !GetAtt Bucket.Arn }
```

```yaml
# mystack.config.yml

StackName: MyStack

TemplateBody:
  # You can either define the whole template body inline or you can include
  # a reference to an external template file. TemplateBody has to be a string,
  # so Fn::Stringify helps with that.
  Fn::Stringify: !Include mystack.template.yml

Parameters:
  - { ParameterKey: BucketName, ParameterValue: MyBucket }

Capabilities: [CAPABILITY_IAM]

Tags:
  - { Key: Environment, Value: production }

```

```bash
export CONFIG=mystack.config.yml AWS_DEFAULT_REGION=us-east-1
make create
# ---------------------------------------------------
# |                 DescribeStacks                  |
# +------------+------------------------------------+
# |  OutputKey |            OutputValue             |
# +------------+------------------------------------+
# |  Arn       |  arn:aws:s3:::mybucket             |
# +------------+------------------------------------+

# ... make some changes to your template, for example change the bucket name

make stage  # creates a change set and displays changes made to the stack
# ------------------------------------------------------------------------------------------------------------------
# |                                                DescribeChangeSet                                               |
# +--------+------------+--------------+---------------------------+---------------------------+-------------------+
# | Action | LogicalId  | Replacement  | ResourceParameterDynamic  |  ResourceParameterStatic  |       Type        |
# +--------+------------+--------------+---------------------------+---------------------------+-------------------+
# |  Modify|  Bucket    |  True        |  BucketName               |  BucketName               |  AWS::S3::Bucket  |
# +--------+------------+--------------+---------------------------+---------------------------+-------------------+

make update # if you are happy with the changes, execute the change set

```

## Customization

All build steps come with pre- and post-hooks. These hooks need to be defined in a separate `Makefile` that is located in the same directory as the `CONFIG` file. If the `CONFIG` file is located in the root directory of the project, you should create a new makefile such as `hooks.makefile`. The environmental variable `$ARTIFACT` holds the location of the build artifact. If a hook fails so does the whole pipeline.

A simple post-build hook could for example replace the `BucketName` parameter value with an environmental variable. The corresponding Makefile would look something like this:

```make
# hooks.makefile

post-build:
  sed -i.bak -e "s/MyBucket/$$BUCKET_NAME/" $(ARTIFACT)
```

Running the `build` target will indicate that a `post-build` hook was found and will execute it:

```
BUCKET_NAME=mynewbucket make build
running post-build hook
sed -i.bak -e "s/MyBucket/$$BUCKET_NAME/" .build/mystack.config.yml.json
```


![Graph](graph.svg)
