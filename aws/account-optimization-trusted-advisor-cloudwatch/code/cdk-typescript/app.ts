#!/usr/bin/env node

/**
 * AWS CDK Application for Account Optimization Monitoring
 * 
 * This application deploys a monitoring solution that leverages AWS Trusted Advisor's
 * built-in optimization checks with CloudWatch alarms and SNS notifications to 
 * proactively alert teams when account optimization opportunities arise.
 * 
 * The solution monitors Trusted Advisor metrics in real-time, automatically triggering 
 * email notifications when cost savings, security improvements, or performance 
 * optimizations are identified.
 */

import * as cdk from 'aws-cdk-lib';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as subscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as iam from 'aws-cdk-lib/aws-iam';
import { AwsSolutionsChecks } from 'cdk-nag';
import { Construct } from 'constructs';

/**
 * Properties for the Trusted Advisor Monitoring Stack
 */
interface TrustedAdvisorMonitoringStackProps extends cdk.StackProps {
  /**
   * Email address to receive optimization alerts
   */
  readonly notificationEmail: string;
  
  /**
   * Optional prefix for resource names to ensure uniqueness
   */
  readonly resourcePrefix?: string;
  
  /**
   * Threshold for cost optimization alarms (number of yellow resources)
   * @default 1
   */
  readonly costOptimizationThreshold?: number;
  
  /**
   * Threshold for security alarms (number of red resources)
   * @default 1
   */
  readonly securityThreshold?: number;
  
  /**
   * Threshold for service limits (percentage of quota usage)
   * @default 80
   */
  readonly serviceLimitsThreshold?: number;
}

/**
 * AWS CDK Stack for Trusted Advisor Monitoring
 * 
 * This stack creates:
 * - SNS topic for notifications
 * - Email subscription to the SNS topic
 * - CloudWatch alarms for various Trusted Advisor checks
 * - Appropriate IAM permissions
 */
class TrustedAdvisorMonitoringStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: TrustedAdvisorMonitoringStackProps) {
    super(scope, id, props);

    // Validate that we're deploying to us-east-1 (required for Trusted Advisor)
    if (this.region !== 'us-east-1') {
      throw new Error(
        'Trusted Advisor metrics are only available in us-east-1 region. ' +
        'Please deploy this stack to us-east-1.'
      );
    }

    // Generate resource prefix for unique naming
    const resourcePrefix = props.resourcePrefix || 
      `trusted-advisor-${Math.random().toString(36).substring(2, 8)}`;

    // Set default thresholds
    const costOptimizationThreshold = props.costOptimizationThreshold ?? 1;
    const securityThreshold = props.securityThreshold ?? 1;
    const serviceLimitsThreshold = props.serviceLimitsThreshold ?? 80;

    // Create SNS Topic for notifications
    const alertsTopic = new sns.Topic(this, 'TrustedAdvisorAlertsTopic', {
      topicName: `${resourcePrefix}-alerts`,
      displayName: 'AWS Account Optimization Alerts',
      description: 'SNS topic for AWS Trusted Advisor optimization alerts'
    });

    // Add email subscription to SNS topic
    alertsTopic.addSubscription(
      new subscriptions.EmailSubscription(props.notificationEmail)
    );

    // Create CloudWatch alarm for Cost Optimization (Low Utilization EC2 Instances)
    const costOptimizationAlarm = new cloudwatch.Alarm(this, 'CostOptimizationAlarm', {
      alarmName: `${resourcePrefix}-cost-optimization`,
      alarmDescription: 'Alert when Trusted Advisor identifies cost optimization opportunities',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/TrustedAdvisor',
        metricName: 'YellowResources',
        dimensionsMap: {
          CheckName: 'Low Utilization Amazon EC2 Instances'
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5)
      }),
      threshold: costOptimizationThreshold,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    // Add SNS action to cost optimization alarm
    costOptimizationAlarm.addAlarmAction(
      new cloudwatch.SnsAction(alertsTopic)
    );

    // Create CloudWatch alarm for Security (Security Groups - Unrestricted Ports)
    const securityAlarm = new cloudwatch.Alarm(this, 'SecurityAlarm', {
      alarmName: `${resourcePrefix}-security`,
      alarmDescription: 'Alert when Trusted Advisor identifies security recommendations',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/TrustedAdvisor',
        metricName: 'RedResources',
        dimensionsMap: {
          CheckName: 'Security Groups - Specific Ports Unrestricted'
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5)
      }),
      threshold: securityThreshold,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    // Add SNS action to security alarm
    securityAlarm.addAlarmAction(
      new cloudwatch.SnsAction(alertsTopic)
    );

