import * as cdk from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { ApplicationStack } from '../lib/application-stack';

describe('ApplicationStack', () => {
  let app: cdk.App;
  let devStack: ApplicationStack;
  let prodStack: ApplicationStack;
  let devTemplate: Template;
  let prodTemplate: Template;

  beforeEach(() => {
    app = new cdk.App();
    
    devStack = new ApplicationStack(app, 'TestDevApplicationStack', {
      environment: 'dev',
      applicationName: 'test-app',
    });

    prodStack = new ApplicationStack(app, 'TestProdApplicationStack', {
      environment: 'prod',
      applicationName: 'test-app',
    });

    devTemplate = Template.fromStack(devStack);
    prodTemplate = Template.fromStack(prodStack);
  });

  test('should create S3 bucket', () => {
    devTemplate.hasResourceProperties('AWS::S3::Bucket', {
      BucketName: expect.stringMatching(/test-app-dev-.*/),
      VersioningConfiguration: {
        Status: 'Enabled',
      },
      BucketEncryption: {
        ServerSideEncryptionConfiguration: [
          {
            ServerSideEncryptionByDefault: {
              SSEAlgorithm: 'AES256',
            },
          },
        ],
      },
    });
  });

  test('should create DynamoDB table', () => {
    devTemplate.hasResourceProperties('AWS::DynamoDB::Table', {
      TableName: 'test-app-dev-table',
      AttributeDefinitions: [
        {
          AttributeName: 'id',
          AttributeType: 'S',
        },
        {
          AttributeName: 'timestamp',
          AttributeType: 'N',
        },
      ],
      KeySchema: [
        {
          AttributeName: 'id',
          KeyType: 'HASH',
        },
        {
          AttributeName: 'timestamp',
          KeyType: 'RANGE',
        },
      ],
      BillingMode: 'PAY_PER_REQUEST',
    });
  });

  test('should create Lambda function', () => {
    devTemplate.hasResourceProperties('AWS::Lambda::Function', {
      FunctionName: 'test-app-dev-function',
      Runtime: 'nodejs18.x',
      Handler: 'index.handler',
      Timeout: 30,
      MemorySize: 256,
    });
  });

  test('should create API Gateway', () => {
    devTemplate.hasResourceProperties('AWS::ApiGateway::RestApi', {
      Name: 'test-app-dev-api',
      Description: 'API for test-app dev environment',
    });
  });

  test('should have different removal policies for dev and prod', () => {
    // Dev stack should have DESTROY removal policy
    devTemplate.hasResource('AWS::S3::Bucket', {
      DeletionPolicy: 'Delete',
    });

    // Prod stack should have RETAIN removal policy
    prodTemplate.hasResource('AWS::S3::Bucket', {
      DeletionPolicy: 'Retain',
    });
  });

  test('should enable point-in-time recovery for production DynamoDB', () => {
    prodTemplate.hasResourceProperties('AWS::DynamoDB::Table', {
      PointInTimeRecoverySpecification: {
        PointInTimeRecoveryEnabled: true,
      },
    });

    // Dev should not have point-in-time recovery
    devTemplate.hasResourceProperties('AWS::DynamoDB::Table', {
      PointInTimeRecoverySpecification: {
        PointInTimeRecoveryEnabled: false,
      },
    });
  });

  test('should create Lambda permissions for API Gateway', () => {
    devTemplate.hasResourceProperties('AWS::Lambda::Permission', {
      Action: 'lambda:InvokeFunction',
      Principal: 'apigateway.amazonaws.com',
    });
  });

  test('should create IAM role for Lambda with correct permissions', () => {
    devTemplate.hasResourceProperties('AWS::IAM::Role', {
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

  test('should create API Gateway methods', () => {
    // Root GET method
    devTemplate.hasResourceProperties('AWS::ApiGateway::Method', {
      HttpMethod: 'GET',
      ResourceId: {
        'Fn::GetAtt': [
          expect.stringMatching(/ApplicationApi.*/),
          'RootResourceId',
        ],
      },
    });

    // Items resource methods
    devTemplate.hasResourceProperties('AWS::ApiGateway::Method', {
      HttpMethod: 'POST',
    });
  });

  test('should create outputs', () => {
    devTemplate.hasOutput('ApiUrl', {
      Description: 'API Gateway URL for dev environment',
    });

    devTemplate.hasOutput('BucketName', {
      Description: 'S3 bucket name for dev environment',
    });

    devTemplate.hasOutput('TableName', {
      Description: 'DynamoDB table name for dev environment',
    });

    devTemplate.hasOutput('LambdaFunctionName', {
      Description: 'Lambda function name for dev environment',
    });
  });

  test('should have correct tags', () => {
    const resources = devTemplate.findResources('AWS::S3::Bucket');
    const bucketResource = Object.values(resources)[0];
    
    expect(bucketResource.Properties.Tags).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          Key: 'Environment',
          Value: 'dev',
        }),
        expect.objectContaining({
          Key: 'Application',
          Value: 'test-app',
        }),
        expect.objectContaining({
          Key: 'ManagedBy',
          Value: 'CDK',
        }),
      ])
    );
  });

  test('should have CORS configuration', () => {
    devTemplate.hasResourceProperties('AWS::ApiGateway::RestApi', {
      Policy: expect.any(Object),
    });
  });

  test('should have Lambda environment variables', () => {
    devTemplate.hasResourceProperties('AWS::Lambda::Function', {
      Environment: {
        Variables: {
          TABLE_NAME: expect.any(Object),
          BUCKET_NAME: expect.any(Object),
          ENVIRONMENT: 'dev',
        },
      },
    });
  });
});