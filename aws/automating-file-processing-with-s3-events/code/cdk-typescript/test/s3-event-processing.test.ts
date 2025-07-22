import * as cdk from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { S3EventProcessingStack } from '../lib/s3-event-processing-stack';

describe('S3EventProcessingStack', () => {
  let app: cdk.App;
  let stack: S3EventProcessingStack;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    stack = new S3EventProcessingStack(app, 'TestS3EventProcessingStack', {
      environment: 'test',
      enableEncryption: false,
      logRetentionDays: 7,
    });
    template = Template.fromStack(stack);
  });

  test('S3 Bucket is created', () => {
    template.hasResourceProperties('AWS::S3::Bucket', {
      PublicAccessBlockConfiguration: {
        BlockPublicAcls: true,
        BlockPublicPolicy: true,
        IgnorePublicAcls: true,
        RestrictPublicBuckets: true,
      },
      VersioningConfiguration: {
        Status: 'Enabled',
      },
    });
  });

  test('SNS Topic is created', () => {
    template.hasResourceProperties('AWS::SNS::Topic', {
      DisplayName: 'File Processing Notifications',
    });
  });

  test('SQS Queue is created with DLQ', () => {
    // Main queue
    template.hasResourceProperties('AWS::SQS::Queue', {
      VisibilityTimeoutSeconds: 300,
      ReceiveMessageWaitTimeSeconds: 20,
    });

    // Dead letter queue
    template.hasResourceProperties('AWS::SQS::Queue', {
      MessageRetentionPeriod: 1209600, // 14 days
    });
  });

  test('Lambda Function is created', () => {
    template.hasResourceProperties('AWS::Lambda::Function', {
      Runtime: 'python3.9',
      Timeout: 30,
      MemorySize: 256,
      ReservedConcurrentExecutions: 100,
      TracingConfig: {
        Mode: 'Active',
      },
    });
  });

  test('Lambda Function has required environment variables', () => {
    template.hasResourceProperties('AWS::Lambda::Function', {
      Environment: {
        Variables: {
          ENVIRONMENT: 'test',
        },
      },
    });
  });

  test('S3 Bucket has lifecycle rules', () => {
    template.hasResourceProperties('AWS::S3::Bucket', {
      LifecycleConfiguration: {
        Rules: [
          {
            Id: 'TransitionToIA',
            Status: 'Enabled',
            Transitions: [
              {
                StorageClass: 'STANDARD_IA',
                TransitionInDays: 30,
              },
              {
                StorageClass: 'GLACIER',
                TransitionInDays: 90,
              },
            ],
          },
        ],
      },
    });
  });

  test('CloudWatch Log Group is created', () => {
    template.hasResourceProperties('AWS::Logs::LogGroup', {
      RetentionInDays: 30,
    });
  });

  test('IAM Role is created for Lambda', () => {
    template.hasResourceProperties('AWS::IAM::Role', {
      AssumeRolePolicyDocument: {
        Statement: [
          {
            Action: 'sts:AssumeRole',
            Effect: 'Allow',
            Principal: {
              Service: 'lambda.amazonaws.com',
            },
          },
        ],
      },
    });
  });

  test('S3 bucket notifications are configured', () => {
    // Check for Lambda permission for S3
    template.hasResourceProperties('AWS::Lambda::Permission', {
      Action: 'lambda:InvokeFunction',
      Principal: 's3.amazonaws.com',
    });
  });

  test('Stack outputs are created', () => {
    const outputs = template.findOutputs('*');
    
    expect(outputs).toHaveProperty('BucketName');
    expect(outputs).toHaveProperty('BucketArn');
    expect(outputs).toHaveProperty('SnsTopicArn');
    expect(outputs).toHaveProperty('SqsQueueUrl');
    expect(outputs).toHaveProperty('SqsQueueArn');
    expect(outputs).toHaveProperty('LambdaFunctionArn');
    expect(outputs).toHaveProperty('LambdaFunctionName');
  });

  test('Encryption can be disabled', () => {
    const testApp = new cdk.App();
    const testStack = new S3EventProcessingStack(testApp, 'TestEncryptionStack', {
      environment: 'test',
      enableEncryption: false,
      logRetentionDays: 7,
    });
    const testTemplate = Template.fromStack(testStack);

    // S3 bucket should not have encryption enabled
    testTemplate.hasResourceProperties('AWS::S3::Bucket', {
      BucketEncryption: cdk.Match.absent(),
    });
  });

  test('Production environment retains resources', () => {
    const prodApp = new cdk.App();
    const prodStack = new S3EventProcessingStack(prodApp, 'ProdS3EventProcessingStack', {
      environment: 'prod',
      enableEncryption: true,
      logRetentionDays: 90,
    });
    const prodTemplate = Template.fromStack(prodStack);

    // Should have DeletionPolicy for production
    prodTemplate.hasResource('AWS::S3::Bucket', {
      DeletionPolicy: 'Retain',
    });
  });
});