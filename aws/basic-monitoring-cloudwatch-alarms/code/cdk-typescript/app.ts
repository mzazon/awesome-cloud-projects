#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as cloudwatchActions from 'aws-cdk-lib/aws-cloudwatch-actions';
import { Construct } from 'constructs';

/**
 * Props for the BasicMonitoringStack
 */
export interface BasicMonitoringStackProps extends cdk.StackProps {
  /**
   * Email address for alarm notifications
   */
  readonly notificationEmail: string;
  
  /**
   * Prefix for alarm names (defaults to stack name)
   */
  readonly alarmNamePrefix?: string;
  
  /**
   * CPU threshold percentage (default: 80%)
   */
  readonly cpuThreshold?: number;
  
  /**
   * Response time threshold in seconds (default: 1.0)
   */
  readonly responseTimeThreshold?: number;
  
  /**
   * Database connections threshold (default: 80)
   */
  readonly dbConnectionsThreshold?: number;
}

/**
 * Stack for setting up basic monitoring with CloudWatch alarms
 * 
 * This stack creates:
 * - SNS topic for alarm notifications
 * - Email subscription to the SNS topic
 * - CloudWatch alarms for EC2 CPU, ALB response time, and RDS connections
 */
export class BasicMonitoringStack extends cdk.Stack {
  /**
   * The SNS topic for alarm notifications
   */
  public readonly alarmTopic: sns.Topic;
  
  /**
   * The CPU utilization alarm
   */
  public readonly cpuAlarm: cloudwatch.Alarm;
  
  /**
   * The response time alarm
   */
  public readonly responseTimeAlarm: cloudwatch.Alarm;
  
  /**
   * The database connections alarm
   */
  public readonly dbConnectionsAlarm: cloudwatch.Alarm;

  constructor(scope: Construct, id: string, props: BasicMonitoringStackProps) {
    super(scope, id, props);

    // Set default values
    const alarmNamePrefix = props.alarmNamePrefix || this.stackName;
    const cpuThreshold = props.cpuThreshold || 80;
    const responseTimeThreshold = props.responseTimeThreshold || 1.0;
    const dbConnectionsThreshold = props.dbConnectionsThreshold || 80;

    // Create SNS topic for alarm notifications
    this.alarmTopic = new sns.Topic(this, 'AlarmTopic', {
      topicName: `${alarmNamePrefix}-monitoring-alerts`,
      displayName: 'CloudWatch Monitoring Alerts',
      description: 'SNS topic for CloudWatch alarm notifications'
    });

    // Subscribe email address to SNS topic
    this.alarmTopic.addSubscription(new snsSubscriptions.EmailSubscription(props.notificationEmail));

    // Create SNS alarm action
    const snsAlarmAction = new cloudwatchActions.SnsAction(this.alarmTopic);

    // Create CloudWatch alarm for high CPU utilization
    this.cpuAlarm = new cloudwatch.Alarm(this, 'HighCPUAlarm', {
      alarmName: `${alarmNamePrefix}-HighCPUUtilization`,
      alarmDescription: `Triggers when EC2 CPU exceeds ${cpuThreshold}%`,
      metric: new cloudwatch.Metric({
        namespace: 'AWS/EC2',
        metricName: 'CPUUtilization',
        statistic: 'Average',
        period: cdk.Duration.minutes(5), // 300 seconds
      }),
      threshold: cpuThreshold,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Add alarm and OK actions to CPU alarm
    this.cpuAlarm.addAlarmAction(snsAlarmAction);
    this.cpuAlarm.addOkAction(snsAlarmAction);

    // Create CloudWatch alarm for high Application Load Balancer response time
    this.responseTimeAlarm = new cloudwatch.Alarm(this, 'HighResponseTimeAlarm', {
      alarmName: `${alarmNamePrefix}-HighResponseTime`,
      alarmDescription: `Triggers when ALB response time exceeds ${responseTimeThreshold} second(s)`,
      metric: new cloudwatch.Metric({
        namespace: 'AWS/ApplicationELB',
        metricName: 'TargetResponseTime',
        statistic: 'Average',
        period: cdk.Duration.minutes(5), // 300 seconds
      }),
      threshold: responseTimeThreshold,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 3,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Add alarm action to response time alarm
    this.responseTimeAlarm.addAlarmAction(snsAlarmAction);

    // Create CloudWatch alarm for high RDS database connections
    this.dbConnectionsAlarm = new cloudwatch.Alarm(this, 'HighDBConnectionsAlarm', {
      alarmName: `${alarmNamePrefix}-HighDBConnections`,
      alarmDescription: `Triggers when RDS connections exceed ${dbConnectionsThreshold}`,
      metric: new cloudwatch.Metric({
        namespace: 'AWS/RDS',
        metricName: 'DatabaseConnections',
        statistic: 'Average',
        period: cdk.Duration.minutes(5), // 300 seconds
      }),
      threshold: dbConnectionsThreshold,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Add alarm action to database connections alarm
    this.dbConnectionsAlarm.addAlarmAction(snsAlarmAction);

    // Create CloudFormation outputs
    new cdk.CfnOutput(this, 'SNSTopicArn', {
      value: this.alarmTopic.topicArn,
      description: 'ARN of the SNS topic for alarm notifications',
      exportName: `${this.stackName}-SNSTopicArn`,
    });

    new cdk.CfnOutput(this, 'NotificationEmail', {
      value: props.notificationEmail,
      description: 'Email address subscribed to alarm notifications',
    });

    new cdk.CfnOutput(this, 'CPUAlarmName', {
      value: this.cpuAlarm.alarmName,
      description: 'Name of the CPU utilization alarm',
    });

    new cdk.CfnOutput(this, 'ResponseTimeAlarmName', {
      value: this.responseTimeAlarm.alarmName,
      description: 'Name of the response time alarm',
    });

    new cdk.CfnOutput(this, 'DBConnectionsAlarmName', {
      value: this.dbConnectionsAlarm.alarmName,
      description: 'Name of the database connections alarm',
    });
  }
}

/**
 * CDK App for Basic Monitoring with CloudWatch Alarms
 */
const app = new cdk.App();

// Get configuration from context or environment variables
const notificationEmail = app.node.tryGetContext('notificationEmail') || 
                         process.env.NOTIFICATION_EMAIL || 
                         'your-email@example.com';

const stackName = app.node.tryGetContext('stackName') || 'BasicMonitoringStack';
const cpuThreshold = app.node.tryGetContext('cpuThreshold') || 80;
const responseTimeThreshold = app.node.tryGetContext('responseTimeThreshold') || 1.0;
const dbConnectionsThreshold = app.node.tryGetContext('dbConnectionsThreshold') || 80;

// Validate email format
const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
if (!emailRegex.test(notificationEmail)) {
  throw new Error('Invalid email format. Please provide a valid email address.');
}

// Create the monitoring stack
new BasicMonitoringStack(app, stackName, {
  notificationEmail,
  cpuThreshold,
  responseTimeThreshold,
  dbConnectionsThreshold,
  description: 'Basic monitoring stack with CloudWatch alarms and SNS notifications',
  
  // Add tags for resource organization
  tags: {
    Project: 'BasicMonitoring',
    Environment: app.node.tryGetContext('environment') || 'dev',
    Owner: 'CloudOps',
  },
});