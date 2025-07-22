import * as cdk from 'aws-cdk-lib';
import { Template, Match } from 'aws-cdk-lib/assertions';
import { ScheduledEmailReportsStack } from '../lib/scheduled-email-reports-stack';

describe('ScheduledEmailReportsStack', () => {
  let app: cdk.App;
  let stack: ScheduledEmailReportsStack;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    stack = new ScheduledEmailReportsStack(app, 'TestScheduledEmailReportsStack', {
      verifiedEmail: 'test@example.com',
      githubRepo: 'https://github.com/test/test-repo',
      scheduleExpression: 'cron(0 9 * * ? *)'
    });
    template = Template.fromStack(stack);
  });

  describe('IAM Roles', () => {
    test('creates App Runner service role with correct permissions', () => {
      template.hasResourceProperties('AWS::IAM::Role', {
        AssumedBy: {
          Service: 'tasks.apprunner.amazonaws.com'
        }
      });

      template.hasResourceProperties('AWS::IAM::Policy', {
        PolicyDocument: {
          Statement: Match.arrayWith([
            Match.objectLike({
              Effect: 'Allow',
              Action: [
                'ses:SendEmail',
                'ses:SendRawEmail'
              ]
            }),
            Match.objectLike({
              Effect: 'Allow',
              Action: [
                'cloudwatch:PutMetricData'
              ]
            })
          ])
        }
      });
    });

    test('creates EventBridge Scheduler role with correct permissions', () => {
      template.hasResourceProperties('AWS::IAM::Role', {
        AssumedBy: {
          Service: 'scheduler.amazonaws.com'
        }
      });
    });
  });

  describe('SES Configuration', () => {
    test('creates SES email identity', () => {
      template.hasResourceProperties('AWS::SES::EmailIdentity', {
        EmailIdentity: 'test@example.com'
      });
    });
  });

  describe('App Runner Service', () => {
    test('creates App Runner service with correct configuration', () => {
      template.hasResourceProperties('AWS::AppRunner::Service', {
        SourceConfiguration: {
          CodeRepository: {
            RepositoryUrl: 'https://github.com/test/test-repo',
            SourceCodeVersion: {
              Type: 'BRANCH',
              Value: 'main'
            },
            CodeConfiguration: {
              ConfigurationSource: 'REPOSITORY'
            }
          },
          AutoDeploymentsEnabled: true
        },
        InstanceConfiguration: {
          Cpu: '0.25 vCPU',
          Memory: '0.5 GB',
          EnvironmentVariables: Match.arrayWith([
            {
              Name: 'SES_VERIFIED_EMAIL',
              Value: 'test@example.com'
            }
          ])
        },
        HealthCheckConfiguration: {
          Protocol: 'HTTP',
          Path: '/health',
          Interval: 10,
          Timeout: 5,
          HealthyThreshold: 1,
          UnhealthyThreshold: 5
        }
      });
    });
  });

  describe('EventBridge Scheduler', () => {
    test('creates schedule with correct configuration', () => {
      template.hasResourceProperties('AWS::Scheduler::Schedule', {
        ScheduleExpression: 'cron(0 9 * * ? *)',
        ScheduleExpressionTimezone: 'UTC',
        State: 'ENABLED',
        FlexibleTimeWindow: {
          Mode: 'OFF'
        },
        Target: {
          Arn: 'arn:aws:scheduler:::http-invoke',
          HttpParameters: {
            HttpMethod: 'POST',
            HeaderParameters: {
              'Content-Type': 'application/json'
            }
          },
          RetryPolicy: {
            MaximumRetryAttempts: 3,
            MaximumEventAge: 86400
          }
        }
      });
    });
  });

  describe('CloudWatch Resources', () => {
    test('creates log group for App Runner', () => {
      template.hasResourceProperties('AWS::Logs::LogGroup', {
        LogGroupName: Match.stringLikeRegexp('/aws/apprunner/email-reports-service-.*'),
        RetentionInDays: 7
      });
    });

    test('creates CloudWatch alarm for monitoring', () => {
      template.hasResourceProperties('AWS::CloudWatch::Alarm', {
        AlarmDescription: 'Alert when email report generation fails',
        MetricName: 'ReportsGenerated',
        Namespace: 'EmailReports',
        Statistic: 'Sum',
        Threshold: 1,
        ComparisonOperator: 'LessThanThreshold',
        EvaluationPeriods: 1,
        TreatMissingData: 'notBreaching'
      });
    });

    test('creates CloudWatch dashboard', () => {
      template.hasResourceProperties('AWS::CloudWatch::Dashboard', {
        DashboardName: Match.stringLikeRegexp('EmailReports-Dashboard-.*')
      });
    });
  });

  describe('Custom Resource', () => {
    test('creates custom resource for updating schedule target', () => {
      template.hasResourceProperties('AWS::CloudFormation::CustomResource', {
        ServiceToken: Match.anyValue()
      });
    });

    test('creates Lambda function for custom resource', () => {
      template.hasResourceProperties('AWS::Lambda::Function', {
        Runtime: 'python3.9',
        Handler: 'index.handler',
        Timeout: 300
      });
    });
  });

  describe('Stack Outputs', () => {
    test('has required outputs', () => {
      template.hasOutput('AppRunnerServiceUrl', {});
      template.hasOutput('AppRunnerServiceName', {});
      template.hasOutput('ScheduleName', {});
      template.hasOutput('VerifiedEmailAddress', {
        Value: 'test@example.com'
      });
      template.hasOutput('CloudWatchDashboardUrl', {});
    });
  });

  describe('Resource Count', () => {
    test('creates expected number of resources', () => {
      // Verify minimum required resources are created
      template.resourceCountIs('AWS::IAM::Role', 3); // App Runner, Scheduler, Lambda
      template.resourceCountIs('AWS::AppRunner::Service', 1);
      template.resourceCountIs('AWS::SES::EmailIdentity', 1);
      template.resourceCountIs('AWS::Scheduler::Schedule', 1);
      template.resourceCountIs('AWS::CloudWatch::Alarm', 1);
      template.resourceCountIs('AWS::CloudWatch::Dashboard', 1);
      template.resourceCountIs('AWS::Logs::LogGroup', 1);
      template.resourceCountIs('AWS::Lambda::Function', 1);
      template.resourceCountIs('AWS::CloudFormation::CustomResource', 1);
    });
  });
});