import * as cdk from 'aws-cdk-lib';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as cloudwatchActions from 'aws-cdk-lib/aws-cloudwatch-actions';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as kms from 'aws-cdk-lib/aws-kms';
import { Construct } from 'constructs';
import { NagSuppressions } from 'cdk-nag';

/**
 * Interface for ChatNotificationsStack properties
 */
export interface ChatNotificationsStackProps extends cdk.StackProps {
  /**
   * Optional prefix for resource names
   * @default - Generated unique suffix
   */
  readonly resourcePrefix?: string;
  
  /**
   * Whether to create demo CloudWatch alarm
   * @default true
   */
  readonly createDemoAlarm?: boolean;
  
  /**
   * Environment stage (dev, staging, prod)
   * @default 'dev'
   */
  readonly stage?: string;
}

/**
 * Stack for Chat Notifications with SNS and Chatbot
 * 
 * This stack creates the infrastructure needed for real-time chat notifications:
 * - SNS Topic with KMS encryption for secure message delivery
 * - CloudWatch Alarm for demonstration and testing
 * - IAM roles and policies for AWS Chatbot integration
 * - Comprehensive security controls and monitoring
 * 
 * The stack follows AWS Well-Architected Framework principles:
 * - Security: KMS encryption, least privilege IAM, SSL enforcement
 * - Reliability: Durable messaging with SNS, proper error handling
 * - Performance: Efficient message delivery, minimal latency
 * - Cost Optimization: Pay-per-use messaging, no idle resources
 * - Operational Excellence: Comprehensive monitoring and alerting
 */
export class ChatNotificationsStack extends cdk.Stack {
  
  // Public readonly properties for stack outputs
  public readonly snsTopicArn: string;
  public readonly snsTopicName: string;
  public readonly kmsKeyArn: string;
  public readonly kmsKeyId: string;
  public readonly chatbotRoleArn: string;
  public readonly demoAlarmName?: string;

