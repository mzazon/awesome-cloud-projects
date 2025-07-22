#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as cloudwatchActions from 'aws-cdk-lib/aws-cloudwatch-actions';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';

/**
 * Properties for the BasicLogMonitoringStack
 */
export interface BasicLogMonitoringStackProps extends cdk.StackProps {
  /**
   * Email address for receiving notifications
   * @default - No email subscription will be created
   */
  readonly notificationEmail?: string;
  
  /**
   * CloudWatch Log Group retention period in days
   * @default 7 days
   */
  readonly logRetentionDays?: logs.RetentionDays;
  
  /**
   * Error threshold for triggering alarms
   * @default 2
   */
  readonly errorThreshold?: number;
  
  /**
   * Alarm evaluation period in minutes
   * @default 5 minutes
   */
  readonly evaluationPeriodMinutes?: number;
}

/**
 * CDK Stack for Basic Log Monitoring with CloudWatch Logs and SNS
 * 
 * This stack creates:
 * - CloudWatch Log Group for application logs
 * - Metric Filter to detect error patterns
 * - CloudWatch Alarm for error threshold monitoring
 * - SNS Topic for alert notifications
 * - Lambda function for processing notifications
 * - Email subscription (optional)
 */
export class BasicLogMonitoringStack extends cdk.Stack {
  public readonly logGroup: logs.LogGroup;
  public readonly snsTopic: sns.Topic;
  public readonly alarm: cloudwatch.Alarm;
  public readonly lambdaFunction: lambda.Function;

  constructor(scope: Construct, id: string, props: BasicLogMonitoringStackProps = {}) {
    super(scope, id, props);

    // Extract properties with defaults
    const logRetentionDays = props.logRetentionDays ?? logs.RetentionDays.ONE_WEEK;
    const errorThreshold = props.errorThreshold ?? 2;
    const evaluationPeriodMinutes = props.evaluationPeriodMinutes ?? 5;

    // Create CloudWatch Log Group for application logs
    this.logGroup = new logs.LogGroup(this, 'ApplicationLogGroup', {
      logGroupName: '/aws/application/monitoring-demo',
      retention: logRetentionDays,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
    });

    // Create SNS Topic for alert notifications
    this.snsTopic = new sns.Topic(this, 'LogMonitoringAlerts', {
      topicName: `log-monitoring-alerts-${this.stackName.toLowerCase()}`,
      displayName: 'Log Monitoring Alerts',
      description: 'Topic for CloudWatch log monitoring alerts',
    });

    // Create Lambda function for processing notifications
    this.lambdaFunction = new lambda.Function(this, 'LogProcessor', {
      functionName: `log-processor-${this.stackName.toLowerCase()}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      timeout: cdk.Duration.seconds(60),
      memorySize: 256,
      description: 'Process CloudWatch alarm notifications and enrich alert data',
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Process CloudWatch alarm notifications and enrich alert data
    """
    
    try:
        # Parse SNS message
        for record in event.get('Records', []):
            sns_message = json.loads(record['Sns']['Message'])
            
            # Extract alarm details
            alarm_name = sns_message.get('AlarmName', 'Unknown')
            alarm_reason = sns_message.get('NewStateReason', 'No reason provided')
            alarm_state = sns_message.get('NewStateValue', 'Unknown')
            timestamp = sns_message.get('StateChangeTime', datetime.now().isoformat())
            
            # Log processing details
            logger.info(f"Processing alarm: {alarm_name}")
            logger.info(f"State: {alarm_state}")
            logger.info(f"Reason: {alarm_reason}")
            logger.info(f"Timestamp: {timestamp}")
            
            # Additional processing can be added here:
            # - Query CloudWatch Logs for error context
            # - Send notifications to external systems
            # - Trigger automated remediation
            
        return {
            'statusCode': 200,
            'body': json.dumps('Log processing completed successfully')
        }
        
    except Exception as e:
        logger.error(f"Error processing log event: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }
      `),
    });

