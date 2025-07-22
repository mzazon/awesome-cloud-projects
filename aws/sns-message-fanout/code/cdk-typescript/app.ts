#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as sqs from 'aws-cdk-lib/aws-sqs';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import { Construct } from 'constructs';

/**
 * Props for the MessageFanoutStack
 */
interface MessageFanoutStackProps extends cdk.StackProps {
  /**
   * Prefix for resource names to ensure uniqueness
   * @default 'message-fanout'
   */
  readonly resourcePrefix?: string;
  
  /**
   * Environment name for tagging and identification
   * @default 'dev'
   */
  readonly environmentName?: string;
  
  /**
   * Enable detailed monitoring with CloudWatch alarms
   * @default true
   */
  readonly enableMonitoring?: boolean;
  
  /**
   * Enable message retention for compliance
   * @default true
   */
  readonly enableMessageRetention?: boolean;
}

/**
 * Interface for queue configuration
 */
interface QueueConfig {
  readonly name: string;
  readonly visibilityTimeout: cdk.Duration;
  readonly messageRetentionPeriod: cdk.Duration;
  readonly maxReceiveCount: number;
  readonly alarmThreshold: number;
  readonly filterPolicy?: { [key: string]: string[] };
}

/**
 * AWS CDK Stack for SNS Message Fan-out with Multiple SQS Queues
 * 
 * This stack creates:
 * - SNS Topic for order events
 * - SQS Queues for different business functions (inventory, payment, shipping, analytics)
 * - Dead Letter Queues for error handling
 * - CloudWatch Alarms for monitoring
 * - IAM policies for secure access
 * - SNS subscriptions with message filtering
 */
export class MessageFanoutStack extends cdk.Stack {
  public readonly orderEventsTopic: sns.Topic;
  public readonly queues: { [key: string]: sqs.Queue };
  public readonly deadLetterQueues: { [key: string]: sqs.Queue };
  public readonly alarms: { [key: string]: cloudwatch.Alarm };

  constructor(scope: Construct, id: string, props: MessageFanoutStackProps = {}) {
    super(scope, id, props);

    // Extract configuration with defaults
    const resourcePrefix = props.resourcePrefix || 'message-fanout';
    const environmentName = props.environmentName || 'dev';
    const enableMonitoring = props.enableMonitoring !== false;
    const enableMessageRetention = props.enableMessageRetention !== false;

    // Define queue configurations for different business functions
    const queueConfigs: { [key: string]: QueueConfig } = {
      inventory: {
        name: 'inventory-processing',
        visibilityTimeout: cdk.Duration.minutes(5),
        messageRetentionPeriod: cdk.Duration.days(14),
        maxReceiveCount: 3,
        alarmThreshold: 100,
        filterPolicy: {
          eventType: ['inventory_update', 'stock_check'],
          priority: ['high', 'medium']
        }
      },
      payment: {
        name: 'payment-processing',
        visibilityTimeout: cdk.Duration.minutes(5),
        messageRetentionPeriod: cdk.Duration.days(14),
        maxReceiveCount: 3,
        alarmThreshold: 50,
        filterPolicy: {
          eventType: ['payment_request', 'payment_confirmation'],
          priority: ['high']
        }
      },
      shipping: {
        name: 'shipping-notifications',
        visibilityTimeout: cdk.Duration.minutes(5),
        messageRetentionPeriod: cdk.Duration.days(14),
        maxReceiveCount: 3,
        alarmThreshold: 75,
        filterPolicy: {
          eventType: ['shipping_notification', 'delivery_update'],
          priority: ['high', 'medium', 'low']
        }
      },
      analytics: {
        name: 'analytics-reporting',
        visibilityTimeout: cdk.Duration.minutes(5),
        messageRetentionPeriod: cdk.Duration.days(14),
        maxReceiveCount: 3,
        alarmThreshold: 200,
        // No filter policy - receives all events
      }
    };

    // Create Dead Letter Queues first
    this.deadLetterQueues = this.createDeadLetterQueues(resourcePrefix, queueConfigs);

    // Create Primary SQS Queues with DLQ configuration
    this.queues = this.createPrimaryQueues(resourcePrefix, queueConfigs, this.deadLetterQueues);

    // Create SNS Topic for order events
    this.orderEventsTopic = this.createSNSTopic(resourcePrefix);

    // Create SNS subscriptions with message filtering
    this.createSNSSubscriptions(queueConfigs);

    // Create CloudWatch alarms for monitoring
    if (enableMonitoring) {
      this.alarms = this.createCloudWatchAlarms(resourcePrefix, queueConfigs);
      this.createCloudWatchDashboard(resourcePrefix);
    }

    // Add common tags to all resources
    this.addCommonTags(environmentName);

    // Output important resource ARNs
    this.createOutputs();
  }

