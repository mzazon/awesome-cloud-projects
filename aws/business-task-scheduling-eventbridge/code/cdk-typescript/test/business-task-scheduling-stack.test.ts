import * as cdk from 'aws-cdk-lib';
import { Template, Match } from 'aws-cdk-lib/assertions';
import { BusinessTaskSchedulingStack } from '../lib/business-task-scheduling-stack';

describe('BusinessTaskSchedulingStack', () => {
  let app: cdk.App;
  let stack: BusinessTaskSchedulingStack;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    stack = new BusinessTaskSchedulingStack(app, 'TestBusinessTaskSchedulingStack', {
      env: { account: '123456789012', region: 'us-east-1' }
    });
    template = Template.fromStack(stack);
  });

  test('Stack creates S3 bucket with correct configuration', () => {
    template.hasResourceProperties('AWS::S3::Bucket', {
      VersioningConfiguration: {
        Status: 'Enabled'
      },
      BucketEncryption: {
        ServerSideEncryptionConfiguration: [{
          ServerSideEncryptionByDefault: {
            SSEAlgorithm: 'AES256'
          }
        }]
      },
      PublicAccessBlockConfiguration: {
        BlockPublicAcls: true,
        BlockPublicPolicy: true,
        IgnorePublicAcls: true,
        RestrictPublicBuckets: true
      }
    });
  });

  test('Stack creates SNS topic', () => {
    template.hasResourceProperties('AWS::SNS::Topic', {
      DisplayName: 'Business Automation Notifications'
    });
  });

  test('Stack creates Lambda function with correct runtime and configuration', () => {
    template.hasResourceProperties('AWS::Lambda::Function', {
      Runtime: 'python3.11',
      Handler: 'business_task_processor.lambda_handler',
      Timeout: 60,
      MemorySize: 256
    });
  });

  test('Stack creates EventBridge schedules', () => {
    // Daily report schedule
    template.hasResourceProperties('AWS::Scheduler::Schedule', {
      Name: 'daily-report-schedule',
      ScheduleExpression: 'cron(0 9 * * ? *)',
      ScheduleExpressionTimezone: 'America/New_York'
    });

    // Hourly data processing schedule
    template.hasResourceProperties('AWS::Scheduler::Schedule', {
      Name: 'hourly-data-processing',
      ScheduleExpression: 'rate(1 hour)'
    });

    // Weekly notification schedule
    template.hasResourceProperties('AWS::Scheduler::Schedule', {
      Name: 'weekly-notification-schedule',
      ScheduleExpression: 'cron(0 10 ? * MON *)',
      ScheduleExpressionTimezone: 'America/New_York'
    });
  });

  test('Stack creates schedule group', () => {
    template.hasResourceProperties('AWS::Scheduler::ScheduleGroup', {
      Name: 'business-automation-group'
    });
  });

  test('Stack creates IAM role for scheduler', () => {
    template.hasResourceProperties('AWS::IAM::Role', {
      AssumeRolePolicyDocument: {
        Statement: Match.arrayWith([
          Match.objectLike({
            Effect: 'Allow',
            Principal: {
              Service: 'scheduler.amazonaws.com'
            },
            Action: 'sts:AssumeRole'
          })
        ])
      }
    });
  });

  test('Stack creates Lambda execution role', () => {
    template.hasResourceProperties('AWS::IAM::Role', {
      AssumeRolePolicyDocument: {
        Statement: Match.arrayWith([
          Match.objectLike({
            Effect: 'Allow',
            Principal: {
              Service: 'lambda.amazonaws.com'
            },
            Action: 'sts:AssumeRole'
          })
        ])
      }
    });
  });

  test('Stack creates CloudWatch Log Group', () => {
    template.hasResourceProperties('AWS::Logs::LogGroup', {
      RetentionInDays: 7
    });
  });

  test('Stack produces required outputs', () => {
    template.hasOutput('S3BucketName', {});
    template.hasOutput('SNSTopicArn', {});
    template.hasOutput('LambdaFunctionName', {});
    template.hasOutput('ScheduleGroupName', {});
    template.hasOutput('ManualTestCommand', {});
  });

  test('Lambda function has environment variables', () => {
    template.hasResourceProperties('AWS::Lambda::Function', {
      Environment: {
        Variables: {
          BUCKET_NAME: Match.anyValue(),
          TOPIC_ARN: Match.anyValue()
        }
      }
    });
  });

  test('S3 bucket has lifecycle configuration', () => {
    template.hasResourceProperties('AWS::S3::Bucket', {
      LifecycleConfiguration: {
        Rules: Match.arrayWith([
          Match.objectLike({
            Id: 'delete-old-versions',
            Status: 'Enabled',
            NoncurrentVersionExpirationInDays: 30
          }),
          Match.objectLike({
            Id: 'transition-to-ia',
            Status: 'Enabled',
            Transitions: Match.arrayWith([
              Match.objectLike({
                StorageClass: 'STANDARD_IA',
                TransitionInDays: 30
              })
            ])
          })
        ])
      }
    });
  });

  test('Stack has appropriate resource count', () => {
    // Verify we have the expected number of each resource type
    template.resourceCountIs('AWS::S3::Bucket', 1);
    template.resourceCountIs('AWS::SNS::Topic', 1);
    template.resourceCountIs('AWS::Lambda::Function', 1);
    template.resourceCountIs('AWS::Scheduler::Schedule', 3);
    template.resourceCountIs('AWS::Scheduler::ScheduleGroup', 1);
    template.resourceCountIs('AWS::Logs::LogGroup', 1);
    
    // Should have at least 2 IAM roles (Lambda execution and Scheduler)
    template.resourcePropertiesCountIs('AWS::IAM::Role', {}, 2);
  });
});