    // Grant basic execution permissions to Lambda
    this.lambdaFunction.addToRolePolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'logs:CreateLogGroup',
        'logs:CreateLogStream',
        'logs:PutLogEvents',
      ],
      resources: ['*'],
    }));

    // Subscribe Lambda function to SNS topic
    this.snsTopic.addSubscription(new snsSubscriptions.LambdaSubscription(this.lambdaFunction));

    // Create email subscription if email is provided
    if (props.notificationEmail) {
      this.snsTopic.addSubscription(new snsSubscriptions.EmailSubscription(props.notificationEmail));
    }

    // Create CloudWatch metric for application errors
    const applicationErrorsMetric = new cloudwatch.Metric({
      namespace: 'CustomApp/Monitoring',
      metricName: 'ApplicationErrors',
      statistic: cloudwatch.Statistic.SUM,
      period: cdk.Duration.minutes(evaluationPeriodMinutes),
    });

    // Create metric filter to detect error patterns
    new logs.MetricFilter(this, 'ErrorCountFilter', {
      logGroup: this.logGroup,
      filterName: 'error-count-filter',
      filterPattern: logs.FilterPattern.anyTerm(
        '{ ($.level = "ERROR") }',
        '{ ($.message = "*ERROR*") }',
        '{ ($.message = "*FAILED*") }',
        '{ ($.message = "*EXCEPTION*") }',
        '{ ($.message = "*TIMEOUT*") }'
      ),
      metricNamespace: 'CustomApp/Monitoring',
      metricName: 'ApplicationErrors',
      metricValue: '1',
      defaultValue: 0,
    });

    // Create CloudWatch alarm for error threshold
    this.alarm = new cloudwatch.Alarm(this, 'ApplicationErrorsAlarm', {
      alarmName: 'application-errors-alarm',
      alarmDescription: 'Alert when application errors exceed threshold',
      metric: applicationErrorsMetric,
      threshold: errorThreshold,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 1,
      datapointsToAlarm: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Add SNS action to the alarm
    this.alarm.addAlarmAction(new cloudwatchActions.SnsAction(this.snsTopic));

    // Outputs for reference
    new cdk.CfnOutput(this, 'LogGroupName', {
      value: this.logGroup.logGroupName,
      description: 'CloudWatch Log Group name for application logs',
    });

    new cdk.CfnOutput(this, 'LogGroupArn', {
      value: this.logGroup.logGroupArn,
      description: 'CloudWatch Log Group ARN',
    });

    new cdk.CfnOutput(this, 'SnsTopicArn', {
      value: this.snsTopic.topicArn,
      description: 'SNS Topic ARN for log monitoring alerts',
    });

    new cdk.CfnOutput(this, 'SnsTopicName', {
      value: this.snsTopic.topicName,
      description: 'SNS Topic name',
    });

    new cdk.CfnOutput(this, 'AlarmArn', {
      value: this.alarm.alarmArn,
      description: 'CloudWatch Alarm ARN',
    });

    new cdk.CfnOutput(this, 'LambdaFunctionArn', {
      value: this.lambdaFunction.functionArn,
      description: 'Lambda function ARN for log processing',
    });

    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: this.lambdaFunction.functionName,
      description: 'Lambda function name',
    });

    // Tags for resource management
    cdk.Tags.of(this).add('Project', 'BasicLogMonitoring');
    cdk.Tags.of(this).add('Environment', 'Demo');
    cdk.Tags.of(this).add('Purpose', 'LogMonitoring');
  }
}

// Create the CDK app
const app = new cdk.App();

// Get context values for configuration
const notificationEmail = app.node.tryGetContext('notificationEmail');
const errorThreshold = app.node.tryGetContext('errorThreshold');
const evaluationPeriodMinutes = app.node.tryGetContext('evaluationPeriodMinutes');

// Create the stack
new BasicLogMonitoringStack(app, 'BasicLogMonitoringStack', {
  notificationEmail: notificationEmail,
  errorThreshold: errorThreshold ? parseInt(errorThreshold) : undefined,
  evaluationPeriodMinutes: evaluationPeriodMinutes ? parseInt(evaluationPeriodMinutes) : undefined,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'Basic Log Monitoring with CloudWatch Logs and SNS - Demo Stack',
});