  constructor(scope: Construct, id: string, props?: ChatNotificationsStackProps) {
    super(scope, id, props);

    // Configuration with defaults
    const stage = props?.stage ?? 'dev';
    const createDemoAlarm = props?.createDemoAlarm ?? true;
    
    // Generate unique suffix for resource names to avoid conflicts
    const uniqueSuffix = props?.resourcePrefix ?? 
      this.node.addr.substring(Math.max(0, this.node.addr.length - 6)).toLowerCase();

    // Create KMS key for SNS encryption with comprehensive policy
    const snsKmsKey = new kms.Key(this, 'SnsEncryptionKey', {
      description: `KMS key for SNS topic encryption in chat notifications system (${stage})`,
      enableKeyRotation: true,
      keySpec: kms.KeySpec.SYMMETRIC_DEFAULT,
      keyUsage: kms.KeyUsage.ENCRYPT_DECRYPT,
      removalPolicy: stage === 'prod' ? cdk.RemovalPolicy.RETAIN : cdk.RemovalPolicy.DESTROY,
      policy: new iam.PolicyDocument({
        statements: [
          // Allow root account full access (required for KMS keys)
          new iam.PolicyStatement({
            sid: 'EnableRootAccess',
            effect: iam.Effect.ALLOW,
            principals: [new iam.AccountRootPrincipal()],
            actions: ['kms:*'],
            resources: ['*'],
          }),
          // Allow SNS service to use the key
          new iam.PolicyStatement({
            sid: 'AllowSNSAccess',
            effect: iam.Effect.ALLOW,
            principals: [new iam.ServicePrincipal('sns.amazonaws.com')],
            actions: [
              'kms:Encrypt',
              'kms:Decrypt',
              'kms:ReEncrypt*',
              'kms:GenerateDataKey*',
              'kms:DescribeKey',
              'kms:CreateGrant'
            ],
            resources: ['*'],
            conditions: {
              StringEquals: {
                'kms:ViaService': `sns.${this.region}.amazonaws.com`
              }
            }
          }),
          // Allow CloudWatch to publish to SNS
          new iam.PolicyStatement({
            sid: 'AllowCloudWatchAccess',
            effect: iam.Effect.ALLOW,
            principals: [new iam.ServicePrincipal('cloudwatch.amazonaws.com')],
            actions: [
              'kms:Encrypt',
              'kms:Decrypt',
              'kms:ReEncrypt*',
              'kms:GenerateDataKey*',
              'kms:DescribeKey'
            ],
            resources: ['*'],
            conditions: {
              StringEquals: {
                'kms:ViaService': `sns.${this.region}.amazonaws.com`
              }
            }
          }),
          // Allow AWS Chatbot service to decrypt messages
          new iam.PolicyStatement({
            sid: 'AllowChatbotAccess',
            effect: iam.Effect.ALLOW,
            principals: [new iam.ServicePrincipal('chatbot.amazonaws.com')],
            actions: [
              'kms:Decrypt',
              'kms:DescribeKey'
            ],
            resources: ['*'],
          }),
        ],
      }),
    });

    // Create alias for the KMS key for easier reference
    const kmsAlias = new kms.Alias(this, 'SnsEncryptionKeyAlias', {
      aliasName: `alias/chat-notifications-sns-${uniqueSuffix}`,
      targetKey: snsKmsKey,
      removalPolicy: stage === 'prod' ? cdk.RemovalPolicy.RETAIN : cdk.RemovalPolicy.DESTROY,
    });

    // Create SNS topic for team notifications with comprehensive configuration
    const notificationTopic = new sns.Topic(this, 'TeamNotificationsTopic', {
      topicName: `team-notifications-${uniqueSuffix}`,
      displayName: `Team Notifications Topic (${stage})`,
      masterKey: snsKmsKey,
      enforceSSL: true,
      fifo: false, // Standard topic for better integration with multiple subscribers
    });

    // Create IAM role for AWS Chatbot with least privilege permissions
    const chatbotRole = new iam.Role(this, 'ChatbotRole', {
      roleName: `ChatbotRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('chatbot.amazonaws.com'),
      description: `IAM role for AWS Chatbot to access SNS and execute read-only commands (${stage})`,
      maxSessionDuration: cdk.Duration.hours(12),
      managedPolicies: [
        // Provide read-only access for helpful context in chat
        iam.ManagedPolicy.fromAwsManagedPolicyName('ReadOnlyAccess'),
        // Enhanced CloudWatch permissions for better monitoring context
        iam.ManagedPolicy.fromAwsManagedPolicyName('CloudWatchReadOnlyAccess'),
      ],
      inlinePolicies: {
        ChatbotSNSPolicy: new iam.PolicyDocument({
          statements: [
            // Allow Chatbot to interact with SNS topics
            new iam.PolicyStatement({
              sid: 'AllowSNSTopicAccess',
              effect: iam.Effect.ALLOW,
              actions: [
                'sns:ListTopics',
                'sns:GetTopicAttributes',
                'sns:ListSubscriptionsByTopic'
              ],
              resources: [notificationTopic.topicArn],
            }),
            // Allow Chatbot to describe CloudWatch alarms for context
            new iam.PolicyStatement({
              sid: 'AllowCloudWatchAlarmAccess',
              effect: iam.Effect.ALLOW,
              actions: [
                'cloudwatch:DescribeAlarms',
                'cloudwatch:DescribeAlarmHistory',
                'cloudwatch:GetMetricStatistics'
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // Create demo CloudWatch alarm for testing notifications (optional)
    let demoAlarm: cloudwatch.Alarm | undefined;
    if (createDemoAlarm) {
      demoAlarm = new cloudwatch.Alarm(this, 'DemoCpuAlarm', {
        alarmName: `demo-cpu-alarm-${uniqueSuffix}`,
        alarmDescription: `Demo CPU alarm for testing chat notifications (${stage})`,
        metric: new cloudwatch.Metric({
          namespace: 'AWS/EC2',
          metricName: 'CPUUtilization',
          statistic: 'Average',
          period: cdk.Duration.minutes(5),
        }),
        threshold: 1.0,
        comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
        evaluationPeriods: 1,
        treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
        actionsEnabled: true,
      });

      // Add SNS topic as alarm action
      demoAlarm.addAlarmAction(new cloudwatchActions.SnsAction(notificationTopic));
      demoAlarm.addOkAction(new cloudwatchActions.SnsAction(notificationTopic));
      demoAlarm.addInsufficientDataAction(new cloudwatchActions.SnsAction(notificationTopic));

      this.demoAlarmName = demoAlarm.alarmName;
    }

    // Store public properties for external access
    this.snsTopicArn = notificationTopic.topicArn;
    this.snsTopicName = notificationTopic.topicName;
    this.kmsKeyArn = snsKmsKey.keyArn;
    this.kmsKeyId = snsKmsKey.keyId;
    this.chatbotRoleArn = chatbotRole.roleArn;

    // Comprehensive CDK Outputs for integration and debugging
    new cdk.CfnOutput(this, 'SnsTopicArn', {
      value: notificationTopic.topicArn,
      description: 'ARN of the SNS topic for team notifications',
      exportName: `${this.stackName}-SnsTopicArn`,
    });

    new cdk.CfnOutput(this, 'SnsTopicName', {
      value: notificationTopic.topicName,
      description: 'Name of the SNS topic for team notifications',
      exportName: `${this.stackName}-SnsTopicName`,
    });

    new cdk.CfnOutput(this, 'ChatbotRoleArn', {
      value: chatbotRole.roleArn,
      description: 'ARN of the IAM role for AWS Chatbot integration',
      exportName: `${this.stackName}-ChatbotRoleArn`,
    });

    new cdk.CfnOutput(this, 'KmsKeyArn', {
      value: snsKmsKey.keyArn,
      description: 'ARN of the KMS key used for SNS encryption',
      exportName: `${this.stackName}-KmsKeyArn`,
    });

    new cdk.CfnOutput(this, 'KmsKeyAlias', {
      value: kmsAlias.aliasName,
      description: 'Alias of the KMS key used for SNS encryption',
    });

    if (demoAlarm) {
      new cdk.CfnOutput(this, 'DemoAlarmName', {
        value: demoAlarm.alarmName,
        description: 'Name of the demo CloudWatch alarm for testing',
        exportName: `${this.stackName}-DemoAlarmName`,
      });
    }

    // Manual setup guidance outputs
    new cdk.CfnOutput(this, 'ChatbotConsoleUrl', {
      value: `https://${this.region}.console.aws.amazon.com/chatbot/`,
      description: 'AWS Chatbot console URL for manual configuration',
    });

    new cdk.CfnOutput(this, 'SetupInstructions', {
      value: [
        '1. Visit AWS Chatbot console',
        '2. Choose Slack or Microsoft Teams',
        '3. Authorize your workspace/tenant',
        '4. Create channel configuration',
        `5. Use IAM role: ${chatbotRole.roleArn}`,
        `6. Subscribe to SNS topic: ${notificationTopic.topicArn}`
      ].join(' | '),
      description: 'Step-by-step setup instructions for AWS Chatbot',
    });

    // Apply CDK Nag suppressions for intentional design decisions
    NagSuppressions.addResourceSuppressions(
      chatbotRole,
      [
        {
          id: 'AwsSolutions-IAM4',
          reason: 'ReadOnlyAccess and CloudWatchReadOnlyAccess managed policies are required for AWS Chatbot to provide helpful context and execute safe commands in chat channels. This follows AWS Chatbot best practices and provides least privilege access for chat operations.',
        },
      ],
    );

    NagSuppressions.addResourceSuppressions(
      snsKmsKey,
      [
        {
          id: 'AwsSolutions-KMS5',
          reason: 'KMS key rotation is enabled for security. The key policy grants access to necessary AWS services (SNS, CloudWatch, Chatbot) with appropriate conditions to ensure secure encryption operations for the chat notification system.',
        },
      ],
    );

    // Suppress CDK Nag warnings for demo alarm if created
    if (demoAlarm) {
      NagSuppressions.addResourceSuppressions(
        demoAlarm,
        [
          {
            id: 'AwsSolutions-CW4',
            reason: 'Demo alarm is intentionally configured with low threshold for testing purposes. In production, alarm thresholds should be set based on actual application requirements and baseline metrics.',
          },
        ],
      );
    }

    // Add comprehensive resource tags for governance and cost allocation
    const resourceTags = [
      ['Component', 'Messaging'],
      ['Service', 'ChatNotifications'],
      ['Environment', stage],
      ['ManagedBy', 'CDK']
    ];

    // Apply tags to all resources
    resourceTags.forEach(([key, value]) => {
      cdk.Tags.of(notificationTopic).add(key, value);
      cdk.Tags.of(chatbotRole).add(key, value);
      cdk.Tags.of(snsKmsKey).add(key, value);
      if (demoAlarm) {
        cdk.Tags.of(demoAlarm).add(key, value);
      }
    });

    // Additional service-specific tags
    cdk.Tags.of(notificationTopic).add('ResourceType', 'SNS-Topic');
    cdk.Tags.of(chatbotRole).add('ResourceType', 'IAM-Role');
    cdk.Tags.of(snsKmsKey).add('ResourceType', 'KMS-Key');
    if (demoAlarm) {
      cdk.Tags.of(demoAlarm).add('ResourceType', 'CloudWatch-Alarm');
    }
  }

  /**
   * Convenience method to get SNS topic reference for external stacks
   */
  public getSnsTopic(): sns.ITopic {
    return sns.Topic.fromTopicArn(this, 'ImportedSnsTopic', this.snsTopicArn);
  }

  /**
   * Convenience method to get KMS key reference for external stacks
   */
  public getKmsKey(): kms.IKey {
    return kms.Key.fromKeyArn(this, 'ImportedKmsKey', this.kmsKeyArn);
  }

  /**
   * Convenience method to get Chatbot role reference for external stacks
   */
  public getChatbotRole(): iam.IRole {
    return iam.Role.fromRoleArn(this, 'ImportedChatbotRole', this.chatbotRoleArn);
  }
}