  /**
   * Create Dead Letter Queues for error handling
   */
  private createDeadLetterQueues(resourcePrefix: string, queueConfigs: { [key: string]: QueueConfig }): { [key: string]: sqs.Queue } {
    const dlqs: { [key: string]: sqs.Queue } = {};

    Object.entries(queueConfigs).forEach(([key, config]) => {
      const dlqName = `${resourcePrefix}-${config.name}-dlq`;
      
      dlqs[key] = new sqs.Queue(this, `${this.capitalizeFirst(key)}DeadLetterQueue`, {
        queueName: dlqName,
        visibilityTimeout: cdk.Duration.seconds(60),
        messageRetentionPeriod: cdk.Duration.days(14),
        enforceSSL: true,
        encryption: sqs.QueueEncryption.SQS_MANAGED,
      });

      // Add tags
      cdk.Tags.of(dlqs[key]).add('Purpose', 'DeadLetterQueue');
      cdk.Tags.of(dlqs[key]).add('BusinessFunction', key);
    });

    return dlqs;
  }

  /**
   * Create Primary SQS Queues with DLQ configuration
   */
  private createPrimaryQueues(
    resourcePrefix: string,
    queueConfigs: { [key: string]: QueueConfig },
    deadLetterQueues: { [key: string]: sqs.Queue }
  ): { [key: string]: sqs.Queue } {
    const queues: { [key: string]: sqs.Queue } = {};

    Object.entries(queueConfigs).forEach(([key, config]) => {
      const queueName = `${resourcePrefix}-${config.name}`;
      
      queues[key] = new sqs.Queue(this, `${this.capitalizeFirst(key)}Queue`, {
        queueName: queueName,
        visibilityTimeout: config.visibilityTimeout,
        messageRetentionPeriod: config.messageRetentionPeriod,
        enforceSSL: true,
        encryption: sqs.QueueEncryption.SQS_MANAGED,
        deadLetterQueue: {
          queue: deadLetterQueues[key],
          maxReceiveCount: config.maxReceiveCount,
        },
      });

      // Add tags
      cdk.Tags.of(queues[key]).add('Purpose', 'PrimaryQueue');
      cdk.Tags.of(queues[key]).add('BusinessFunction', key);
    });

    return queues;
  }

  /**
   * Create SNS Topic for order events
   */
  private createSNSTopic(resourcePrefix: string): sns.Topic {
    const topic = new sns.Topic(this, 'OrderEventsTopic', {
      topicName: `${resourcePrefix}-order-events`,
      displayName: 'Order Events Topic for E-commerce Processing',
      enforceSSL: true,
    });

    // Configure delivery policy for resilient message delivery
    topic.addToResourcePolicy(new iam.PolicyStatement({
      sid: 'DeliveryPolicy',
      effect: iam.Effect.ALLOW,
      principals: [new iam.ServicePrincipal('sns.amazonaws.com')],
      actions: ['sns:Publish'],
      resources: [topic.topicArn],
    }));

    // Add tags
    cdk.Tags.of(topic).add('Purpose', 'MessageFanout');
    cdk.Tags.of(topic).add('Service', 'OrderProcessing');

    return topic;
  }

