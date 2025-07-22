AWSTemplateFormatVersion: '2010-09-09'
Description: 'Production-ready custom resource implementation - Managed by Terraform'

Parameters:
  Environment:
    Type: String
    Default: ${environment}
    AllowedValues: ['development', 'staging', 'production']
    Description: Environment name
  
  ResourceVersion:
    Type: String
    Default: '1.0'
    Description: Version of the custom resource

Resources:
  # IAM Role for Lambda execution
  CustomResourceRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: !Sub '${project_name}-prod-lambda-role-${random_suffix}'
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: lambda.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
      Policies:
        - PolicyName: CustomResourcePolicy
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              - Effect: Allow
                Action:
                  - s3:GetObject
                  - s3:PutObject
                  - s3:DeleteObject
                  - s3:ListBucket
                Resource: !Sub '$${S3Bucket}/*'
              - Effect: Allow
                Action:
                  - s3:ListBucket
                Resource: !Sub '$${S3Bucket}'
      Tags:
        - Key: Project
          Value: ${project_name}
        - Key: Environment
          Value: !Ref Environment
        - Key: ManagedBy
          Value: Terraform
  
  # S3 Bucket for data storage
  S3Bucket:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: !Sub '${project_name}-prod-$${Environment}-$${AWS::AccountId}-${aws_region}-${random_suffix}'
      PublicAccessBlockConfiguration:
        BlockPublicAcls: true
        BlockPublicPolicy: true
        IgnorePublicAcls: true
        RestrictPublicBuckets: true
      BucketEncryption:
        ServerSideEncryptionConfiguration:
          - ServerSideEncryptionByDefault:
              SSEAlgorithm: AES256
      VersioningConfiguration:
        Status: Enabled
      LifecycleConfiguration:
        Rules:
          - Id: DeleteOldVersions
            Status: Enabled
            NoncurrentVersionExpirationInDays: 30
      Tags:
        - Key: Project
          Value: ${project_name}
        - Key: Environment
          Value: !Ref Environment
        - Key: ManagedBy
          Value: Terraform
  
  # Lambda function for custom resource
  CustomResourceFunction:
    Type: AWS::Lambda::Function
    Properties:
      FunctionName: !Sub '${project_name}-prod-function-$${Environment}-${random_suffix}'
      Runtime: python3.9
      Handler: index.lambda_handler
      Role: !GetAtt CustomResourceRole.Arn
      Timeout: 300
      MemorySize: 256
      Environment:
        Variables:
          ENVIRONMENT: !Ref Environment
          LOG_LEVEL: INFO
      Code:
        ZipFile: |
          import json
          import boto3
          import cfnresponse
          import logging
          from datetime import datetime
          
          logger = logging.getLogger()
          logger.setLevel(logging.INFO)
          
          def lambda_handler(event, context):
              try:
                  logger.info(f"Event: {json.dumps(event)}")
                  
                  request_type = event['RequestType']
                  properties = event.get('ResourceProperties', {})
                  physical_id = event.get('PhysicalResourceId', 'CustomResourceDemo')
                  
                  response_data = {}
                  
                  if request_type == 'Create':
                      response_data = {'Message': 'Resource created successfully', 'Timestamp': datetime.utcnow().isoformat()}
                  elif request_type == 'Update':
                      response_data = {'Message': 'Resource updated successfully', 'Timestamp': datetime.utcnow().isoformat()}
                  elif request_type == 'Delete':
                      response_data = {'Message': 'Resource deleted successfully', 'Timestamp': datetime.utcnow().isoformat()}
                  
                  cfnresponse.send(event, context, cfnresponse.SUCCESS, response_data, physical_id)
                  
              except Exception as e:
                  logger.error(f"Error: {str(e)}")
                  cfnresponse.send(event, context, cfnresponse.FAILED, {}, physical_id)
      Tags:
        - Key: Project
          Value: ${project_name}
        - Key: Environment
          Value: !Ref Environment
        - Key: ManagedBy
          Value: Terraform
  
  # CloudWatch Log Group
  CustomResourceLogGroup:
    Type: AWS::Logs::LogGroup
    Properties:
      LogGroupName: !Sub '/aws/lambda/$${CustomResourceFunction}'
      RetentionInDays: 14
      Tags:
        - Key: Project
          Value: ${project_name}
        - Key: Environment
          Value: !Ref Environment
        - Key: ManagedBy
          Value: Terraform
  
  # The actual custom resource
  CustomResourceDemo:
    Type: AWS::CloudFormation::CustomResource
    Properties:
      ServiceToken: !GetAtt CustomResourceFunction.Arn
      Environment: !Ref Environment
      Version: !Ref ResourceVersion
      BucketName: !Ref S3Bucket
      Project: ${project_name}
      RandomSuffix: ${random_suffix}

Outputs:
  CustomResourceArn:
    Description: ARN of the custom resource Lambda function
    Value: !GetAtt CustomResourceFunction.Arn
    Export:
      Name: !Sub '$${AWS::StackName}-CustomResourceArn'
  
  S3BucketName:
    Description: Name of the S3 bucket
    Value: !Ref S3Bucket
    Export:
      Name: !Sub '$${AWS::StackName}-S3Bucket'
  
  CustomResourceMessage:
    Description: Message from custom resource
    Value: !GetAtt CustomResourceDemo.Message
    Export:
      Name: !Sub '$${AWS::StackName}-Message'