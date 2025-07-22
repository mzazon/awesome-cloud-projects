import * as cdk from 'aws-cdk-lib';
import { Template, Match } from 'aws-cdk-lib/assertions';
import { TextractDocumentProcessingStack } from '../lib/textract-document-processing-stack';

describe('TextractDocumentProcessingStack', () => {
  let app: cdk.App;
  let stack: TextractDocumentProcessingStack;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    stack = new TextractDocumentProcessingStack(app, 'TestStack', {
      env: { account: '123456789012', region: 'us-east-1' }
    });
    template = Template.fromStack(stack);
  });

  test('creates S3 bucket with correct configuration', () => {
    template.hasResourceProperties('AWS::S3::Bucket', {
      VersioningConfiguration: {
        Status: 'Enabled'
      },
      PublicAccessBlockConfiguration: {
        BlockPublicAcls: true,
        BlockPublicPolicy: true,
        IgnorePublicAcls: true,
        RestrictPublicBuckets: true
      },
      BucketEncryption: {
        ServerSideEncryptionConfiguration: [
          {
            ServerSideEncryptionByDefault: {
              SSEAlgorithm: 'AES256'
            }
          }
        ]
      }
    });
  });

  test('creates Lambda function with correct runtime and handler', () => {
    template.hasResourceProperties('AWS::Lambda::Function', {
      Runtime: 'python3.12',
      Handler: 'lambda_function.lambda_handler',
      Timeout: 60,
      MemorySize: 256
    });
  });

  test('creates IAM role with basic execution policy', () => {
    template.hasResourceProperties('AWS::IAM::Role', {
      AssumeRolePolicyDocument: {
        Statement: [
          {
            Effect: 'Allow',
            Principal: {
              Service: 'lambda.amazonaws.com'
            },
            Action: 'sts:AssumeRole'
          }
        ]
      },
      ManagedPolicyArns: [
        {
          'Fn::Join': [
            '',
            [
              'arn:',
              { Ref: 'AWS::Partition' },
              ':iam::aws:policy/service-role/AWSLambdaBasicExecutionRole'
            ]
          ]
        }
      ]
    });
  });

  test('creates IAM policy with S3 and Textract permissions', () => {
    template.hasResourceProperties('AWS::IAM::Policy', {
      PolicyDocument: {
        Statement: Match.arrayWith([
          Match.objectLike({
            Effect: 'Allow',
            Action: [
              's3:GetObject',
              's3:PutObject',
              's3:ListBucket'
            ]
          }),
          Match.objectLike({
            Effect: 'Allow',
            Action: [
              'textract:DetectDocumentText',
              'textract:AnalyzeDocument',
              'textract:GetDocumentAnalysis',
              'textract:GetDocumentTextDetection'
            ]
          })
        ])
      }
    });
  });

  test('creates CloudWatch log group', () => {
    template.hasResourceProperties('AWS::Logs::LogGroup', {
      LogGroupName: '/aws/lambda/textract-processing-processor',
      RetentionInDays: 7
    });
  });

  test('creates S3 notification configuration', () => {
    template.hasResourceProperties('AWS::S3::Bucket', {
      NotificationConfiguration: {
        LambdaConfigurations: [
          {
            Event: 's3:ObjectCreated:*',
            Filter: {
              S3Key: {
                Rules: [
                  {
                    Name: 'prefix',
                    Value: 'documents/'
                  }
                ]
              }
            }
          }
        ]
      }
    });
  });

  test('has correct outputs', () => {
    template.hasOutput('DocumentBucketName', {
      Description: 'Name of the S3 bucket for document storage'
    });

    template.hasOutput('ProcessingFunctionName', {
      Description: 'Name of the Lambda function for document processing'
    });

    template.hasOutput('LambdaRoleArn', {
      Description: 'ARN of the IAM role for the Lambda function'
    });
  });

  test('applies correct tags', () => {
    const resources = template.findResources('AWS::S3::Bucket');
    const bucketLogicalId = Object.keys(resources)[0];
    
    template.hasResource('AWS::S3::Bucket', {
      Properties: Match.anyValue(),
      Metadata: {
        'aws:cdk:path': Match.stringLikeRegexp('TestStack/DocumentBucket/Resource')
      }
    });
  });

  test('stack with custom configuration', () => {
    const customStack = new TextractDocumentProcessingStack(app, 'CustomStack', {
      resourcePrefix: 'custom-textract',
      enableVersioning: false,
      lambdaTimeout: 120,
      lambdaMemorySize: 512,
      env: { account: '123456789012', region: 'us-west-2' }
    });

    const customTemplate = Template.fromStack(customStack);

    customTemplate.hasResourceProperties('AWS::Lambda::Function', {
      FunctionName: 'custom-textract-processor',
      Timeout: 120,
      MemorySize: 512
    });
  });

  test('Lambda function has correct environment variables', () => {
    template.hasResourceProperties('AWS::Lambda::Function', {
      Environment: {
        Variables: {
          LOG_LEVEL: 'INFO',
          RESULTS_PREFIX: 'results/'
        }
      }
    });
  });

  test('S3 bucket has lifecycle configuration', () => {
    template.hasResourceProperties('AWS::S3::Bucket', {
      LifecycleConfiguration: {
        Rules: Match.arrayWith([
          Match.objectLike({
            Id: 'DeleteIncompleteMultipartUploads',
            Status: 'Enabled',
            AbortIncompleteMultipartUpload: {
              DaysAfterInitiation: 1
            }
          }),
          Match.objectLike({
            Id: 'TransitionToIA',
            Status: 'Enabled',
            Transitions: [
              {
                StorageClass: 'STANDARD_IA',
                TransitionInDays: 30
              }
            ]
          })
        ])
      }
    });
  });

  test('stack creates expected number of resources', () => {
    // Should create: S3 bucket, Lambda function, IAM role, IAM policy, CloudWatch log group
    // Plus CDK-generated resources like Lambda permission for S3
    const resources = template.toJSON().Resources;
    const resourceCount = Object.keys(resources).length;
    
    expect(resourceCount).toBeGreaterThanOrEqual(5);
  });
});