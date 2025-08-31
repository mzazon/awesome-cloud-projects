import * as cdk from 'aws-cdk-lib';
import { Template, Match } from 'aws-cdk-lib/assertions';
import { SecretsManagerLambdaStack } from '../lib/secrets-manager-lambda-stack';

describe('SecretsManagerLambdaStack', () => {
  let app: cdk.App;
  let stack: SecretsManagerLambdaStack;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    stack = new SecretsManagerLambdaStack(app, 'TestSecretsManagerLambdaStack');
    template = Template.fromStack(stack);
  });

  test('Creates Secrets Manager Secret', () => {
    template.hasResourceProperties('AWS::SecretsManager::Secret', {
      Description: 'Sample application secrets for Lambda demo',
      GenerateSecretString: {
        ExcludeCharacters: ' %+~`#$&*()|[]{}:;<>?!\'/@"\\',
        GenerateStringKey: 'password',
        PasswordLength: 32,
        SecretStringTemplate: Match.stringLikeRegexp('.*database_host.*')
      }
    });
  });

  test('Creates Lambda Function with correct configuration', () => {
    template.hasResourceProperties('AWS::Lambda::Function', {
      Runtime: 'python3.11',
      Handler: 'lambda_function.lambda_handler',
      Timeout: 30,
      MemorySize: 256,
      Environment: {
        Variables: {
          PARAMETERS_SECRETS_EXTENSION_CACHE_ENABLED: 'true',
          PARAMETERS_SECRETS_EXTENSION_CACHE_SIZE: '1000',
          PARAMETERS_SECRETS_EXTENSION_MAX_CONNECTIONS: '3',
          PARAMETERS_SECRETS_EXTENSION_HTTP_PORT: '2773'
        }
      }
    });
  });

  test('Creates IAM Role with proper trust policy', () => {
    template.hasResourceProperties('AWS::IAM::Role', {
      AssumeRolePolicyDocument: {
        Statement: [
          {
            Action: 'sts:AssumeRole',
            Effect: 'Allow',
            Principal: {
              Service: 'lambda.amazonaws.com'
            }
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

  test('Creates CloudWatch Log Group with retention', () => {
    template.hasResourceProperties('AWS::Logs::LogGroup', {
      RetentionInDays: 7
    });
  });

  test('Lambda function has AWS Parameters and Secrets Extension layer', () => {
    template.hasResourceProperties('AWS::Lambda::Function', {
      Layers: [
        Match.stringLikeRegexp('.*AWS-Parameters-and-Secrets-Lambda-Extension.*')
      ]
    });
  });

  test('Secret has proper IAM permissions for Lambda', () => {
    template.hasResourceProperties('AWS::IAM::Policy', {
      PolicyDocument: {
        Statement: [
          {
            Action: 'secretsmanager:GetSecretValue',
            Effect: 'Allow',
            Resource: {
              Ref: Match.stringLikeRegexp('DatabaseSecret.*')
            }
          }
        ]
      }
    });
  });

  test('Stack has required outputs', () => {
    template.hasOutput('SecretName', {});
    template.hasOutput('SecretArn', {});
    template.hasOutput('LambdaFunctionName', {});
    template.hasOutput('LambdaFunctionArn', {});
    template.hasOutput('IAMRoleName', {});
    template.hasOutput('LogGroupName', {});
  });

  test('Resources are properly tagged', () => {
    template.hasResourceProperties('AWS::SecretsManager::Secret', {
      Tags: Match.arrayWith([
        {
          Key: 'Project',
          Value: 'BasicSecretManagement'
        },
        {
          Key: 'Environment',
          Value: 'Demo'
        },
        {
          Key: 'Recipe',
          Value: 'basic-secret-management-secrets-lambda'
        }
      ])
    });
  });

  test('Secret has unique naming with suffix', () => {
    template.hasResourceProperties('AWS::SecretsManager::Secret', {
      Name: Match.stringLikeRegexp('my-app-secrets-.*')
    });
  });

  test('Lambda function has proper description', () => {
    template.hasResourceProperties('AWS::Lambda::Function', {
      Description: 'Lambda function demonstrating secure secret retrieval using AWS Parameters and Secrets Extension'
    });
  });
});