    // Create CloudWatch alarm for Service Limits
    const serviceLimitsAlarm = new cloudwatch.Alarm(this, 'ServiceLimitsAlarm', {
      alarmName: `${resourcePrefix}-service-limits`,
      alarmDescription: 'Alert when service usage approaches limits',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/TrustedAdvisor',
        metricName: 'ServiceLimitUsage',
        dimensionsMap: {
          ServiceName: 'EC2',
          ServiceLimit: 'Running On-Demand EC2 Instances',
          Region: this.region
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5)
      }),
      threshold: serviceLimitsThreshold,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    // Add SNS action to service limits alarm
    serviceLimitsAlarm.addAlarmAction(
      new cloudwatch.SnsAction(alertsTopic)
    );

    // Create additional alarms for other important Trusted Advisor checks
    const performanceAlarm = new cloudwatch.Alarm(this, 'PerformanceAlarm', {
      alarmName: `${resourcePrefix}-performance`,
      alarmDescription: 'Alert when Trusted Advisor identifies performance recommendations',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/TrustedAdvisor',
        metricName: 'YellowResources',
        dimensionsMap: {
          CheckName: 'Amazon RDS Idle DB Instances'
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5)
      }),
      threshold: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    // Add SNS action to performance alarm
    performanceAlarm.addAlarmAction(
      new cloudwatch.SnsAction(alertsTopic)
    );

    // Create CloudWatch Dashboard for monitoring
    const dashboard = new cloudwatch.Dashboard(this, 'TrustedAdvisorDashboard', {
      dashboardName: `${resourcePrefix}-dashboard`,
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'Cost Optimization Opportunities',
            left: [costOptimizationAlarm.metric],
            width: 12,
            height: 6
          }),
          new cloudwatch.GraphWidget({
            title: 'Security Issues',
            left: [securityAlarm.metric],
            width: 12,
            height: 6
          })
        ],
        [
          new cloudwatch.GraphWidget({
            title: 'Service Limits Usage',
            left: [serviceLimitsAlarm.metric],
            width: 12,
            height: 6
          }),
          new cloudwatch.GraphWidget({
            title: 'Performance Issues',
            left: [performanceAlarm.metric],
            width: 12,
            height: 6
          })
        ]
      ]
    });

    // Outputs for reference
    new cdk.CfnOutput(this, 'SNSTopicArn', {
      value: alertsTopic.topicArn,
      description: 'ARN of the SNS topic for Trusted Advisor alerts',
      exportName: `${resourcePrefix}-sns-topic-arn`
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${dashboard.dashboardName}`,
      description: 'URL to the CloudWatch dashboard for Trusted Advisor monitoring'
    });

    new cdk.CfnOutput(this, 'CostOptimizationAlarm', {
      value: costOptimizationAlarm.alarmName,
      description: 'Name of the cost optimization CloudWatch alarm'
    });

    new cdk.CfnOutput(this, 'SecurityAlarm', {
      value: securityAlarm.alarmName,
      description: 'Name of the security CloudWatch alarm'
    });

    new cdk.CfnOutput(this, 'ServiceLimitsAlarm', {
      value: serviceLimitsAlarm.alarmName,
      description: 'Name of the service limits CloudWatch alarm'
    });

    // Add tags to all resources
    cdk.Tags.of(this).add('Project', 'TrustedAdvisorMonitoring');
    cdk.Tags.of(this).add('Environment', 'Production');
    cdk.Tags.of(this).add('ManagedBy', 'CDK');
  }
}

/**
 * CDK Application
 */
const app = new cdk.App();

// Get configuration from context or environment variables
const notificationEmail = app.node.tryGetContext('notificationEmail') || 
  process.env.NOTIFICATION_EMAIL;

if (!notificationEmail) {
  throw new Error(
    'Notification email is required. ' +
    'Set via context (-c notificationEmail=email@domain.com) or ' +
    'environment variable NOTIFICATION_EMAIL'
  );
}

const resourcePrefix = app.node.tryGetContext('resourcePrefix') || 
  process.env.RESOURCE_PREFIX;

// Create the stack
const trustedAdvisorStack = new TrustedAdvisorMonitoringStack(app, 'TrustedAdvisorMonitoringStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: 'us-east-1' // Trusted Advisor requires us-east-1
  },
  notificationEmail,
  resourcePrefix,
  costOptimizationThreshold: Number(app.node.tryGetContext('costOptimizationThreshold')) || 1,
  securityThreshold: Number(app.node.tryGetContext('securityThreshold')) || 1,
  serviceLimitsThreshold: Number(app.node.tryGetContext('serviceLimitsThreshold')) || 80,
  description: 'AWS Trusted Advisor monitoring with CloudWatch alarms and SNS notifications'
});

// Apply CDK Nag for security best practices
AwsSolutionsChecks.check(app);

// Synthesize the app
app.synth();