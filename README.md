# cfn-make

Minimalistic Makefile for CloudFormation stack deployments.

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
  # Fn::Stringify takes care of that.
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

## Build Stages

* **init** Ensures that all required variables are set and all dependencies are installed.
* **build** Compile the configuration file with `cfn-include` and write the output to a build folder.
* **test** Extract the CloudFormation template from the build folder and run `validate-template` on it.
* **create** Create the CloudFormation template and wait for its creation to finish. Prints stack outputs.
* **stage** Create a change set of the deployed stack to the current template. Prints change set elements.
* **update** Execute the change set. Prints stack outputs.

Build stages have dependencies as defined in the following graph. Note that the `update` stage does not depend on `stage`. The `update` stage will fail if the stack has not been staged. If you are certain that you want to run `stage` and `update` in one run (without reviewing the change set for potential surprises) you can run `make stage update`. The name of change set is unique to the template configuration and body. A change to the template or configuration will also change the change set name. A call to `update` will therefore fail if changes have been made to the template but the change set has not been created yet.

![Graph](graph.svg)

## Custom Hooks

All build steps come with pre- and post-hooks. These hooks need to be defined in a separate `Makefile` that is located in the same directory as the `$CONFIG` file. If the `$CONFIG` file is located in the root directory of the project, you should create a new makefile such as `hooks.makefile`. The environmental variable `$ARTIFACT` holds the location of the build artifact. If a hook fails so does the whole pipeline.

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
