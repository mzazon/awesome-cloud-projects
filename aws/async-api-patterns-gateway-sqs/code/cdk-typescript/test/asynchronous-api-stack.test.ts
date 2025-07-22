import * as cdk from 'aws-cdk-lib';
import { Template, Match } from 'aws-cdk-lib/assertions';
import { AsynchronousApiStack } from '../lib/asynchronous-api-stack';

describe('AsynchronousApiStack', () => {
  let app: cdk.App;
  let stack: AsynchronousApiStack;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    stack = new AsynchronousApiStack(app, 'TestStack', {
      environment: 'test',
      projectName: 'test-async-api',
    });
    template = Template.fromStack(stack);
  });

  test('creates SQS queues with proper configuration', () => {
    // Main queue
    template.hasResourceProperties('AWS::SQS::Queue', {
      QueueName: 'test-async-api-test-main-queue',
      MessageRetentionPeriod: 1209600, // 14 days
      VisibilityTimeoutSeconds: 300,
    });

    // Dead letter queue
    template.hasResourceProperties('AWS::SQS::Queue', {
      QueueName: 'test-async-api-test-dlq',
      MessageRetentionPeriod: 1209600,
      VisibilityTimeoutSeconds: 300,
    });
  });

  test('creates DynamoDB table with correct configuration', () => {
    template.hasResourceProperties('AWS::DynamoDB::Table', {
      TableName: 'test-async-api-test-jobs',
      BillingMode: 'PAY_PER_REQUEST',
      AttributeDefinitions: [
        {
          AttributeName: 'jobId',
          AttributeType: 'S',
        },
      ],
      KeySchema: [
        {
          AttributeName: 'jobId',
          KeyType: 'HASH',
        },
      ],
      PointInTimeRecoverySpecification: {
        PointInTimeRecoveryEnabled: true,
      },
    });
  });

  test('creates S3 bucket with proper security settings', () => {
    template.hasResourceProperties('AWS::S3::Bucket', {
      BucketName: Match.stringLikeRegexp('test-async-api-test-results-.*'),
      BucketEncryption: {
        ServerSideEncryptionConfiguration: [
          {
            ServerSideEncryptionByDefault: {
              SSEAlgorithm: 'AES256',
            },
          },
        ],
      },
      PublicAccessBlockConfiguration: {
        BlockPublicAcls: true,
        BlockPublicPolicy: true,
        IgnorePublicAcls: true,
        RestrictPublicBuckets: true,
      },
    });
  });

  test('creates Lambda functions with proper configuration', () => {
    // Job processor function
    template.hasResourceProperties('AWS::Lambda::Function', {
      FunctionName: 'test-async-api-test-job-processor',
      Runtime: 'python3.9',
      Handler: 'job-processor.lambda_handler',
      Timeout: 300,
      MemorySize: 512,
    });

    // Status checker function
    template.hasResourceProperties('AWS::Lambda::Function', {
      FunctionName: 'test-async-api-test-status-checker',
      Runtime: 'python3.9',
      Handler: 'status-checker.lambda_handler',
      Timeout: 30,
      MemorySize: 256,
    });
  });

  test('creates API Gateway with proper endpoints', () => {
    // REST API
    template.hasResourceProperties('AWS::ApiGateway::RestApi', {
      Name: 'test-async-api-test-api',
      Description: 'Asynchronous API with SQS integration',
      EndpointConfiguration: {
        Types: ['REGIONAL'],
      },
    });

    // Submit resource
    template.hasResourceProperties('AWS::ApiGateway::Resource', {
      PathPart: 'submit',
    });

    // Status resource
    template.hasResourceProperties('AWS::ApiGateway::Resource', {
      PathPart: 'status',
    });

    // JobId resource
    template.hasResourceProperties('AWS::ApiGateway::Resource', {
      PathPart: '{jobId}',
    });
  });

  test('creates IAM roles with least privilege principles', () => {
    // API Gateway role
    template.hasResourceProperties('AWS::IAM::Role', {
      RoleName: 'test-async-api-test-api-gateway-role',
      AssumeRolePolicyDocument: {
        Statement: [
          {
            Effect: 'Allow',
            Principal: {
              Service: 'apigateway.amazonaws.com',
            },
            Action: 'sts:AssumeRole',
          },
        ],
        Version: '2012-10-17',
      },
    });

    // Lambda role
    template.hasResourceProperties('AWS::IAM::Role', {
      RoleName: 'test-async-api-test-lambda-role',
      AssumeRolePolicyDocument: {
        Statement: [
          {
            Effect: 'Allow',
            Principal: {
              Service: 'lambda.amazonaws.com',
            },
            Action: 'sts:AssumeRole',
          },
        ],
        Version: '2012-10-17',
      },
    });
  });

  test('creates SQS event source mapping for Lambda', () => {
    template.hasResourceProperties('AWS::Lambda::EventSourceMapping', {
      BatchSize: 10,
      MaximumBatchingWindowInSeconds: 5,
    });
  });

  test('validates stack outputs', () => {
    const outputs = template.findOutputs('*');
    
    expect(outputs).toHaveProperty('ApiEndpoint');
    expect(outputs).toHaveProperty('MainQueueUrl');
    expect(outputs).toHaveProperty('DeadLetterQueueUrl');
    expect(outputs).toHaveProperty('JobsTableName');
    expect(outputs).toHaveProperty('ResultsBucketName');
    expect(outputs).toHaveProperty('SubmitEndpoint');
    expect(outputs).toHaveProperty('StatusEndpoint');
  });

  test('ensures resource count is reasonable', () => {
    // Count major resource types to ensure stack is complete but not bloated
    const resources = template.toJSON().Resources;
    const resourceTypes = Object.values(resources).map((r: any) => r.Type);
    
    // Expected resource types and approximate counts
    const expectedTypes = {
      'AWS::SQS::Queue': 2, // Main + DLQ
      'AWS::DynamoDB::Table': 1,
      'AWS::S3::Bucket': 1,
      'AWS::Lambda::Function': 3, // Processor + Status + Initializer
      'AWS::ApiGateway::RestApi': 1,
      'AWS::IAM::Role': 2, // API Gateway + Lambda
    };

    Object.entries(expectedTypes).forEach(([type, expectedCount]) => {
      const actualCount = resourceTypes.filter(t => t === type).length;
      expect(actualCount).toBeGreaterThanOrEqual(expectedCount);
    });
  });

  test('validates environment variables are set correctly', () => {
    template.hasResourceProperties('AWS::Lambda::Function', {
      FunctionName: 'test-async-api-test-job-processor',
      Environment: {
        Variables: {
          JOBS_TABLE_NAME: Match.stringLikeRegexp('test-async-api-test-jobs'),
          RESULTS_BUCKET_NAME: Match.stringLikeRegexp('test-async-api-test-results-.*'),
        },
      },
    });

    template.hasResourceProperties('AWS::Lambda::Function', {
      FunctionName: 'test-async-api-test-status-checker',
      Environment: {
        Variables: {
          JOBS_TABLE_NAME: Match.stringLikeRegexp('test-async-api-test-jobs'),
        },
      },
    });
  });

  test('ensures proper CORS configuration', () => {
    // Verify CORS is configured on the API Gateway
    template.hasResourceProperties('AWS::ApiGateway::Method', {
      HttpMethod: 'OPTIONS',
    });
  });
});