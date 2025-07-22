AWSTemplateFormatVersion: '2010-09-09'
Description: 'Demo stack with Lambda-backed custom resource - Managed by Terraform'

Parameters:
  LambdaFunctionArn:
    Type: String
    Description: ARN of the Lambda function for custom resource
    Default: ${lambda_function_arn}
  S3BucketName:
    Type: String
    Description: S3 bucket name for data storage
    Default: ${s3_bucket_name}
  DataFileName:
    Type: String
    Default: ${data_file_name}
    Description: Name of the data file to create
  CustomDataContent:
    Type: String
    Default: '${custom_data_content}'
    Description: JSON content for the custom data

Resources:
  # Custom Resource that uses Lambda function
  CustomDataResource:
    Type: AWS::CloudFormation::CustomResource
    Properties:
      ServiceToken: !Ref LambdaFunctionArn
      BucketName: !Ref S3BucketName
      FileName: !Ref DataFileName
      DataContent: !Ref CustomDataContent
      Version: '1.0'  # Change this to trigger updates
      Project: ${project_name}
      Environment: ${environment}
      RandomSuffix: ${random_suffix}

  # CloudWatch Log Group for monitoring
  CustomResourceLogGroup:
    Type: AWS::Logs::LogGroup
    Properties:
      LogGroupName: !Sub '/aws/cloudformation/${project_name}-${environment}-${random_suffix}'
      RetentionInDays: 7

Outputs:
  CustomResourceDataUrl:
    Description: URL of the data file created by custom resource
    Value: !GetAtt CustomDataResource.DataUrl
    Export:
      Name: !Sub '$${AWS::StackName}-DataUrl'
  
  CustomResourceFileName:
    Description: Name of the file created by custom resource
    Value: !GetAtt CustomDataResource.FileName
    Export:
      Name: !Sub '$${AWS::StackName}-FileName'
  
  CustomResourceBucketName:
    Description: Bucket name used by custom resource
    Value: !GetAtt CustomDataResource.BucketName
    Export:
      Name: !Sub '$${AWS::StackName}-BucketName'
  
  CreatedAt:
    Description: Timestamp when resource was created
    Value: !GetAtt CustomDataResource.CreatedAt
    Export:
      Name: !Sub '$${AWS::StackName}-CreatedAt'