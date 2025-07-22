import * as cdk from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { AutomatedWorkspacesStack } from '../lib/automated-workspaces-stack';

describe('AutomatedWorkspacesStack', () => {
  let app: cdk.App;
  let stack: AutomatedWorkspacesStack;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    stack = new AutomatedWorkspacesStack(app, 'TestStack', {
      directoryId: 'd-test123456',
      bundleId: 'wsb-test123',
      targetUsers: ['testuser1', 'testuser2'],
      automationSchedule: 'rate(24 hours)',
      enableVpcEndpoints: false,
      stackName: 'test-workspaces',
    });
    template = Template.fromStack(stack);
  });

  test('Creates Lambda function with correct configuration', () => {
    template.hasResourceProperties('AWS::Lambda::Function', {
      Runtime: 'python3.9',
      Handler: 'index.lambda_handler',
      Timeout: 300,
      MemorySize: 256,
    });
  });

  test('Creates IAM role for Lambda with required permissions', () => {
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
    });

    // Check for WorkSpaces permissions
    template.hasResourceProperties('AWS::IAM::Policy', {
      PolicyDocument: {
        Statement: [
          {
            Effect: 'Allow',
            Action: [
              'workspaces:CreateWorkspaces',
              'workspaces:TerminateWorkspaces',
              'workspaces:DescribeWorkspaces',
              'workspaces:DescribeWorkspaceDirectories',
              'workspaces:DescribeWorkspaceBundles',
              'workspaces:ModifyWorkspaceProperties',
            ],
          },
        ],
      },
    });
  });

  test('Creates Secrets Manager secret for AD credentials', () => {
    template.hasResourceProperties('AWS::SecretsManager::Secret', {
      Description: 'Active Directory service account credentials for WorkSpaces automation',
      GenerateSecretString: {
        SecretStringTemplate: '{"username":"workspaces-service"}',
        GenerateStringKey: 'password',
        ExcludeCharacters: '"@/\\\'',
        PasswordLength: 32,
        RequireEachIncludedType: true,
      },
    });
  });

  test('Creates Systems Manager document', () => {
    template.hasResourceProperties('AWS::SSM::Document', {
      DocumentType: 'Command',
      DocumentFormat: 'JSON',
      Name: 'test-workspaces-dev-environment-setup',
    });
  });

  test('Creates EventBridge rule with correct schedule', () => {
    template.hasResourceProperties('AWS::Events::Rule', {
      Description: 'Daily WorkSpaces provisioning automation',
      ScheduleExpression: 'rate(24 hours)',
      State: 'ENABLED',
    });
  });

  test('Creates CloudWatch log group with retention policy', () => {
    template.hasResourceProperties('AWS::Logs::LogGroup', {
      LogGroupName: '/aws/lambda/test-workspaces-automation',
      RetentionInDays: 14,
    });
  });

  test('Validates required stack outputs are created', () => {
    template.hasOutput('LambdaFunctionName', {});
    template.hasOutput('LambdaFunctionArn', {});
    template.hasOutput('SecretsManagerArn', {});
    template.hasOutput('SSMDocumentName', {});
    template.hasOutput('EventBridgeRuleName', {});
  });

  test('Applies security best practices', () => {
    // Check that WorkSpaces are configured with encryption
    const lambdaCode = template.findResources('AWS::Lambda::Function');
    const functionCode = JSON.stringify(lambdaCode);
    
    expect(functionCode).toContain('UserVolumeEncryptionEnabled');
    expect(functionCode).toContain('RootVolumeEncryptionEnabled');
    expect(functionCode).toContain('RunningMode');
  });

  test('Configures proper resource tagging', () => {
    const lambdaCode = template.findResources('AWS::Lambda::Function');
    const functionCode = JSON.stringify(lambdaCode);
    
    expect(functionCode).toContain('Project');
    expect(functionCode).toContain('DevEnvironmentAutomation');
    expect(functionCode).toContain('ManagedBy');
  });

  test('Stack has correct number of resources', () => {
    const resources = template.findResources('AWS::Lambda::Function');
    expect(Object.keys(resources)).toHaveLength(1);

    const roles = template.findResources('AWS::IAM::Role');
    expect(Object.keys(roles).length).toBeGreaterThanOrEqual(1);

    const secrets = template.findResources('AWS::SecretsManager::Secret');
    expect(Object.keys(secrets)).toHaveLength(1);

    const documents = template.findResources('AWS::SSM::Document');
    expect(Object.keys(documents)).toHaveLength(1);

    const rules = template.findResources('AWS::Events::Rule');
    expect(Object.keys(rules)).toHaveLength(1);
  });
});