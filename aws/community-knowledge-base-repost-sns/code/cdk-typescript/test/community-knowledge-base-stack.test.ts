import * as cdk from 'aws-cdk-lib';
import { Template, Match } from 'aws-cdk-lib/assertions';
import { CommunityKnowledgeBaseStack } from '../community-knowledge-base-stack';

describe('CommunityKnowledgeBaseStack', () => {
  let app: cdk.App;
  let stack: CommunityKnowledgeBaseStack;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    stack = new CommunityKnowledgeBaseStack(app, 'TestStack', {
      notificationEmails: ['test1@example.com', 'test2@example.com'],
      enableDetailedMonitoring: true,
    });
    template = Template.fromStack(stack);
  });

  describe('SNS Topic', () => {
    test('creates SNS topic with correct configuration', () => {
      template.hasResource('AWS::SNS::Topic', {
        Properties: {
          DisplayName: 'Community Knowledge Base Notifications',
          TopicName: Match.stringLikeRegexp('repost-knowledge-notifications-.*'),
        },
      });
    });

    test('creates email subscriptions for all provided emails', () => {
      template.resourceCountIs('AWS::SNS::Subscription', 2);
      
      template.hasResource('AWS::SNS::Subscription', {
        Properties: {
          Protocol: 'email',
          Endpoint: 'test1@example.com',
        },
      });

      template.hasResource('AWS::SNS::Subscription', {
        Properties: {
          Protocol: 'email',
          Endpoint: 'test2@example.com',
        },
      });
    });
  });

  describe('IAM Role', () => {
    test('creates service role for re:Post Private', () => {
      template.hasResource('AWS::IAM::Role', {
        Properties: {
          AssumeRolePolicyDocument: {
            Statement: [
              {
                Effect: 'Allow',
                Principal: {
                  Service: 'repost.amazonaws.com',
                },
                Action: 'sts:AssumeRole',
              },
            ],
          },
          Description: 'Service role for AWS re:Post Private integration with knowledge base notifications',
        },
      });
    });

    test('creates SNS logging role', () => {
      template.hasResource('AWS::IAM::Role', {
        Properties: {
          AssumeRolePolicyDocument: {
            Statement: [
              {
                Effect: 'Allow',
                Principal: {
                  Service: 'sns.amazonaws.com',
                },
                Action: 'sts:AssumeRole',
              },
            ],
          },
          Description: 'Role for SNS to write delivery status logs to CloudWatch',
        },
      });
    });

    test('includes required SNS permissions', () => {
      template.hasResource('AWS::IAM::Role', {
        Properties: {
          Policies: [
            {
              PolicyDocument: {
                Statement: [
                  {
                    Effect: 'Allow',
                    Action: [
                      'sns:Publish',
                      'sns:GetTopicAttributes',
                    ],
                    Resource: Match.anyValue(),
                    Condition: {
                      StringEquals: {
                        'aws:SourceAccount': Match.anyValue(),
                      },
                    },
                  },
                ],
              },
            },
          ],
        },
      });
    });
  });

  describe('CloudWatch Resources', () => {
    test('creates log group for monitoring', () => {
      template.hasResource('AWS::Logs::LogGroup', {
        Properties: {
          LogGroupName: Match.stringLikeRegexp('/aws/community-knowledge-base/.*'),
          RetentionInDays: 30,
        },
      });
    });

    test('creates monitoring dashboard when detailed monitoring is enabled', () => {
      template.hasResource('AWS::CloudWatch::Dashboard', {
        Properties: {
          DashboardName: Match.stringLikeRegexp('community-knowledge-base-.*'),
        },
      });
    });

    test('creates CloudWatch alarms for operational monitoring', () => {
      // Check for notification failure alarm
      template.hasResource('AWS::CloudWatch::Alarm', {
        Properties: {
          AlarmDescription: 'Alert when SNS notifications fail to deliver',
          MetricName: 'NumberOfNotificationsFailed',
          Namespace: 'AWS/SNS',
          Threshold: 1,
        },
      });

      // Check for high volume alarm
      template.hasResource('AWS::CloudWatch::Alarm', {
        Properties: {
          AlarmDescription: 'Alert when notification volume is unexpectedly high',
          MetricName: 'NumberOfMessagesPublished',
          Namespace: 'AWS/SNS',
          Threshold: 100,
        },
      });
    });
  });

  describe('Stack Outputs', () => {
    test('creates required stack outputs', () => {
      template.hasOutput('NotificationTopicArn', {
        Description: 'ARN of the SNS topic for knowledge base notifications',
      });

      template.hasOutput('NotificationTopicName', {
        Description: 'Name of the SNS topic for knowledge base notifications',
      });

      template.hasOutput('RePostServiceRoleArn', {
        Description: 'ARN of the service role for re:Post Private integration',
      });

      template.hasOutput('LogGroupName', {
        Description: 'CloudWatch Log Group for knowledge base monitoring',
      });

      template.hasOutput('RePostPrivateConsoleUrl', {
        Value: 'https://console.aws.amazon.com/repost-private/',
        Description: 'URL to access AWS re:Post Private console (requires Enterprise Support)',
      });
    });
  });

  describe('Error Handling', () => {
    test('throws error for invalid email addresses', () => {
      expect(() => {
        new CommunityKnowledgeBaseStack(app, 'ErrorTestStack', {
          notificationEmails: ['invalid-email'],
          enableDetailedMonitoring: false,
        });
      }).toThrow('Invalid email address: invalid-email');
    });

    test('accepts valid email addresses', () => {
      expect(() => {
        new CommunityKnowledgeBaseStack(app, 'ValidTestStack', {
          notificationEmails: [
            'user@example.com',
            'test.email+tag@domain.co.uk',
            'valid_email@subdomain.example.org',
          ],
          enableDetailedMonitoring: false,
        });
      }).not.toThrow();
    });
  });

  describe('Resource Tagging', () => {
    test('applies consistent tags to resources', () => {
      // SNS Topic should have tags
      template.hasResource('AWS::SNS::Topic', {
        Properties: {
          Tags: Match.arrayWith([
            {
              Key: 'Project',
              Value: 'CommunityKnowledgeBase',
            },
          ]),
        },
      });
    });
  });

  describe('Minimal Configuration', () => {
    test('works with minimal configuration and no detailed monitoring', () => {
      const minimalStack = new CommunityKnowledgeBaseStack(app, 'MinimalStack', {
        notificationEmails: ['minimal@example.com'],
        enableDetailedMonitoring: false,
      });

      const minimalTemplate = Template.fromStack(minimalStack);

      // Should still create basic resources
      minimalTemplate.hasResource('AWS::SNS::Topic', {});
      minimalTemplate.hasResource('AWS::SNS::Subscription', {});
      minimalTemplate.hasResource('AWS::IAM::Role', {});
      minimalTemplate.hasResource('AWS::Logs::LogGroup', {});

      // Should not create dashboard when monitoring is disabled
      minimalTemplate.resourceCountIs('AWS::CloudWatch::Dashboard', 0);
    });
  });
});

describe('Email Validation', () => {
  test('validates various email formats correctly', () => {
    const validEmails = [
      'user@example.com',
      'test.email@domain.org',
      'user+tag@subdomain.example.co.uk',
      'firstname.lastname@company-name.com',
      'user123@test-domain.org',
    ];

    const invalidEmails = [
      'invalid-email',
      '@domain.com',
      'user@',
      'user.domain.com',
      'user space@domain.com',
    ];

    const app = new cdk.App();

    validEmails.forEach((email) => {
      expect(() => {
        new CommunityKnowledgeBaseStack(app, `ValidStack${Math.random()}`, {
          notificationEmails: [email],
        });
      }).not.toThrow();
    });

    invalidEmails.forEach((email) => {
      expect(() => {
        new CommunityKnowledgeBaseStack(app, `InvalidStack${Math.random()}`, {
          notificationEmails: [email],
        });
      }).toThrow(`Invalid email address: ${email}`);
    });
  });
});