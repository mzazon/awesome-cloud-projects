import * as cdk from 'aws-cdk-lib';
import { Template, Match } from 'aws-cdk-lib/assertions';
import { EventDrivenMicroservicesStack } from '../lib/event-driven-microservices-stack';

describe('EventDrivenMicroservicesStack', () => {
  let app: cdk.App;
  let stack: EventDrivenMicroservicesStack;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    stack = new EventDrivenMicroservicesStack(app, 'TestStack', {
      projectName: 'test-project',
      environment: 'test',
    });
    template = Template.fromStack(stack);
  });

  describe('DynamoDB Resources', () => {
    test('creates DynamoDB table with correct configuration', () => {
      template.hasResourceProperties('AWS::DynamoDB::Table', {
        AttributeDefinitions: [
          {
            AttributeName: 'orderId',
            AttributeType: 'S',
          },
          {
            AttributeName: 'customerId',
            AttributeType: 'S',
          },
        ],
        KeySchema: [
          {
            AttributeName: 'orderId',
            KeyType: 'HASH',
          },
          {
            AttributeName: 'customerId',
            KeyType: 'RANGE',
          },
        ],
        ProvisionedThroughput: {
          ReadCapacityUnits: 5,
          WriteCapacityUnits: 5,
        },
      });
    });

    test('creates Global Secondary Index for customer queries', () => {
      template.hasResourceProperties('AWS::DynamoDB::Table', {
        GlobalSecondaryIndexes: [
          {
            IndexName: 'CustomerId-Index',
            KeySchema: [
              {
                AttributeName: 'customerId',
                KeyType: 'HASH',
              },
            ],
            ProvisionedThroughput: {
              ReadCapacityUnits: 5,
              WriteCapacityUnits: 5,
            },
            Projection: {
              ProjectionType: 'ALL',
            },
          },
        ],
      });
    });
  });

  describe('EventBridge Resources', () => {
    test('creates custom event bus', () => {
      template.hasResourceProperties('AWS::Events::EventBus', {
        Name: Match.stringLikeRegexp('test-project-eventbus-.*'),
      });
    });

    test('creates event rules for order processing', () => {
      template.hasResourceProperties('AWS::Events::Rule', {
        EventPattern: {
          source: ['order.service'],
          'detail-type': ['Order Created'],
        },
        State: 'ENABLED',
      });
    });

    test('creates event rules for payment processing', () => {
      template.hasResourceProperties('AWS::Events::Rule', {
        EventPattern: {
          source: ['payment.service'],
          'detail-type': ['Payment Processed', 'Payment Failed'],
        },
        State: 'ENABLED',
      });
    });
  });

  describe('Lambda Functions', () => {
    test('creates all four microservice Lambda functions', () => {
      // Order Service
      template.hasResourceProperties('AWS::Lambda::Function', {
        FunctionName: Match.stringLikeRegexp('test-project-order-service-.*'),
        Runtime: 'python3.9',
        Handler: 'index.lambda_handler',
        Timeout: 30,
        MemorySize: 256,
      });

      // Payment Service
      template.hasResourceProperties('AWS::Lambda::Function', {
        FunctionName: Match.stringLikeRegexp('test-project-payment-service-.*'),
        Runtime: 'python3.9',
        Handler: 'index.lambda_handler',
        Timeout: 30,
        MemorySize: 256,
      });

      // Inventory Service
      template.hasResourceProperties('AWS::Lambda::Function', {
        FunctionName: Match.stringLikeRegexp('test-project-inventory-service-.*'),
        Runtime: 'python3.9',
        Handler: 'index.lambda_handler',
        Timeout: 30,
        MemorySize: 256,
      });

      // Notification Service
      template.hasResourceProperties('AWS::Lambda::Function', {
        FunctionName: Match.stringLikeRegexp('test-project-notification-service-.*'),
        Runtime: 'python3.9',
        Handler: 'index.lambda_handler',
        Timeout: 30,
        MemorySize: 256,
      });
    });

    test('configures environment variables for Lambda functions', () => {
      template.hasResourceProperties('AWS::Lambda::Function', {
        Environment: {
          Variables: {
            EVENTBUS_NAME: Match.anyValue(),
            DYNAMODB_TABLE_NAME: Match.anyValue(),
          },
        },
      });
    });
  });

  describe('Step Functions', () => {
    test('creates state machine for order processing', () => {
      template.hasResourceProperties('AWS::StepFunctions::StateMachine', {
        StateMachineName: Match.stringLikeRegexp('test-project-order-processing-.*'),
        StateMachineType: 'STANDARD',
      });
    });

    test('configures CloudWatch logging for state machine', () => {
      template.hasResourceProperties('AWS::StepFunctions::StateMachine', {
        LoggingConfiguration: {
          Level: 'ALL',
          IncludeExecutionData: true,
          Destinations: [
            {
              CloudWatchLogsLogGroup: {
                LogGroupArn: Match.anyValue(),
              },
            },
          ],
        },
      });
    });
  });

  describe('IAM Roles and Policies', () => {
    test('creates Lambda execution role with appropriate policies', () => {
      template.hasResourceProperties('AWS::IAM::Role', {
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
        },
        ManagedPolicyArns: [
          {
            'Fn::Join': [
              '',
              [
                'arn:',
                { Ref: 'AWS::Partition' },
                ':iam::aws:policy/service-role/AWSLambdaBasicExecutionRole',
              ],
            ],
          },
        ],
      });
    });

    test('creates Step Functions execution role', () => {
      template.hasResourceProperties('AWS::IAM::Role', {
        AssumeRolePolicyDocument: {
          Statement: [
            {
              Effect: 'Allow',
              Principal: {
                Service: 'states.amazonaws.com',
              },
              Action: 'sts:AssumeRole',
            },
          ],
        },
      });
    });
  });

  describe('CloudWatch Resources', () => {
    test('creates CloudWatch dashboard', () => {
      template.hasResourceProperties('AWS::CloudWatch::Dashboard', {
        DashboardName: Match.stringLikeRegexp('test-project-microservices-dashboard-.*'),
      });
    });

    test('creates CloudWatch log group for Step Functions', () => {
      template.hasResourceProperties('AWS::Logs::LogGroup', {
        LogGroupName: Match.stringLikeRegexp('/aws/stepfunctions/test-project-order-processing-.*'),
        RetentionInDays: 14,
      });
    });
  });

  describe('Stack Outputs', () => {
    test('creates all required stack outputs', () => {
      const outputs = template.findOutputs('*');
      
      expect(outputs).toHaveProperty('EventBusName');
      expect(outputs).toHaveProperty('EventBusArn');
      expect(outputs).toHaveProperty('DynamoDBTableName');
      expect(outputs).toHaveProperty('StateMachineArn');
      expect(outputs).toHaveProperty('OrderServiceName');
      expect(outputs).toHaveProperty('PaymentServiceName');
      expect(outputs).toHaveProperty('InventoryServiceName');
      expect(outputs).toHaveProperty('NotificationServiceName');
      expect(outputs).toHaveProperty('DashboardURL');
    });
  });

  describe('Resource Count Validation', () => {
    test('creates expected number of resources', () => {
      // Count key resource types
      const resources = template.toJSON().Resources;
      const resourceTypes = Object.values(resources).map((resource: any) => resource.Type);
      
      // Lambda Functions (4)
      expect(resourceTypes.filter(type => type === 'AWS::Lambda::Function')).toHaveLength(4);
      
      // DynamoDB Table (1)
      expect(resourceTypes.filter(type => type === 'AWS::DynamoDB::Table')).toHaveLength(1);
      
      // EventBridge Event Bus (1)
      expect(resourceTypes.filter(type => type === 'AWS::Events::EventBus')).toHaveLength(1);
      
      // EventBridge Rules (2)
      expect(resourceTypes.filter(type => type === 'AWS::Events::Rule')).toHaveLength(2);
      
      // Step Functions State Machine (1)
      expect(resourceTypes.filter(type => type === 'AWS::StepFunctions::StateMachine')).toHaveLength(1);
      
      // IAM Roles (2 minimum - Lambda and Step Functions)
      expect(resourceTypes.filter(type => type === 'AWS::IAM::Role').length).toBeGreaterThanOrEqual(2);
      
      // CloudWatch Dashboard (1)
      expect(resourceTypes.filter(type => type === 'AWS::CloudWatch::Dashboard')).toHaveLength(1);
      
      // CloudWatch Log Group (1)
      expect(resourceTypes.filter(type => type === 'AWS::Logs::LogGroup')).toHaveLength(1);
    });
  });
});