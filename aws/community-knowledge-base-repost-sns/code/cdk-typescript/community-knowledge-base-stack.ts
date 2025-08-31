import * as cdk from 'aws-cdk-lib';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import { Construct } from 'constructs';

/**
 * Interface for CommunityKnowledgeBaseStack properties
 */
export interface CommunityKnowledgeBaseStackProps extends cdk.StackProps {
  readonly stackName?: string;
  readonly notificationEmails: string[];
  readonly enableDetailedMonitoring?: boolean;
}

/**
 * CDK Stack for Community Knowledge Base with re:Post Private and SNS
 * 
 * This stack creates the infrastructure needed to support an enterprise
 * knowledge base using AWS re:Post Private with SNS email notifications.
 * 
 * Components:
 * - SNS Topic for knowledge base notifications
 * - Email subscriptions for team members
 * - IAM service role for re:Post Private integration
 * - CloudWatch dashboard for monitoring
 * - CloudWatch alarms for operational alerts
 */
export class CommunityKnowledgeBaseStack extends cdk.Stack {
  public readonly notificationTopic: sns.Topic;
  public readonly repostServiceRole: iam.Role;
  public readonly logGroup: logs.LogGroup;

  constructor(scope: Construct, id: string, props: CommunityKnowledgeBaseStackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names to avoid conflicts
    const uniqueSuffix = cdk.Names.uniqueId(this).toLowerCase().slice(-6);
    
    // Create CloudWatch Log Group for monitoring and debugging
    this.logGroup = new logs.LogGroup(this, 'KnowledgeBaseLogGroup', {
      logGroupName: `/aws/community-knowledge-base/${uniqueSuffix}`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create SNS Topic for knowledge base notifications
    this.notificationTopic = new sns.Topic(this, 'KnowledgeBaseNotificationTopic', {
      topicName: `repost-knowledge-notifications-${uniqueSuffix}`,
      displayName: 'Community Knowledge Base Notifications',
      
      // Enable detailed monitoring and logging
      loggingConfigs: props.enableDetailedMonitoring ? [
        {
          protocol: sns.LoggingProtocol.HTTP,
          successFeedbackRoleArn: this.createSnsLoggingRole().roleArn,
          successFeedbackSampleRate: 100,
          failureFeedbackRoleArn: this.createSnsLoggingRole().roleArn,
        },
      ] : undefined,
    });

    // Add email subscriptions for team members
    props.notificationEmails.forEach((email, index) => {
      // Validate email format (basic validation)
      if (!this.isValidEmail(email)) {
        throw new Error(`Invalid email address: ${email}`);
      }

      new snsSubscriptions.EmailSubscription(email, {
        json: false, // Send plain text emails for better readability
      });

      // Subscribe email to the topic
      this.notificationTopic.addSubscription(
        new snsSubscriptions.EmailSubscription(email, {
          json: false,
        })
      );
    });

    // Create IAM role for re:Post Private service integration
    this.repostServiceRole = new iam.Role(this, 'RePostServiceRole', {
      roleName: `repost-service-role-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('repost.amazonaws.com'),
      description: 'Service role for AWS re:Post Private integration with knowledge base notifications',
      
      inlinePolicies: {
        'SNSPublishPolicy': new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'sns:Publish',
                'sns:GetTopicAttributes',
              ],
              resources: [this.notificationTopic.topicArn],
              conditions: {
                StringEquals: {
                  'aws:SourceAccount': this.account,
                },
              },
            }),
          ],
        }),
        
        'CloudWatchLogsPolicy': new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:CreateLogStream',
                'logs:PutLogEvents',
                'logs:DescribeLogGroups',
                'logs:DescribeLogStreams',
              ],
              resources: [
                this.logGroup.logGroupArn,
                `${this.logGroup.logGroupArn}:*`,
              ],
            }),
          ],
        }),
      },
    });

    // Create CloudWatch Dashboard for monitoring (if detailed monitoring is enabled)
    if (props.enableDetailedMonitoring) {
      this.createMonitoringDashboard(uniqueSuffix);
      this.createCloudWatchAlarms();
    }

    // Create outputs for important resource ARNs and configuration
    this.createStackOutputs(uniqueSuffix, props.notificationEmails);
  }

  /**
   * Creates an IAM role for SNS logging
   */
  private createSnsLoggingRole(): iam.Role {
    return new iam.Role(this, 'SnsLoggingRole', {
      assumedBy: new iam.ServicePrincipal('sns.amazonaws.com'),
      description: 'Role for SNS to write delivery status logs to CloudWatch',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/SNSLogsDeliveryRolePolicy'),
      ],
    });
  }

  /**
   * Creates CloudWatch Dashboard for monitoring the knowledge base system
   */
  private createMonitoringDashboard(uniqueSuffix: string): void {
    new cloudwatch.Dashboard(this, 'KnowledgeBaseDashboard', {
      dashboardName: `community-knowledge-base-${uniqueSuffix}`,
      
      widgets: [
        [
          // SNS Topic metrics
          new cloudwatch.GraphWidget({
            title: 'SNS Notification Metrics',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/SNS',
                metricName: 'NumberOfMessagesPublished',
                dimensionsMap: {
                  TopicName: this.notificationTopic.topicName,
                },
                statistic: 'Sum',
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/SNS',
                metricName: 'NumberOfNotificationsDelivered',
                dimensionsMap: {
                  TopicName: this.notificationTopic.topicName,
                },
                statistic: 'Sum',
              }),
            ],
          }),
          
          // Error metrics
          new cloudwatch.GraphWidget({
            title: 'Notification Errors',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/SNS',
                metricName: 'NumberOfNotificationsFailed',
                dimensionsMap: {
                  TopicName: this.notificationTopic.topicName,
                },
                statistic: 'Sum',
              }),
            ],
          }),
        ],
        
        [
          // Log insights widget for troubleshooting
          new cloudwatch.LogQueryWidget({
            title: 'Recent Knowledge Base Activity',
            logGroups: [this.logGroup],
            queryLines: [
              'fields @timestamp, @message',
              'sort @timestamp desc',
              'limit 20',
            ],
          }),
        ],
      ],
    });
  }

  /**
   * Creates CloudWatch Alarms for operational monitoring
   */
  private createCloudWatchAlarms(): void {
    // Alarm for failed notifications
    new cloudwatch.Alarm(this, 'NotificationFailureAlarm', {
      alarmName: `knowledge-base-notification-failures-${cdk.Names.uniqueId(this).slice(-6)}`,
      alarmDescription: 'Alert when SNS notifications fail to deliver',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/SNS',
        metricName: 'NumberOfNotificationsFailed',
        dimensionsMap: {
          TopicName: this.notificationTopic.topicName,
        },
        statistic: 'Sum',
      }),
      threshold: 1,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Alarm for high notification volume (cost control)
    new cloudwatch.Alarm(this, 'HighNotificationVolumeAlarm', {
      alarmName: `knowledge-base-high-volume-${cdk.Names.uniqueId(this).slice(-6)}`,
      alarmDescription: 'Alert when notification volume is unexpectedly high',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/SNS',
        metricName: 'NumberOfMessagesPublished',
        dimensionsMap: {
          TopicName: this.notificationTopic.topicName,
        },
        statistic: 'Sum',
      }),
      threshold: 100, // Adjust based on expected usage
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });
  }

  /**
   * Creates stack outputs for important resource information
   */
  private createStackOutputs(uniqueSuffix: string, notificationEmails: string[]): void {
    // SNS Topic ARN - needed for re:Post Private configuration
    new cdk.CfnOutput(this, 'NotificationTopicArn', {
      value: this.notificationTopic.topicArn,
      description: 'ARN of the SNS topic for knowledge base notifications',
      exportName: `${this.stackName}-notification-topic-arn`,
    });

    // SNS Topic Name - for CLI operations
    new cdk.CfnOutput(this, 'NotificationTopicName', {
      value: this.notificationTopic.topicName,
      description: 'Name of the SNS topic for knowledge base notifications',
      exportName: `${this.stackName}-notification-topic-name`,
    });

    // Service Role ARN - for re:Post Private integration
    new cdk.CfnOutput(this, 'RePostServiceRoleArn', {
      value: this.repostServiceRole.roleArn,
      description: 'ARN of the service role for re:Post Private integration',
      exportName: `${this.stackName}-repost-service-role-arn`,
    });

    // Log Group Name - for monitoring and troubleshooting
    new cdk.CfnOutput(this, 'LogGroupName', {
      value: this.logGroup.logGroupName,
      description: 'CloudWatch Log Group for knowledge base monitoring',
      exportName: `${this.stackName}-log-group-name`,
    });

    // Configuration summary
    new cdk.CfnOutput(this, 'ConfigurationSummary', {
      value: JSON.stringify({
        topicArn: this.notificationTopic.topicArn,
        subscribedEmails: notificationEmails.length,
        region: this.region,
        uniqueSuffix: uniqueSuffix,
      }),
      description: 'Configuration summary for the knowledge base infrastructure',
    });

    // re:Post Private console URL
    new cdk.CfnOutput(this, 'RePostPrivateConsoleUrl', {
      value: 'https://console.aws.amazon.com/repost-private/',
      description: 'URL to access AWS re:Post Private console (requires Enterprise Support)',
    });

    // Next steps for manual configuration
    new cdk.CfnOutput(this, 'NextSteps', {
      value: 'After deployment: 1) Confirm email subscriptions, 2) Configure re:Post Private in AWS console, 3) Test notifications',
      description: 'Manual steps required after CDK deployment',
    });
  }

  /**
   * Basic email validation
   */
  private isValidEmail(email: string): boolean {
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    return emailRegex.test(email);
  }
}