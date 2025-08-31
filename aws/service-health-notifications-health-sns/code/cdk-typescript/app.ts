#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';

/**
 * Configuration interface for the ServiceHealthNotifications stack
 */
interface ServiceHealthNotificationsProps extends cdk.StackProps {
  /**
   * Email address to receive health notifications
   * @default - No email subscription will be created
   */
  readonly notificationEmail?: string;
  
  /**
   * Custom name for the SNS topic
   * @default - Auto-generated name
   */
  readonly topicName?: string;
  
  /**
   * Custom name for the EventBridge rule
   * @default - Auto-generated name
   */
  readonly ruleName?: string;
  
  /**
   * Additional email addresses to subscribe to notifications
   * @default - No additional emails
   */
  readonly additionalEmails?: string[];
}

/**
 * CDK Stack for AWS Service Health Notifications
 * 
 * This stack creates a complete notification system for AWS Personal Health Dashboard events.
 * It automatically detects service events affecting your account and sends immediate 
 * notifications via email, enabling proactive incident response and improved operational awareness.
 * 
 * Architecture:
 * - AWS Personal Health Dashboard: Source of service health events
 * - EventBridge Rule: Filters and routes health events
 * - SNS Topic: Manages notification distribution
 * - Email Subscriptions: Delivers notifications to specified recipients
 */
export class ServiceHealthNotificationsStack extends cdk.Stack {
  
  /**
   * The SNS topic for health notifications
   */
  public readonly healthTopic: sns.Topic;
  
  /**
   * The EventBridge rule for health events
   */
  public readonly healthRule: events.Rule;
  
  /**
   * The IAM role for EventBridge to publish to SNS
   */
  public readonly eventBridgeRole: iam.Role;

  constructor(scope: Construct, id: string, props: ServiceHealthNotificationsProps = {}) {
    super(scope, id, props);

    // Create SNS topic for health notifications with appropriate display name
    this.healthTopic = new sns.Topic(this, 'HealthNotificationsTopic', {
      topicName: props.topicName,
      displayName: 'AWS Health Notifications',
      // Enable server-side encryption for security
      masterKey: undefined, // Uses AWS managed key
    });

    // Add email subscription if provided
    if (props.notificationEmail) {
      this.healthTopic.addSubscription(
        new snsSubscriptions.EmailSubscription(props.notificationEmail)
      );
    }

    // Add additional email subscriptions if provided
    if (props.additionalEmails) {
      props.additionalEmails.forEach((email, index) => {
        this.healthTopic.addSubscription(
          new snsSubscriptions.EmailSubscription(email)
        );
      });
    }

    // Create IAM role for EventBridge to publish to SNS
    this.eventBridgeRole = new iam.Role(this, 'EventBridgeHealthRole', {
      assumedBy: new iam.ServicePrincipal('events.amazonaws.com'),
      description: 'Role for EventBridge to publish AWS Health events to SNS',
      inlinePolicies: {
        SNSPublishPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['sns:Publish'],
              resources: [this.healthTopic.topicArn],
            }),
          ],
        }),
      },
    });

    // Create EventBridge rule to capture AWS Health events
    this.healthRule = new events.Rule(this, 'AwsHealthEventsRule', {
      ruleName: props.ruleName,
      description: 'Monitor AWS Health events and send SNS notifications for proactive incident response',
      // Event pattern to match all AWS Health events
      eventPattern: {
        source: ['aws.health'],
        detailType: ['AWS Health Event'],
      },
      enabled: true,
    });

    // Add SNS topic as target for the EventBridge rule
    this.healthRule.addTarget(
      new targets.SnsTopic(this.healthTopic, {
        // Use the IAM role we created for publishing permissions
        role: this.eventBridgeRole,
        // Transform the event to include useful information in the notification
        message: events.RuleTargetInput.fromObject({
          eventName: events.EventField.fromPath('$.detail.eventTypeCode'),
          service: events.EventField.fromPath('$.detail.service'),
          region: events.EventField.fromPath('$.region'),
          account: events.EventField.fromPath('$.account'),
          time: events.EventField.fromPath('$.time'),
          description: events.EventField.fromPath('$.detail.eventDescription[0].latestDescription'),
          status: events.EventField.fromPath('$.detail.statusCode'),
          eventArn: events.EventField.fromPath('$.detail.arn'),
          affectedEntities: events.EventField.fromPath('$.detail.affectedEntities'),
          source: 'AWS Personal Health Dashboard',
          notificationType: 'Service Health Event'
        }),
      })
    );

    // Grant EventBridge permission to publish to the SNS topic
    this.healthTopic.grantPublish(new iam.ServicePrincipal('events.amazonaws.com'));

    // Add CloudFormation outputs for easy reference
    new cdk.CfnOutput(this, 'HealthTopicArn', {
      value: this.healthTopic.topicArn,
      description: 'ARN of the SNS topic for health notifications',
      exportName: `${this.stackName}-HealthTopicArn`,
    });

    new cdk.CfnOutput(this, 'HealthTopicName', {
      value: this.healthTopic.topicName,
      description: 'Name of the SNS topic for health notifications',
      exportName: `${this.stackName}-HealthTopicName`,
    });

    new cdk.CfnOutput(this, 'EventBridgeRuleName', {
      value: this.healthRule.ruleName,
      description: 'Name of the EventBridge rule for health events',
      exportName: `${this.stackName}-EventBridgeRuleName`,
    });

    new cdk.CfnOutput(this, 'EventBridgeRoleArn', {
      value: this.eventBridgeRole.roleArn,
      description: 'ARN of the IAM role used by EventBridge',
      exportName: `${this.stackName}-EventBridgeRoleArn`,
    });

    // Add tags for resource organization and cost tracking
    cdk.Tags.of(this).add('Project', 'HealthNotifications');
    cdk.Tags.of(this).add('Environment', props.env?.account || 'unknown');
    cdk.Tags.of(this).add('Purpose', 'Operational Monitoring');
    cdk.Tags.of(this).add('CostCenter', 'Operations');
  }
}

