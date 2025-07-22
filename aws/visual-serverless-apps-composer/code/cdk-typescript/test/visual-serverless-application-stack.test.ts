import * as cdk from 'aws-cdk-lib';
import { Template, Match } from 'aws-cdk-lib/assertions';
import { VisualServerlessApplicationStack } from '../lib/visual-serverless-application-stack';

describe('VisualServerlessApplicationStack', () => {
  let app: cdk.App;
  let stack: VisualServerlessApplicationStack;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    stack = new VisualServerlessApplicationStack(app, 'TestStack', {
      stage: 'test',
      env: {
        account: '123456789012',
        region: 'us-east-1',
      },
    });
    template = Template.fromStack(stack);
  });

  describe('DynamoDB Table', () => {
    test('should create DynamoDB table with correct configuration', () => {
      template.hasResourceProperties('AWS::DynamoDB::Table', {
        TableName: 'test-users-table',
        AttributeDefinitions: [
          {
            AttributeName: 'id',
            AttributeType: 'S',
          },
        ],
        KeySchema: [
          {
            AttributeName: 'id',
            KeyType: 'HASH',
          },
        ],
        BillingMode: 'PAY_PER_REQUEST',
        SSESpecification: {
          SSEEnabled: true,
        },
        PointInTimeRecoverySpecification: {
          PointInTimeRecoveryEnabled: true,
        },
      });
    });

    test('should have proper tags', () => {
      template.hasResourceProperties('AWS::DynamoDB::Table', {
        Tags: Match.arrayWith([
          {
            Key: 'Environment',
            Value: 'test',
          },
          {
            Key: 'Application',
            Value: 'Visual Serverless App',
          },
        ]),
      });
    });
  });

  describe('Lambda Function', () => {
    test('should create Lambda function with correct configuration', () => {
      template.hasResourceProperties('AWS::Lambda::Function', {
        FunctionName: 'test-users-function',
        Runtime: 'python3.11',
        Handler: 'users.lambda_handler',
        Timeout: 30,
        MemorySize: 256,
        ReservedConcurrencyLimit: 100,
        TracingConfig: {
          Mode: 'Active',
        },
        Environment: {
          Variables: {
            TABLE_NAME: Match.anyValue(),
            LOG_LEVEL: 'INFO',
            STAGE: 'test',
          },
        },
      });
    });

    test('should have dead letter queue configuration', () => {
      template.hasResourceProperties('AWS::Lambda::Function', {
        DeadLetterConfig: {
          TargetArn: Match.anyValue(),
        },
      });
    });

    test('should have proper IAM permissions for DynamoDB', () => {
      template.hasResourceProperties('AWS::IAM::Policy', {
        PolicyDocument: {
          Statement: Match.arrayWith([
            {
              Effect: 'Allow',
              Action: [
                'dynamodb:BatchGetItem',
                'dynamodb:GetRecords',
                'dynamodb:GetShardIterator',
                'dynamodb:Query',
                'dynamodb:GetItem',
                'dynamodb:Scan',
                'dynamodb:ConditionCheckItem',
                'dynamodb:BatchWriteItem',
                'dynamodb:PutItem',
                'dynamodb:UpdateItem',
                'dynamodb:DeleteItem',
                'dynamodb:DescribeTable',
              ],
              Resource: Match.anyValue(),
            },
          ]),
        },
      });
    });

    test('should have proper IAM permissions for X-Ray tracing', () => {
      template.hasResourceProperties('AWS::IAM::Policy', {
        PolicyDocument: {
          Statement: Match.arrayWith([
            {
              Effect: 'Allow',
              Action: ['xray:PutTraceSegments', 'xray:PutTelemetryRecords'],
              Resource: '*',
            },
          ]),
        },
      });
    });
  });

  describe('API Gateway', () => {
    test('should create REST API with correct configuration', () => {
      template.hasResourceProperties('AWS::ApiGateway::RestApi', {
        Name: 'test-serverless-api',
        Description: 'Serverless API for test environment - Visual Serverless Application',
        EndpointConfiguration: {
          Types: ['REGIONAL'],
        },
      });
    });

    test('should create deployment with correct stage', () => {
      template.hasResourceProperties('AWS::ApiGateway::Deployment', {
        StageName: 'test',
      });
    });

    test('should enable tracing on deployment', () => {
      template.hasResourceProperties('AWS::ApiGateway::Stage', {
        TracingEnabled: true,
        DataTraceEnabled: true,
        LoggingLevel: 'INFO',
        MetricsEnabled: true,
        ThrottlingBurstLimit: 1000,
        ThrottlingRateLimit: 500,
      });
    });

    test('should create users resource', () => {
      template.hasResourceProperties('AWS::ApiGateway::Resource', {
        PathPart: 'users',
      });
    });

    test('should create GET method for users', () => {
      template.hasResourceProperties('AWS::ApiGateway::Method', {
        HttpMethod: 'GET',
        ResourceId: Match.anyValue(),
        RestApiId: Match.anyValue(),
        Integration: {
          Type: 'AWS_PROXY',
          IntegrationHttpMethod: 'POST',
          Uri: Match.anyValue(),
        },
      });
    });

    test('should create POST method for users', () => {
      template.hasResourceProperties('AWS::ApiGateway::Method', {
        HttpMethod: 'POST',
        ResourceId: Match.anyValue(),
        RestApiId: Match.anyValue(),
        Integration: {
          Type: 'AWS_PROXY',
          IntegrationHttpMethod: 'POST',
          Uri: Match.anyValue(),
        },
      });
    });

    test('should have CORS configuration', () => {
      template.hasResourceProperties('AWS::ApiGateway::Method', {
        HttpMethod: 'OPTIONS',
        Integration: {
          Type: 'MOCK',
          IntegrationResponses: [
            {
              StatusCode: '200',
              ResponseParameters: {
                'method.response.header.Access-Control-Allow-Headers': "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
                'method.response.header.Access-Control-Allow-Methods': "'GET,POST,PUT,DELETE,OPTIONS'",
                'method.response.header.Access-Control-Allow-Origin': "'*'",
              },
            },
          ],
        },
      });
    });
  });

  describe('SQS Dead Letter Queue', () => {
    test('should create SQS queue with correct configuration', () => {
      template.hasResourceProperties('AWS::SQS::Queue', {
        QueueName: 'test-users-dlq',
        MessageRetentionPeriod: 1209600, // 14 days
        VisibilityTimeoutSeconds: 60,
        SqsManagedSseEnabled: true,
      });
    });
  });

  describe('CloudWatch Log Group', () => {
    test('should create log group with correct configuration', () => {
      template.hasResourceProperties('AWS::Logs::LogGroup', {
        LogGroupName: '/aws/lambda/test-users-function',
        RetentionInDays: 14,
      });
    });
  });

  describe('CloudWatch Dashboard', () => {
    test('should create CloudWatch dashboard', () => {
      template.hasResourceProperties('AWS::CloudWatch::Dashboard', {
        DashboardName: 'test-visual-serverless-app-dashboard',
        DashboardBody: Match.anyValue(),
      });
    });
  });

  describe('Stack Outputs', () => {
    test('should create API endpoint output', () => {
      template.hasOutput('ApiEndpoint', {
        Description: 'API Gateway endpoint URL',
        Export: {
          Name: 'TestStack-ApiEndpoint',
        },
      });
    });

    test('should create DynamoDB table name output', () => {
      template.hasOutput('DynamoDBTableName', {
        Description: 'DynamoDB table name for users',
        Export: {
          Name: 'TestStack-UsersTable',
        },
      });
    });

    test('should create Lambda function ARN output', () => {
      template.hasOutput('LambdaFunctionArn', {
        Description: 'Lambda function ARN',
        Export: {
          Name: 'TestStack-UsersFunction',
        },
      });
    });

    test('should create dead letter queue URL output', () => {
      template.hasOutput('DeadLetterQueueUrl', {
        Description: 'Dead Letter Queue URL',
        Export: {
          Name: 'TestStack-DeadLetterQueue',
        },
      });
    });

    test('should create CloudWatch dashboard URL output', () => {
      template.hasOutput('CloudWatchDashboardUrl', {
        Description: 'CloudWatch Dashboard URL',
      });
    });
  });

  describe('Resource Count', () => {
    test('should create expected number of resources', () => {
      // Count key resources to ensure completeness
      template.resourceCountIs('AWS::DynamoDB::Table', 1);
      template.resourceCountIs('AWS::Lambda::Function', 1);
      template.resourceCountIs('AWS::ApiGateway::RestApi', 1);
      template.resourceCountIs('AWS::SQS::Queue', 1);
      template.resourceCountIs('AWS::Logs::LogGroup', 1);
      template.resourceCountIs('AWS::CloudWatch::Dashboard', 1);
    });
  });

  describe('Environment-specific Configuration', () => {
    test('should configure production environment with retention policy', () => {
      const prodApp = new cdk.App();
      const prodStack = new VisualServerlessApplicationStack(prodApp, 'ProdStack', {
        stage: 'prod',
        env: {
          account: '123456789012',
          region: 'us-east-1',
        },
      });
      const prodTemplate = Template.fromStack(prodStack);

      prodTemplate.hasResourceProperties('AWS::DynamoDB::Table', {
        DeletionProtectionEnabled: true,
      });
    });

    test('should configure development environment without retention policy', () => {
      const devApp = new cdk.App();
      const devStack = new VisualServerlessApplicationStack(devApp, 'DevStack', {
        stage: 'dev',
        env: {
          account: '123456789012',
          region: 'us-east-1',
        },
      });
      const devTemplate = Template.fromStack(devStack);

      devTemplate.hasResourceProperties('AWS::DynamoDB::Table', {
        DeletionProtectionEnabled: Match.absent(),
      });
    });
  });

  describe('Security Configuration', () => {
    test('should enable encryption on DynamoDB table', () => {
      template.hasResourceProperties('AWS::DynamoDB::Table', {
        SSESpecification: {
          SSEEnabled: true,
        },
      });
    });

    test('should enable encryption on SQS queue', () => {
      template.hasResourceProperties('AWS::SQS::Queue', {
        SqsManagedSseEnabled: true,
      });
    });

    test('should enable X-Ray tracing on Lambda function', () => {
      template.hasResourceProperties('AWS::Lambda::Function', {
        TracingConfig: {
          Mode: 'Active',
        },
      });
    });

    test('should enable tracing on API Gateway', () => {
      template.hasResourceProperties('AWS::ApiGateway::Stage', {
        TracingEnabled: true,
      });
    });
  });
});