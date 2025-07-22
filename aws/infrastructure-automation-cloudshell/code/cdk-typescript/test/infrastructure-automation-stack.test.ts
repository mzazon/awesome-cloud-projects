import * as cdk from 'aws-cdk-lib';
import { Template, Match } from 'aws-cdk-lib/assertions';
import * as logs from 'aws-cdk-lib/aws-logs';
import { InfrastructureAutomationStack } from '../lib/infrastructure-automation-stack';

describe('InfrastructureAutomationStack', () => {
  let app: cdk.App;
  let stack: InfrastructureAutomationStack;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    stack = new InfrastructureAutomationStack(app, 'TestStack');
    template = Template.fromStack(stack);
  });

  describe('IAM Role', () => {
    test('creates automation role with correct trust policy', () => {
      template.hasResourceProperties('AWS::IAM::Role', {
        AssumeRolePolicyDocument: {
          Statement: [
            {
              Effect: 'Allow',
              Principal: {
                Service: ['lambda.amazonaws.com', 'ssm.amazonaws.com']
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

    test('automation role has required permissions', () => {
      template.hasResourceProperties('AWS::IAM::Policy', {
        PolicyDocument: {
          Statement: Match.arrayWith([
            Match.objectLike({
              Effect: 'Allow',
              Action: Match.arrayWith([
                'ssm:StartAutomationExecution',
                'ssm:GetAutomationExecution',
                'ec2:DescribeInstances',
                's3:ListAllMyBuckets',
                'cloudwatch:PutMetricData',
                'logs:CreateLogGroup'
              ]),
              Resource: '*'
            })
          ])
        }
      });
    });
  });

  describe('Lambda Function', () => {
    test('creates orchestration function with correct configuration', () => {
      template.hasResourceProperties('AWS::Lambda::Function', {
        FunctionName: 'infrastructure-automation-orchestrator',
        Runtime: 'python3.11',
        Handler: 'index.lambda_handler',
        Timeout: 300,
        MemorySize: 256,
        Environment: {
          Variables: {
            AUTOMATION_DOCUMENT_NAME: 'InfrastructureHealthCheck',
            LOG_GROUP_NAME: '/aws/automation/infrastructure-health'
          }
        }
      });
    });

    test('lambda function has inline code', () => {
      template.hasResourceProperties('AWS::Lambda::Function', {
        Code: {
          ZipFile: Match.stringLikeRegexp('.*lambda_handler.*')
        }
      });
    });
  });

  describe('CloudWatch Resources', () => {
    test('creates log group with correct configuration', () => {
      template.hasResourceProperties('AWS::Logs::LogGroup', {
        LogGroupName: '/aws/automation/infrastructure-health',
        RetentionInDays: 30
      });
    });

    test('creates CloudWatch alarms for monitoring', () => {
      // Automation error alarm
      template.hasResourceProperties('AWS::CloudWatch::Alarm', {
        AlarmName: 'infrastructure-automation-errors',
        MetricName: 'AutomationErrors',
        Namespace: 'Infrastructure/Automation',
        Threshold: 1,
        ComparisonOperator: 'GreaterThanOrEqualToThreshold'
      });

      // Lambda error alarm
      template.hasResourceProperties('AWS::CloudWatch::Alarm', {
        AlarmName: 'infrastructure-automation-lambda-errors',
        MetricName: 'Errors',
        Namespace: 'AWS/Lambda'
      });
    });

    test('creates CloudWatch dashboard', () => {
      template.hasResourceProperties('AWS::CloudWatch::Dashboard', {
        DashboardName: 'infrastructure-automation-monitoring'
      });
    });
  });

  describe('SNS Topic', () => {
    test('creates SNS topic for alerts', () => {
      template.hasResourceProperties('AWS::SNS::Topic', {
        TopicName: 'infrastructure-automation-alerts',
        DisplayName: 'Infrastructure Automation Alerts'
      });
    });

    test('SNS topic is used in alarm actions', () => {
      template.hasResourceProperties('AWS::CloudWatch::Alarm', {
        AlarmActions: [
          { Ref: Match.anyValue() }
        ]
      });
    });
  });

  describe('Systems Manager', () => {
    test('creates automation document', () => {
      template.hasResourceProperties('AWS::SSM::Document', {
        Name: 'InfrastructureHealthCheck',
        DocumentType: 'Automation',
        DocumentFormat: 'JSON'
      });
    });

    test('automation document has correct structure', () => {
      template.hasResourceProperties('AWS::SSM::Document', {
        Content: Match.objectLike({
          schemaVersion: '0.3',
          description: 'Infrastructure Health Check Automation using PowerShell',
          parameters: {
            Region: Match.objectLike({
              type: 'String'
            }),
            LogGroupName: Match.objectLike({
              type: 'String'
            })
          },
          mainSteps: Match.arrayWith([
            Match.objectLike({
              name: 'CreateLogGroup',
              action: 'aws:executeAwsApi'
            }),
            Match.objectLike({
              name: 'ExecuteHealthCheck',
              action: 'aws:executeScript',
              inputs: Match.objectLike({
                Runtime: 'PowerShell Core 6.0'
              })
            })
          ])
        })
      });
    });
  });

  describe('EventBridge', () => {
    test('creates scheduled rule with correct configuration', () => {
      template.hasResourceProperties('AWS::Events::Rule', {
        Name: 'infrastructure-health-schedule',
        ScheduleExpression: 'cron(0 6 * * ? *)',
        State: 'ENABLED'
      });
    });

    test('EventBridge rule targets Lambda function', () => {
      template.hasResourceProperties('AWS::Events::Rule', {
        Targets: [
          Match.objectLike({
            Arn: {
              'Fn::GetAtt': [Match.anyValue(), 'Arn']
            }
          })
        ]
      });
    });
  });

  describe('Stack Outputs', () => {
    test('exports important resource information', () => {
      template.hasOutput('AutomationRoleArn', {
        Description: 'ARN of the IAM role used by automation services'
      });

      template.hasOutput('OrchestrationFunctionName', {
        Description: 'Name of the Lambda function orchestrating automation'
      });

      template.hasOutput('LogGroupName', {
        Description: 'CloudWatch Log Group for automation logs'
      });

      template.hasOutput('AlertTopicArn', {
        Description: 'SNS topic ARN for automation alerts'
      });
    });
  });

  describe('Custom Configuration', () => {
    test('accepts custom email notification', () => {
      const customStack = new InfrastructureAutomationStack(app, 'CustomStack', {
        notificationEmail: 'test@example.com'
      });
      const customTemplate = Template.fromStack(customStack);

      customTemplate.hasResourceProperties('AWS::SNS::Subscription', {
        Protocol: 'email',
        Endpoint: 'test@example.com'
      });
    });

    test('accepts custom schedule expression', () => {
      const customStack = new InfrastructureAutomationStack(app, 'CustomStack', {
        scheduleExpression: 'cron(0 12 * * ? *)'
      });
      const customTemplate = Template.fromStack(customStack);

      customTemplate.hasResourceProperties('AWS::Events::Rule', {
        ScheduleExpression: 'cron(0 12 * * ? *)'
      });
    });

    test('accepts custom log retention', () => {
      const customStack = new InfrastructureAutomationStack(app, 'CustomStack', {
        logRetention: logs.RetentionDays.ONE_WEEK
      });
      const customTemplate = Template.fromStack(customStack);

      customTemplate.hasResourceProperties('AWS::Logs::LogGroup', {
        RetentionInDays: 7
      });
    });
  });

  describe('Resource Count', () => {
    test('creates expected number of resources', () => {
      // Count key resource types
      const resources = template.toJSON().Resources;
      const resourceTypes = Object.values(resources).map((r: any) => r.Type);

      expect(resourceTypes.filter(t => t === 'AWS::IAM::Role')).toHaveLength(1);
      expect(resourceTypes.filter(t => t === 'AWS::Lambda::Function')).toHaveLength(1);
      expect(resourceTypes.filter(t => t === 'AWS::SNS::Topic')).toHaveLength(1);
      expect(resourceTypes.filter(t => t === 'AWS::SSM::Document')).toHaveLength(1);
      expect(resourceTypes.filter(t => t === 'AWS::Events::Rule')).toHaveLength(1);
      expect(resourceTypes.filter(t => t === 'AWS::Logs::LogGroup')).toHaveLength(1);
      expect(resourceTypes.filter(t => t === 'AWS::CloudWatch::Alarm')).toHaveLength(2);
      expect(resourceTypes.filter(t => t === 'AWS::CloudWatch::Dashboard')).toHaveLength(1);
    });
  });

  describe('Tags', () => {
    test('applies default tags to resources', () => {
      // Check that taggable resources have the expected tags
      const resources = template.toJSON().Resources;
      
      // Find Lambda function and check tags
      const lambdaFunction = Object.values(resources).find(
        (r: any) => r.Type === 'AWS::Lambda::Function'
      ) as any;
      
      expect(lambdaFunction?.Properties?.Tags).toBeDefined();
    });
  });
});