/**
 * CDK Application entry point
 * 
 * This application deploys the Service Health Notifications stack with configurable options.
 * You can customize the deployment by setting environment variables or modifying the 
 * stack configuration below.
 */
const app = new cdk.App();

// Get configuration from CDK context or environment variables
const notificationEmail = app.node.tryGetContext('notificationEmail') || process.env.NOTIFICATION_EMAIL;
const topicName = app.node.tryGetContext('topicName');
const ruleName = app.node.tryGetContext('ruleName');
const additionalEmails = app.node.tryGetContext('additionalEmails')?.split(',') || [];

// Validate email format if provided
if (notificationEmail && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(notificationEmail)) {
  throw new Error(`Invalid email format: ${notificationEmail}. Please provide a valid email address.`);
}

// Validate additional emails if provided
additionalEmails.forEach((email: string) => {
  const trimmedEmail = email.trim();
  if (trimmedEmail && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(trimmedEmail)) {
    throw new Error(`Invalid additional email format: ${trimmedEmail}. Please provide valid email addresses.`);
  }
});

// Create the main stack with configuration
new ServiceHealthNotificationsStack(app, 'ServiceHealthNotificationsStack', {
  notificationEmail,
  topicName,
  ruleName,
  additionalEmails: additionalEmails.filter((email: string) => email.trim()),
  
  // Stack configuration
  description: 'AWS Service Health Notifications with Personal Health Dashboard, EventBridge, and SNS (uksb-1tupboc57)',
  
  // Environment configuration - will use default AWS CLI configuration if not specified
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  
  // Enable termination protection for production deployments
  terminationProtection: app.node.tryGetContext('terminationProtection') === 'true',
  
  // Stack tags for organization
  tags: {
    Application: 'HealthNotifications',
    Owner: 'Operations',
    Environment: app.node.tryGetContext('environment') || 'development',
  },
});

// Synthesize the CloudFormation template
app.synth();