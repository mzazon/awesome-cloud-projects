import { App } from 'aws-cdk-lib';
import { Template, Match } from 'aws-cdk-lib/assertions';
import { FeatureFlagsAppConfigStack } from '../lib/feature-flags-appconfig-stack';

describe('FeatureFlagsAppConfigStack', () => {
  let app: App;
  let stack: FeatureFlagsAppConfigStack;
  let template: Template;

  beforeEach(() => {
    app = new App();
    stack = new FeatureFlagsAppConfigStack(app, 'TestStack');
    template = Template.fromStack(stack);
  });

  describe('AppConfig Resources', () => {
    test('creates AppConfig application', () => {
      template.hasResourceProperties('AWS::AppConfig::Application', {
        Name: Match.stringLikeRegexp('FeatureFlags-App-.*'),
        Description: 'Feature flag demo application for safe deployments'
      });
    });

    test('creates AppConfig environment with monitoring', () => {
      template.hasResourceProperties('AWS::AppConfig::Environment', {
        Name: 'production',
        Description: 'Production environment with automated rollback capabilities',
        Monitors: Match.arrayWith([
          Match.objectLike({
            AlarmArn: Match.anyValue(),
            AlarmRoleArn: Match.anyValue()
          })
        ])
      });
    });

    test('creates feature flag configuration profile', () => {
      template.hasResourceProperties('AWS::AppConfig::ConfigurationProfile', {
        Name: 'feature-flags',
        LocationUri: 'hosted',
        Type: 'AWS.AppConfig.FeatureFlags',
        Description: 'Feature flags for gradual rollout and A/B testing'
      });
    });

    test('creates deployment strategy with correct settings', () => {
      template.hasResourceProperties('AWS::AppConfig::DeploymentStrategy', {
        Name: Match.stringLikeRegexp('gradual-rollout-.*'),
        DeploymentDurationInMinutes: 20,
        FinalBakeTimeInMinutes: 10,
        GrowthFactor: 25,
        GrowthType: 'LINEAR',
        ReplicateTo: 'NONE'
      });
    });

    test('creates hosted configuration version with feature flags', () => {
      template.hasResourceProperties('AWS::AppConfig::HostedConfigurationVersion', {
        ContentType: 'application/json',
        Description: 'Initial feature flags configuration with multiple flags and attributes'
      });
    });

    test('creates deployment with correct references', () => {
      template.hasResourceProperties('AWS::AppConfig::Deployment', {
        Description: 'Initial deployment of feature flags with gradual rollout'
      });
    });
  });

  describe('Lambda Function', () => {
    test('creates Lambda function with correct configuration', () => {
      template.hasResourceProperties('AWS::Lambda::Function', {
        FunctionName: Match.stringLikeRegexp('feature-flag-demo-.*'),
        Runtime: 'python3.9',
        Handler: 'index.lambda_handler',
        Timeout: 30,
        MemorySize: 256,
        TracingConfig: {
          Mode: 'Active'
        },
        ReservedConcurrencyLimit: 10
      });
    });

    test('Lambda function has AppConfig extension layer', () => {
      template.hasResourceProperties('AWS::Lambda::Function', {
        Layers: Match.arrayWith([
          Match.stringLikeRegexp('arn:aws:lambda:.*:027255383542:layer:AWS-AppConfig-Extension:82')
        ])
      });
    });

    test('Lambda function has correct environment variables', () => {
      template.hasResourceProperties('AWS::Lambda::Function', {
        Environment: {
          Variables: {
            APP_ID: Match.anyValue(),
            ENV_ID: Match.anyValue(),
            PROFILE_ID: Match.anyValue()
          }
        }
      });
    });
  });

  describe('IAM Resources', () => {
    test('creates Lambda execution role with AppConfig permissions', () => {
      template.hasResourceProperties('AWS::IAM::Role', {
        AssumeRolePolicyDocument: {
          Statement: Match.arrayWith([
            {
              Effect: 'Allow',
              Principal: {
                Service: 'lambda.amazonaws.com'
              },
              Action: 'sts:AssumeRole'
            }
          ])
        },
        ManagedPolicyArns: Match.arrayWith([
          'arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole'
        ])
      });
    });

    test('creates AppConfig access policy for Lambda', () => {
      template.hasResourceProperties('AWS::IAM::Policy', {
        PolicyDocument: {
          Statement: Match.arrayWith([
            {
              Effect: 'Allow',
              Action: [
                'appconfig:StartConfigurationSession',
                'appconfig:GetLatestConfiguration'
              ],
              Resource: '*',
              Sid: 'AppConfigAccess'
            }
          ])
        }
      });
    });

    test('creates service-linked role for AppConfig', () => {
      template.hasResourceProperties('AWS::IAM::ServiceLinkedRole', {
        AWSServiceName: 'appconfig.amazonaws.com',
        Description: 'Service-linked role for AppConfig monitoring and rollback'
      });
    });
  });

  describe('CloudWatch Resources', () => {
    test('creates CloudWatch alarm for Lambda monitoring', () => {
      template.hasResourceProperties('AWS::CloudWatch::Alarm', {
        AlarmName: Match.stringLikeRegexp('lambda-error-rate-.*'),
        AlarmDescription: 'Monitor Lambda function error rate for AppConfig rollback',
        MetricName: 'Errors',
        Namespace: 'AWS/Lambda',
        Statistic: 'Sum',
        Period: 300,
        Threshold: 5,
        EvaluationPeriods: 2,
        ComparisonOperator: 'GreaterThanThreshold',
        TreatMissingData: 'notBreaching'
      });
    });

    test('creates log group for Lambda function', () => {
      template.hasResourceProperties('AWS::Logs::LogGroup', {
        RetentionInDays: 7
      });
    });

    test('creates metric filter for error tracking', () => {
      template.hasResourceProperties('AWS::Logs::MetricFilter', {
        FilterPattern: '[timestamp, requestId="ERROR"]',
        MetricTransformations: [{
          MetricName: 'LambdaErrors',
          MetricNamespace: 'FeatureFlags/Demo',
          MetricValue: '1',
          DefaultValue: 0
        }]
      });
    });
  });

  describe('SQS Resources', () => {
    test('creates dead letter queue for Lambda', () => {
      template.hasResourceProperties('AWS::SQS::Queue', {
        QueueName: Match.stringLikeRegexp('feature-flag-dlq-.*'),
        MessageRetentionPeriod: 1209600 // 14 days in seconds
      });
    });
  });

  describe('Stack Outputs', () => {
    test('exports important resource identifiers', () => {
      const outputs = template.findOutputs('*');
      
      expect(outputs).toHaveProperty('AppConfigApplicationId');
      expect(outputs).toHaveProperty('AppConfigEnvironmentId');
      expect(outputs).toHaveProperty('ConfigurationProfileId');
      expect(outputs).toHaveProperty('LambdaFunctionName');
      expect(outputs).toHaveProperty('LambdaFunctionArn');
      expect(outputs).toHaveProperty('DeploymentStrategyId');
      expect(outputs).toHaveProperty('CloudWatchAlarmName');
    });
  });

  describe('Resource Tagging', () => {
    test('applies consistent tags to resources', () => {
      // Check that AppConfig application has proper tags
      template.hasResourceProperties('AWS::AppConfig::Application', {
        Tags: Match.arrayWith([
          { Key: 'Name', Value: Match.stringLikeRegexp('FeatureFlags-Application') },
          { Key: 'Purpose', Value: 'FeatureFlagManagement' }
        ])
      });

      // Check that Lambda function has proper tags  
      template.hasResourceProperties('AWS::Lambda::Function', {
        Tags: Match.arrayWith([
          { Key: 'Name', Value: Match.stringLikeRegexp('FeatureFlags-Lambda') },
          { Key: 'Purpose', Value: 'FeatureFlagDemo' }
        ])
      });
    });
  });

  describe('Custom Configuration', () => {
    test('accepts custom resource prefix', () => {
      const customStack = new FeatureFlagsAppConfigStack(app, 'CustomStack', {
        resourcePrefix: 'MyApp'
      });
      const customTemplate = Template.fromStack(customStack);

      customTemplate.hasResourceProperties('AWS::AppConfig::Application', {
        Name: Match.stringLikeRegexp('MyApp-App-.*')
      });
    });

    test('accepts custom environment name', () => {
      const customStack = new FeatureFlagsAppConfigStack(app, 'CustomStack', {
        environmentName: 'staging'
      });
      const customTemplate = Template.fromStack(customStack);

      customTemplate.hasResourceProperties('AWS::AppConfig::Environment', {
        Name: 'staging'
      });
    });

    test('accepts custom deployment configuration', () => {
      const customStack = new FeatureFlagsAppConfigStack(app, 'CustomStack', {
        deploymentConfig: {
          deploymentDurationInMinutes: 30,
          growthFactor: 50,
          finalBakeTimeInMinutes: 15
        }
      });
      const customTemplate = Template.fromStack(customStack);

      customTemplate.hasResourceProperties('AWS::AppConfig::DeploymentStrategy', {
        DeploymentDurationInMinutes: 30,
        GrowthFactor: 50,
        FinalBakeTimeInMinutes: 15
      });
    });
  });

  describe('Resource Count Validation', () => {
    test('creates expected number of resources', () => {
      const resources = template.toJSON().Resources;
      
      // Count specific resource types
      const appConfigApps = Object.values(resources).filter(r => r.Type === 'AWS::AppConfig::Application');
      const appConfigEnvs = Object.values(resources).filter(r => r.Type === 'AWS::AppConfig::Environment');
      const lambdaFunctions = Object.values(resources).filter(r => r.Type === 'AWS::Lambda::Function');
      const iamRoles = Object.values(resources).filter(r => r.Type === 'AWS::IAM::Role');
      const cloudwatchAlarms = Object.values(resources).filter(r => r.Type === 'AWS::CloudWatch::Alarm');

      expect(appConfigApps).toHaveLength(1);
      expect(appConfigEnvs).toHaveLength(1);
      expect(lambdaFunctions).toHaveLength(1);
      expect(iamRoles).toHaveLength(1);
      expect(cloudwatchAlarms).toHaveLength(1);
    });
  });
});