  /**
   * Create SNS subscriptions with message filtering
   */
  private createSNSSubscriptions(queueConfigs: { [key: string]: QueueConfig }): void {
    Object.entries(queueConfigs).forEach(([key, config]) => {
      const queue = this.queues[key];
      
      // Create subscription with optional filter policy
      const subscription = new snsSubscriptions.SqsSubscription(queue, {
        rawMessageDelivery: false,
        filterPolicy: config.filterPolicy ? this.createFilterPolicy(config.filterPolicy) : undefined,
      });

      this.orderEventsTopic.addSubscription(subscription);

      // Grant SNS permission to send messages to the queue
      queue.grantSendMessages(new iam.ServicePrincipal('sns.amazonaws.com'));
    });
  }

  /**
   * Create CloudWatch alarms for monitoring
   */
  private createCloudWatchAlarms(
    resourcePrefix: string,
    queueConfigs: { [key: string]: QueueConfig }
  ): { [key: string]: cloudwatch.Alarm } {
    const alarms: { [key: string]: cloudwatch.Alarm } = {};

    // Create alarms for each queue
    Object.entries(queueConfigs).forEach(([key, config]) => {
      const queue = this.queues[key];
      
      // Queue depth alarm
      alarms[`${key}-depth`] = new cloudwatch.Alarm(this, `${this.capitalizeFirst(key)}QueueDepthAlarm`, {
        alarmName: `${resourcePrefix}-${config.name}-queue-depth`,
        alarmDescription: `Monitor ${config.name} queue depth`,
        metric: queue.metricApproximateNumberOfVisibleMessages({
          period: cdk.Duration.minutes(5),
          statistic: 'Average',
        }),
        threshold: config.alarmThreshold,
        evaluationPeriods: 2,
        comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      });

      // Dead letter queue alarm
      alarms[`${key}-dlq`] = new cloudwatch.Alarm(this, `${this.capitalizeFirst(key)}DLQAlarm`, {
        alarmName: `${resourcePrefix}-${config.name}-dlq-messages`,
        alarmDescription: `Monitor ${config.name} dead letter queue for failed messages`,
        metric: this.deadLetterQueues[key].metricApproximateNumberOfVisibleMessages({
          period: cdk.Duration.minutes(5),
          statistic: 'Sum',
        }),
        threshold: 1,
        evaluationPeriods: 1,
        comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
        treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      });
    });

    // SNS failed notifications alarm
    alarms['sns-failed'] = new cloudwatch.Alarm(this, 'SNSFailedDeliveriesAlarm', {
      alarmName: `${resourcePrefix}-sns-failed-deliveries`,
      alarmDescription: 'Monitor SNS failed deliveries',
      metric: this.orderEventsTopic.metricNumberOfNotificationsFailed({
        period: cdk.Duration.minutes(5),
        statistic: 'Sum',
      }),
      threshold: 5,
      evaluationPeriods: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    return alarms;
  }

  /**
   * Create CloudWatch dashboard for monitoring
   */
  private createCloudWatchDashboard(resourcePrefix: string): void {
    const dashboard = new cloudwatch.Dashboard(this, 'MessageFanoutDashboard', {
      dashboardName: `${resourcePrefix}-message-fanout-dashboard`,
    });

    // SNS metrics widget
    const snsWidget = new cloudwatch.GraphWidget({
      title: 'SNS Message Publishing',
      width: 12,
      height: 6,
      left: [
        this.orderEventsTopic.metricNumberOfMessagesPublished({
          period: cdk.Duration.minutes(5),
          statistic: 'Sum',
        }),
      ],
      right: [
        this.orderEventsTopic.metricNumberOfNotificationsFailed({
          period: cdk.Duration.minutes(5),
          statistic: 'Sum',
        }),
      ],
    });

    // SQS queue depths widget
    const sqsWidget = new cloudwatch.GraphWidget({
      title: 'SQS Queue Depths',
      width: 12,
      height: 6,
      left: Object.values(this.queues).map(queue => 
        queue.metricApproximateNumberOfVisibleMessages({
          period: cdk.Duration.minutes(5),
          statistic: 'Average',
        })
      ),
    });

    // DLQ messages widget
    const dlqWidget = new cloudwatch.GraphWidget({
      title: 'Dead Letter Queue Messages',
      width: 12,
      height: 6,
      left: Object.values(this.deadLetterQueues).map(queue => 
        queue.metricApproximateNumberOfVisibleMessages({
          period: cdk.Duration.minutes(5),
          statistic: 'Sum',
        })
      ),
    });

    // Message processing age widget
    const ageWidget = new cloudwatch.GraphWidget({
      title: 'Message Processing Age',
      width: 12,
      height: 6,
      left: Object.values(this.queues).map(queue => 
        queue.metricApproximateAgeOfOldestMessage({
          period: cdk.Duration.minutes(5),
          statistic: 'Maximum',
        })
      ),
    });

    dashboard.addWidgets(snsWidget, sqsWidget);
    dashboard.addWidgets(dlqWidget, ageWidget);
  }

  /**
   * Create filter policy for SNS subscriptions
   */
  private createFilterPolicy(filterPolicy: { [key: string]: string[] }): { [key: string]: sns.SubscriptionFilter } {
    const policy: { [key: string]: sns.SubscriptionFilter } = {};
    
    Object.entries(filterPolicy).forEach(([key, values]) => {
      policy[key] = sns.SubscriptionFilter.stringFilter({
        allowlist: values,
      });
    });

    return policy;
  }

  /**
   * Add common tags to all resources
   */
  private addCommonTags(environmentName: string): void {
    cdk.Tags.of(this).add('Environment', environmentName);
    cdk.Tags.of(this).add('Project', 'MessageFanout');
    cdk.Tags.of(this).add('ManagedBy', 'AWS-CDK');
    cdk.Tags.of(this).add('Purpose', 'EcommerceOrderProcessing');
  }

  /**
   * Create CloudFormation outputs
   */
  private createOutputs(): void {
    // SNS Topic ARN
    new cdk.CfnOutput(this, 'OrderEventsTopicArn', {
      value: this.orderEventsTopic.topicArn,
      description: 'ARN of the SNS topic for order events',
      exportName: `${this.stackName}-OrderEventsTopicArn`,
    });

    // SNS Topic Name
    new cdk.CfnOutput(this, 'OrderEventsTopicName', {
      value: this.orderEventsTopic.topicName,
      description: 'Name of the SNS topic for order events',
      exportName: `${this.stackName}-OrderEventsTopicName`,
    });

    // Queue ARNs and URLs
    Object.entries(this.queues).forEach(([key, queue]) => {
      new cdk.CfnOutput(this, `${this.capitalizeFirst(key)}QueueArn`, {
        value: queue.queueArn,
        description: `ARN of the ${key} processing queue`,
        exportName: `${this.stackName}-${this.capitalizeFirst(key)}QueueArn`,
      });

      new cdk.CfnOutput(this, `${this.capitalizeFirst(key)}QueueUrl`, {
        value: queue.queueUrl,
        description: `URL of the ${key} processing queue`,
        exportName: `${this.stackName}-${this.capitalizeFirst(key)}QueueUrl`,
      });
    });

    // Dead Letter Queue ARNs
    Object.entries(this.deadLetterQueues).forEach(([key, queue]) => {
      new cdk.CfnOutput(this, `${this.capitalizeFirst(key)}DLQArn`, {
        value: queue.queueArn,
        description: `ARN of the ${key} dead letter queue`,
        exportName: `${this.stackName}-${this.capitalizeFirst(key)}DLQArn`,
      });
    });
  }

  /**
   * Helper method to capitalize first letter
   */
  private capitalizeFirst(str: string): string {
    return str.charAt(0).toUpperCase() + str.slice(1);
  }
}

/**
 * CDK App
 */
const app = new cdk.App();

// Get configuration from CDK context or environment variables
const resourcePrefix = app.node.tryGetContext('resourcePrefix') || process.env.RESOURCE_PREFIX || 'message-fanout';
const environmentName = app.node.tryGetContext('environment') || process.env.ENVIRONMENT || 'dev';
const enableMonitoring = app.node.tryGetContext('enableMonitoring') !== 'false';

// Create the stack
new MessageFanoutStack(app, 'MessageFanoutStack', {
  resourcePrefix,
  environmentName,
  enableMonitoring,
  description: 'CDK Stack for SNS Message Fan-out with Multiple SQS Queues',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'MessageFanout',
    Environment: environmentName,
    ManagedBy: 'AWS-CDK',
  },
});

// Synthesize the app
app.synth();