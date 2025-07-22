import * as cdk from 'aws-cdk-lib';
import { Template, Match } from 'aws-cdk-lib/assertions';
import { ServerlessWebAppStack } from '../lib/serverless-web-app-stack';

describe('ServerlessWebAppStack', () => {
  let app: cdk.App;
  let stack: ServerlessWebAppStack;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    stack = new ServerlessWebAppStack(app, 'TestStack', {
      env: {
        account: '123456789012',
        region: 'us-east-1',
      },
    });
    template = Template.fromStack(stack);
  });

  describe('DynamoDB Table', () => {
    test('creates DynamoDB table with correct configuration', () => {
      template.hasResourceProperties('AWS::DynamoDB::Table', {
        BillingMode: 'PAY_PER_REQUEST',
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
        PointInTimeRecoverySpecification: {
          PointInTimeRecoveryEnabled: true,
        },
        SSESpecification: {
          SSEEnabled: true,
        },
      });
    });

    test('table has proper tags', () => {
      template.hasResourceProperties('AWS::DynamoDB::Table', {
        Tags: Match.arrayWith([
          {
            Key: 'Purpose',
            Value: 'TodoStorage',
          },
        ]),
      });
    });
  });

  describe('Cognito User Pool', () => {
    test('creates user pool with correct configuration', () => {
      template.hasResourceProperties('AWS::Cognito::UserPool', {
        AutoVerifiedAttributes: ['email'],
        UsernameAttributes: ['email', 'username'],
        UserPoolAddOns: {
          AdvancedSecurityMode: 'OFF',
        },
        Policies: {
          PasswordPolicy: {
            MinimumLength: 8,
            RequireLowercase: true,
            RequireNumbers: true,
            RequireSymbols: false,
            RequireUppercase: true,
          },
        },
        AccountRecoverySetting: {
          RecoveryMechanisms: [
            {
              Name: 'verified_email',
              Priority: 1,
            },
          ],
        },
      });
    });

    test('creates user pool client with correct configuration', () => {
      template.hasResourceProperties('AWS::Cognito::UserPoolClient', {
        ExplicitAuthFlows: [
          'ALLOW_ADMIN_USER_PASSWORD_AUTH',
          'ALLOW_USER_PASSWORD_AUTH',
          'ALLOW_USER_SRP_AUTH',
          'ALLOW_REFRESH_TOKEN_AUTH',
        ],
        GenerateSecret: false,
        PreventUserExistenceErrors: 'ENABLED',
        RefreshTokenValidity: 30,
        AccessTokenValidity: 60,
        IdTokenValidity: 60,
        TokenValidityUnits: {
          AccessToken: 'minutes',
          IdToken: 'minutes',
          RefreshToken: 'days',
        },
      });
    });
  });

  describe('Lambda Function', () => {
    test('creates Lambda function with correct runtime and configuration', () => {
      template.hasResourceProperties('AWS::Lambda::Function', {
        Runtime: 'nodejs18.x',
        Handler: 'index.handler',
        Timeout: 30,
        MemorySize: 256,
        Environment: {
          Variables: {
            TODO_TABLE_NAME: Match.anyValue(),
            USER_POOL_ID: Match.anyValue(),
            CORS_ORIGIN: '*',
            LOG_LEVEL: 'INFO',
          },
        },
      });
    });

    test('Lambda function has proper IAM permissions for DynamoDB', () => {
      template.hasResourceProperties('AWS::IAM::Policy', {
        PolicyDocument: {
          Statement: Match.arrayWith([
            Match.objectLike({
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
            }),
          ]),
        },
      });
    });

    test('Lambda function has proper IAM permissions for Cognito', () => {
      template.hasResourceProperties('AWS::IAM::Policy', {
        PolicyDocument: {
          Statement: Match.arrayWith([
            Match.objectLike({
              Effect: 'Allow',
              Action: ['cognito-idp:GetUser', 'cognito-idp:AdminGetUser'],
            }),
          ]),
        },
      });
    });
  });

  describe('API Gateway', () => {
    test('creates REST API with correct configuration', () => {
      template.hasResourceProperties('AWS::ApiGateway::RestApi', {
        EndpointConfiguration: {
          Types: ['REGIONAL'],
        },
      });
    });

    test('creates deployment with correct stage configuration', () => {
      template.hasResourceProperties('AWS::ApiGateway::Deployment', {
        StageName: 'prod',
      });
    });

    test('creates stage with correct configuration', () => {
      template.hasResourceProperties('AWS::ApiGateway::Stage', {
        StageName: 'prod',
        MethodSettings: [
          {
            DataTraceEnabled: true,
            HttpMethod: '*',
            LoggingLevel: 'INFO',
            MetricsEnabled: true,
            ResourcePath: '/*',
            ThrottlingBurstLimit: 1000,
            ThrottlingRateLimit: 500,
          },
        ],
      });
    });

    test('creates Cognito authorizer', () => {
      template.hasResourceProperties('AWS::ApiGateway::Authorizer', {
        Type: 'COGNITO_USER_POOLS',
        IdentitySource: 'method.request.header.Authorization',
        ProviderARNs: [Match.anyValue()],
      });
    });

    test('creates API methods with authorization', () => {
      // Test GET /todos
      template.hasResourceProperties('AWS::ApiGateway::Method', {
        HttpMethod: 'GET',
        AuthorizationType: 'COGNITO_USER_POOLS',
        AuthorizerId: Match.anyValue(),
      });

      // Test POST /todos
      template.hasResourceProperties('AWS::ApiGateway::Method', {
        HttpMethod: 'POST',
        AuthorizationType: 'COGNITO_USER_POOLS',
        AuthorizerId: Match.anyValue(),
      });
    });

    test('creates CORS options methods', () => {
      template.hasResourceProperties('AWS::ApiGateway::Method', {
        HttpMethod: 'OPTIONS',
        AuthorizationType: 'NONE',
      });
    });
  });

  describe('Amplify App', () => {
    test('creates Amplify app with correct configuration', () => {
      template.hasResourceProperties('AWS::Amplify::App', {
        BuildSpec: Match.anyValue(),
        EnvironmentVariables: [
          {
            Name: 'USER_POOL_ID',
            Value: Match.anyValue(),
          },
          {
            Name: 'USER_POOL_CLIENT_ID',
            Value: Match.anyValue(),
          },
          {
            Name: 'API_ENDPOINT',
            Value: Match.anyValue(),
          },
          {
            Name: 'AWS_REGION',
            Value: 'us-east-1',
          },
        ],
        AutoBranchCreationConfig: {
          EnableAutoBranchCreation: true,
          EnableAutoBuild: true,
          EnablePullRequestPreview: true,
          Stage: 'DEVELOPMENT',
        },
      });
    });

    test('creates main branch', () => {
      template.hasResourceProperties('AWS::Amplify::Branch', {
        BranchName: 'main',
        EnableAutoBuild: true,
        EnablePullRequestPreview: true,
        Stage: 'PRODUCTION',
      });
    });
  });

  describe('CloudWatch Dashboard', () => {
    test('creates CloudWatch dashboard', () => {
      template.hasResourceProperties('AWS::CloudWatch::Dashboard', {
        DashboardBody: Match.anyValue(),
      });
    });
  });

  describe('Outputs', () => {
    test('exports required outputs', () => {
      template.hasOutput('UserPoolId', {
        Export: {
          Name: 'TestStack-UserPoolId',
        },
      });

      template.hasOutput('UserPoolClientId', {
        Export: {
          Name: 'TestStack-UserPoolClientId',
        },
      });

      template.hasOutput('ApiEndpoint', {
        Export: {
          Name: 'TestStack-ApiEndpoint',
        },
      });

      template.hasOutput('TodoTableName', {
        Export: {
          Name: 'TestStack-TodoTableName',
        },
      });

      template.hasOutput('AmplifyAppId', {
        Export: {
          Name: 'TestStack-AmplifyAppId',
        },
      });
    });
  });

  describe('Stack Properties', () => {
    test('accepts custom properties', () => {
      const customStack = new ServerlessWebAppStack(app, 'CustomStack', {
        tableName: 'custom-todos',
        functionName: 'custom-function',
        appName: 'custom-app',
        enableMonitoring: false,
        env: {
          account: '123456789012',
          region: 'us-west-2',
        },
      });

      const customTemplate = Template.fromStack(customStack);

      // Verify custom table name is used
      customTemplate.hasResourceProperties('AWS::DynamoDB::Table', {
        TableName: 'custom-todos',
      });

      // Verify custom function name is used
      customTemplate.hasResourceProperties('AWS::Lambda::Function', {
        FunctionName: 'custom-function',
      });
    });
  });

  describe('Resource Count', () => {
    test('creates expected number of resources', () => {
      const resources = template.toJSON().Resources;
      const resourceTypes = Object.values(resources).map((r: any) => r.Type);

      // Count key resource types
      expect(resourceTypes.filter(type => type === 'AWS::DynamoDB::Table')).toHaveLength(1);
      expect(resourceTypes.filter(type => type === 'AWS::Cognito::UserPool')).toHaveLength(1);
      expect(resourceTypes.filter(type => type === 'AWS::Cognito::UserPoolClient')).toHaveLength(1);
      expect(resourceTypes.filter(type => type === 'AWS::Lambda::Function')).toHaveLength(1);
      expect(resourceTypes.filter(type => type === 'AWS::ApiGateway::RestApi')).toHaveLength(1);
      expect(resourceTypes.filter(type => type === 'AWS::Amplify::App')).toHaveLength(1);
      expect(resourceTypes.filter(type => type === 'AWS::CloudWatch::Dashboard')).toHaveLength(1);
    });
  });
});