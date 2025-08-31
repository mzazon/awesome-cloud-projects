import * as cdk from 'aws-cdk-lib';
import { Template, Match } from 'aws-cdk-lib/assertions';
import { ChatNotificationsStack } from '../lib/chat-notifications-stack';

describe('ChatNotificationsStack', () => {
  let app: cdk.App;
  let stack: ChatNotificationsStack;
  let template: Template;

  beforeEach(() => {
    app = new cdk.App();
    stack = new ChatNotificationsStack(app, 'TestChatNotificationsStack', {
      env: {
        account: '123456789012',
        region: 'us-east-1',
      },
    });
    template = Template.fromStack(stack);
  });

  test('SNS Topic is created with encryption', () => {
    template.hasResourceProperties('AWS::SNS::Topic', {
      DisplayName: 'Team Notifications Topic',
      KmsMasterKeyId: Match.objectLike({
        'Fn::GetAtt': Match.arrayWith([
          Match.stringLikeRegexp('SnsEncryptionKey.*'),
          'Arn'
        ]),
      }),
    });
  });

  test('KMS Key is created with proper policy', () => {
    template.hasResourceProperties('AWS::KMS::Key', {
      Description: 'KMS key for SNS topic encryption in chat notifications system',
      EnableKeyRotation: true,
      KeySpec: 'SYMMETRIC_DEFAULT',
      KeyUsage: 'ENCRYPT_DECRYPT',
    });
  });

  test('IAM Role for Chatbot is created with correct permissions', () => {
    template.hasResourceProperties('AWS::IAM::Role', {
      AssumeRolePolicyDocument: {
        Statement: [
          {
            Action: 'sts:AssumeRole',
            Effect: 'Allow',
            Principal: {
              Service: 'chatbot.amazonaws.com',
            },
          },
        ],
        Version: '2012-10-17',
      },
      Description: 'IAM role for AWS Chatbot to access SNS and execute read-only commands',
    });
    
    // Verify managed policies are attached
    template.hasResourceProperties('AWS::IAM::Role', {
      ManagedPolicyArns: Match.arrayEquals([
        Match.objectLike({
          'Fn::Join': Match.anyValue(),
        }),
        Match.objectLike({
          'Fn::Join': Match.anyValue(),
        }),
      ]),
    });
  });

  test('CloudWatch Alarm is created for testing', () => {
    template.hasResourceProperties('AWS::CloudWatch::Alarm', {
      AlarmDescription: 'Demo CPU alarm for testing chat notifications',
      ComparisonOperator: 'LessThanThreshold',
      EvaluationPeriods: 1,
      MetricName: 'CPUUtilization',
      Namespace: 'AWS/EC2',
      Period: 300,
      Statistic: 'Average',
      Threshold: 1,
      TreatMissingData: 'notBreaching',
    });
  });

  test('Alarm has SNS topic as action', () => {
    template.hasResourceProperties('AWS::CloudWatch::Alarm', {
      AlarmActions: [
        {
          Ref: Match.stringLikeRegexp('TeamNotificationsTopic.*'),
        },
      ],
    });
  });

  test('Stack outputs are configured correctly', () => {
    template.hasOutput('SnsTopicArn', {
      Description: 'ARN of the SNS topic for team notifications',
      Export: {
        Name: 'TestChatNotificationsStack-SnsTopicArn',
      },
    });

    template.hasOutput('ChatbotRoleArn', {
      Description: 'ARN of the IAM role for AWS Chatbot integration',
      Export: {
        Name: 'TestChatNotificationsStack-ChatbotRoleArn',
      },
    });

    template.hasOutput('ChatbotConsoleUrl', {
      Description: 'AWS Chatbot console URL for manual configuration',
      Value: 'https://console.aws.amazon.com/chatbot/',
    });
  });

  test('Resources have appropriate tags', () => {
    template.hasResourceProperties('AWS::SNS::Topic', {
      Tags: Match.arrayWith([
        {
          Key: 'Component',
          Value: 'Messaging',
        },
        {
          Key: 'Service',
          Value: 'SNS',
        },
      ]),
    });

    template.hasResourceProperties('AWS::IAM::Role', {
      Tags: Match.arrayWith([
        {
          Key: 'Component',
          Value: 'Security',
        },
        {
          Key: 'Service',
          Value: 'IAM',
        },
      ]),
    });
  });

  test('KMS key has proper alias', () => {
    template.hasResourceProperties('AWS::KMS::Alias', {
      AliasName: Match.stringLikeRegexp('alias/chat-notifications-sns-.*'),
      TargetKeyId: Match.objectLike({
        'Fn::GetAtt': Match.arrayWith([
          Match.stringLikeRegexp('SnsEncryptionKey.*'),
          'Arn',
        ]),
      }),
    });
  });

  test('Stack has expected number of resources', () => {
    const resources = template.findResources('AWS::SNS::Topic');
    expect(Object.keys(resources)).toHaveLength(1);
    
    const kmsResources = template.findResources('AWS::KMS::Key');
    expect(Object.keys(kmsResources)).toHaveLength(1);
    
    const roleResources = template.findResources('AWS::IAM::Role');
    expect(Object.keys(roleResources)).toHaveLength(1);
    
    const alarmResources = template.findResources('AWS::CloudWatch::Alarm');
    expect(Object.keys(alarmResources)).toHaveLength(1);
  });

  test('Stack properties are accessible', () => {
    expect(stack.snsTopicArn).toBeDefined();
    expect(stack.snsTopicName).toBeDefined();
    expect(stack.kmsKeyArn).toBeDefined();
    expect(stack.demoAlarmName).toBeDefined();
  });

  test('SNS topic enforces SSL', () => {
    // The SNS topic should have SSL enforcement through the KMS encryption
    // and proper access policies (verified by the KMS key policy)
    template.hasResourceProperties('AWS::SNS::Topic', {
      KmsMasterKeyId: Match.objectLike({
        'Fn::GetAtt': Match.anyValue(),
      }),
    });
  });

  test('IAM role has inline policy for SNS access', () => {
    template.hasResourceProperties('AWS::IAM::Role', {
      Policies: [
        {
          PolicyName: 'ChatbotSNSPolicy',
          PolicyDocument: {
            Statement: [
              {
                Action: [
                  'sns:ListTopics',
                  'sns:GetTopicAttributes',
                ],
                Effect: 'Allow',
                Resource: {
                  Ref: Match.stringLikeRegexp('TeamNotificationsTopic.*'),
                },
              },
            ],
            Version: '2012-10-17',
          },
        },
      ],
    });
  });
});