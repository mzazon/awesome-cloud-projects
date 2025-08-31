#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as cloudwatchActions from 'aws-cdk-lib/aws-cloudwatch-actions';

/**
 * Properties for the ServiceQuotaMonitoringStack
 */
interface ServiceQuotaMonitoringStackProps extends cdk.StackProps {
  /**
   * Email address to receive quota notifications
   * @default - No email subscription will be created
   */
  readonly notificationEmail?: string;

  /**
   * Threshold percentage for quota utilization alarms (0-100)
   * @default 80
   */
  readonly quotaThreshold?: number;

  /**
   * Whether to enable email subscription
   * @default true
   */
  readonly enableEmailNotification?: boolean;
}

/**
 * CDK Stack for AWS Service Quota Monitoring with CloudWatch Alarms
 * 
 * This stack creates:
 * - SNS Topic for quota notifications
 * - CloudWatch Alarms for EC2, VPC, and Lambda service quotas
 * - Optional email subscription to the SNS topic
 */
export class ServiceQuotaMonitoringStack extends cdk.Stack {
  public readonly snsTopicArn: string;
  public readonly alarmNames: string[];

  constructor(scope: Construct, id: string, props: ServiceQuotaMonitoringStackProps = {}) {
    super(scope, id, props);

    // Default values
    const quotaThreshold = props.quotaThreshold ?? 80;
    const enableEmailNotification = props.enableEmailNotification ?? true;

    // Validate threshold
    if (quotaThreshold < 0 || quotaThreshold > 100) {
      throw new Error('quotaThreshold must be between 0 and 100');
    }

    // Create SNS Topic for quota alerts
    const quotaAlertsTopic = new sns.Topic(this, 'ServiceQuotaAlertsTopic', {
      topicName: `service-quota-alerts-${this.stackName.toLowerCase()}`,
      displayName: 'AWS Service Quota Alerts',
      description: 'SNS topic for AWS service quota utilization alerts'
    });

    // Add email subscription if email is provided and enabled
    if (props.notificationEmail && enableEmailNotification) {
      quotaAlertsTopic.addSubscription(
        new snsSubscriptions.EmailSubscription(props.notificationEmail)
      );
    }

    // Store SNS Topic ARN for output
    this.snsTopicArn = quotaAlertsTopic.topicArn;

    // Create CloudWatch Alarm for EC2 Running Instances Quota
    const ec2InstancesAlarm = new cloudwatch.Alarm(this, 'EC2RunningInstancesQuotaAlarm', {
      alarmName: 'EC2-Running-Instances-Quota-Alert',
      alarmDescription: `Alert when EC2 running instances exceed ${quotaThreshold}% of quota`,
      metric: new cloudwatch.Metric({
        namespace: 'AWS/ServiceQuotas',
        metricName: 'ServiceQuotaUtilization',
        dimensionsMap: {
          'ServiceCode': 'ec2',
          'QuotaCode': 'L-1216C47A'  // Running On-Demand instances quota code
        },
        statistic: 'Maximum',
        period: cdk.Duration.minutes(5)
      }),
      threshold: quotaThreshold,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    // Add SNS action to EC2 alarm
    ec2InstancesAlarm.addAlarmAction(new cloudwatchActions.SnsAction(quotaAlertsTopic));

    // Create CloudWatch Alarm for VPC Quota
    const vpcQuotaAlarm = new cloudwatch.Alarm(this, 'VPCQuotaAlarm', {
      alarmName: 'VPC-Quota-Alert',
      alarmDescription: `Alert when VPC count exceeds ${quotaThreshold}% of quota`,
      metric: new cloudwatch.Metric({
        namespace: 'AWS/ServiceQuotas',
        metricName: 'ServiceQuotaUtilization',
        dimensionsMap: {
          'ServiceCode': 'vpc',
          'QuotaCode': 'L-F678F1CE'  // VPCs per Region quota code
        },
        statistic: 'Maximum',
        period: cdk.Duration.minutes(5)
      }),
      threshold: quotaThreshold,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    // Add SNS action to VPC alarm
    vpcQuotaAlarm.addAlarmAction(new cloudwatchActions.SnsAction(quotaAlertsTopic));

    // Create CloudWatch Alarm for Lambda Concurrent Executions Quota
    const lambdaConcurrentExecutionsAlarm = new cloudwatch.Alarm(this, 'LambdaConcurrentExecutionsQuotaAlarm', {
      alarmName: 'Lambda-Concurrent-Executions-Quota-Alert',
      alarmDescription: `Alert when Lambda concurrent executions exceed ${quotaThreshold}% of quota`,
      metric: new cloudwatch.Metric({
        namespace: 'AWS/ServiceQuotas',
        metricName: 'ServiceQuotaUtilization',
        dimensionsMap: {
          'ServiceCode': 'lambda',
          'QuotaCode': 'L-B99A9384'  // Concurrent executions quota code
        },
        statistic: 'Maximum',
        period: cdk.Duration.minutes(5)
      }),
      threshold: quotaThreshold,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    // Add SNS action to Lambda alarm
    lambdaConcurrentExecutionsAlarm.addAlarmAction(new cloudwatchActions.SnsAction(quotaAlertsTopic));

    // Store alarm names for reference
    this.alarmNames = [
      ec2InstancesAlarm.alarmName,
      vpcQuotaAlarm.alarmName,
      lambdaConcurrentExecutionsAlarm.alarmName
    ];

    // Add tags to all resources
    cdk.Tags.of(this).add('Project', 'ServiceQuotaMonitoring');
    cdk.Tags.of(this).add('Environment', props.env?.account || 'development');
    cdk.Tags.of(this).add('Purpose', 'ProactiveQuotaMonitoring');

    // CloudFormation Outputs
    new cdk.CfnOutput(this, 'SNSTopicArn', {
      value: quotaAlertsTopic.topicArn,
      description: 'ARN of the SNS topic for service quota alerts',
      exportName: `${this.stackName}-SNSTopicArn`
    });

    new cdk.CfnOutput(this, 'EC2InstancesAlarmName', {
      value: ec2InstancesAlarm.alarmName,
      description: 'Name of the CloudWatch alarm for EC2 running instances quota',
      exportName: `${this.stackName}-EC2InstancesAlarmName`
    });

    new cdk.CfnOutput(this, 'VPCAlarmName', {
      value: vpcQuotaAlarm.alarmName,
      description: 'Name of the CloudWatch alarm for VPC quota',
      exportName: `${this.stackName}-VPCAlarmName`
    });

    new cdk.CfnOutput(this, 'LambdaAlarmName', {
      value: lambdaConcurrentExecutionsAlarm.alarmName,
      description: 'Name of the CloudWatch alarm for Lambda concurrent executions quota',
      exportName: `${this.stackName}-LambdaAlarmName`
    });

    new cdk.CfnOutput(this, 'QuotaThreshold', {
      value: quotaThreshold.toString(),
      description: 'Threshold percentage used for quota utilization alarms'
    });

    if (props.notificationEmail && enableEmailNotification) {
      new cdk.CfnOutput(this, 'NotificationEmail', {
        value: props.notificationEmail,
        description: 'Email address subscribed to quota alerts (confirmation required)'
      });
    }
  }
}

/**
 * CDK Application
 */
const app = new cdk.App();

// Get context values for configuration
const notificationEmail = app.node.tryGetContext('notificationEmail');
const quotaThreshold = app.node.tryGetContext('quotaThreshold');
const enableEmailNotification = app.node.tryGetContext('enableEmailNotification');

// Create the stack
new ServiceQuotaMonitoringStack(app, 'ServiceQuotaMonitoringStack', {
  notificationEmail: notificationEmail,
  quotaThreshold: quotaThreshold ? parseInt(quotaThreshold) : undefined,
  enableEmailNotification: enableEmailNotification !== 'false',
  description: 'AWS Service Quota Monitoring with CloudWatch Alarms and SNS Notifications',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
});

app.synth();