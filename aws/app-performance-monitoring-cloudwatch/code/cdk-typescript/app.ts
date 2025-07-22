#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';

/**
 * Stack for automated application performance monitoring using CloudWatch Application Signals and EventBridge
 */
export class AutomatedApplicationPerformanceMonitoringStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource naming
    const uniqueSuffix = this.node.tryGetContext('uniqueSuffix') || cdk.Names.uniqueId(this).slice(-6).toLowerCase();

    // Parameters for customization
    const applicationName = new cdk.CfnParameter(this, 'ApplicationName', {
      type: 'String',
      default: 'MyApplication',
      description: 'Name of the application to monitor'
    });

    const notificationEmail = new cdk.CfnParameter(this, 'NotificationEmail', {
      type: 'String',
      default: 'admin@example.com',
      description: 'Email address for performance notifications',
      allowedPattern: '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$',
      constraintDescription: 'Must be a valid email address'
    });

    const latencyThreshold = new cdk.CfnParameter(this, 'LatencyThreshold', {
      type: 'Number',
      default: 2000,
      description: 'Latency threshold in milliseconds',
      minValue: 100,
      maxValue: 30000
    });

    const errorRateThreshold = new cdk.CfnParameter(this, 'ErrorRateThreshold', {
      type: 'Number',
      default: 5,
      description: 'Error rate threshold percentage',
      minValue: 0.1,
      maxValue: 50
    });

    const throughputThreshold = new cdk.CfnParameter(this, 'ThroughputThreshold', {
      type: 'Number',
      default: 10,
      description: 'Minimum throughput (requests per period)',
      minValue: 1,
      maxValue: 10000
    });

    // Create SNS topic for performance alerts
    const alertsTopic = new sns.Topic(this, 'PerformanceAlertsTopic', {
      topicName: `performance-alerts-${uniqueSuffix}`,
      displayName: 'Application Performance Alerts',
      deliveryPolicy: {
        http: {
          defaultHealthyRetryPolicy: {
            minDelayTarget: 20,
            maxDelayTarget: 20,
            numRetries: 3,
            numMaxDelayRetries: 0,
            numMinDelayRetries: 0,
            numNoDelayRetries: 0,
            backoffFunction: 'linear'
          },
          disableSubscriptionOverrides: false
        }
      }
    });

    // Add email subscription to SNS topic
    alertsTopic.addSubscription(new snsSubscriptions.EmailSubscription(notificationEmail.valueAsString));

    // Create CloudWatch Log Group for Application Signals
    const applicationSignalsLogGroup = new logs.LogGroup(this, 'ApplicationSignalsLogGroup', {
      logGroupName: '/aws/application-signals/data',
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    // Create IAM role for Lambda function
    const lambdaExecutionRole = new iam.Role(this, 'PerformanceProcessorRole', {
      roleName: `performance-processor-${uniqueSuffix}-role`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ],
      inlinePolicies: {
        PerformanceMonitoringPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'sns:Publish',
                'cloudwatch:DescribeAlarms',
                'cloudwatch:GetMetricStatistics',
                'autoscaling:DescribeAutoScalingGroups',
                'autoscaling:UpdateAutoScalingGroup'
              ],
              resources: ['*']
            })
          ]
        })
      }
    });

    // Create Lambda function for event processing
    const performanceProcessorFunction = new lambda.Function(this, 'PerformanceProcessorFunction', {
      functionName: `performance-processor-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaExecutionRole,
      timeout: cdk.Duration.seconds(60),
      memorySize: 256,
      environment: {
        SNS_TOPIC_ARN: alertsTopic.topicArn
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
from datetime import datetime
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Process CloudWatch alarm state changes and trigger appropriate actions
    """
    try:
        # Parse EventBridge event
        detail = event.get('detail', {})
        alarm_name = detail.get('alarmName', '')
        new_state = detail.get('newState', {})
        state_value = new_state.get('value', '')
        state_reason = new_state.get('reason', '')
        
        logger.info(f"Processing alarm: {alarm_name}, State: {state_value}")
        
        # Initialize AWS clients
        sns_client = boto3.client('sns')
        cloudwatch_client = boto3.client('cloudwatch')
        
        # Get SNS topic ARN from environment
        sns_topic_arn = os.environ.get('SNS_TOPIC_ARN')
        
        # Define response actions based on alarm state
        if state_value == 'ALARM':
            # Send immediate notification
            message = f"""
🚨 PERFORMANCE ALERT 🚨

Alarm: {alarm_name}
State: {state_value}
Reason: {state_reason}
Time: {datetime.now().isoformat()}

Automatic scaling has been triggered.
Monitor dashboard for real-time updates.
            """
            
            sns_client.publish(
                TopicArn=sns_topic_arn,
                Message=message,
                Subject=f"Performance Alert: {alarm_name}"
            )
            
            logger.info("Sent alarm notification and triggered scaling response")
            
        elif state_value == 'OK':
            # Send resolution notification
            message = f"""
✅ ALERT RESOLVED ✅

Alarm: {alarm_name}
State: {state_value}
Time: {datetime.now().isoformat()}

Performance metrics have returned to normal.
            """
            
            sns_client.publish(
                TopicArn=sns_topic_arn,
                Message=message,
                Subject=f"Alert Resolved: {alarm_name}"
            )
            
            logger.info("Sent resolution notification")
        
        return {
            'statusCode': 200,
            'body': json.dumps(f'Successfully processed alarm: {alarm_name}')
        }
        
    except Exception as e:
        logger.error(f"Error processing event: {str(e)}")
        raise e
`)
    });

    // Create EventBridge rule for CloudWatch alarm state changes
    const alarmStateChangeRule = new events.Rule(this, 'AlarmStateChangeRule', {
      ruleName: `performance-anomaly-rule-${uniqueSuffix}`,
      description: 'Route CloudWatch alarm state changes to Lambda processor',
      eventPattern: {
        source: ['aws.cloudwatch'],
        detailType: ['CloudWatch Alarm State Change'],
        detail: {
          state: {
            value: ['ALARM', 'OK']
          }
        }
      }
    });

    // Add Lambda function as target to EventBridge rule
    alarmStateChangeRule.addTarget(new targets.LambdaFunction(performanceProcessorFunction));

    // Create CloudWatch alarms for Application Signals metrics
    const highLatencyAlarm = new cloudwatch.Alarm(this, 'HighLatencyAlarm', {
      alarmName: `AppSignals-HighLatency-${uniqueSuffix}`,
      alarmDescription: 'Monitor application latency from Application Signals',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/ApplicationSignals',
        metricName: 'Latency',
        dimensionsMap: {
          Service: applicationName.valueAsString
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5)
      }),
      threshold: latencyThreshold.valueAsNumber,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2,
      datapointsToAlarm: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    const highErrorRateAlarm = new cloudwatch.Alarm(this, 'HighErrorRateAlarm', {
      alarmName: `AppSignals-HighErrorRate-${uniqueSuffix}`,
      alarmDescription: 'Monitor application error rate from Application Signals',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/ApplicationSignals',
        metricName: 'ErrorRate',
        dimensionsMap: {
          Service: applicationName.valueAsString
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5)
      }),
      threshold: errorRateThreshold.valueAsNumber,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 1,
      datapointsToAlarm: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    const lowThroughputAlarm = new cloudwatch.Alarm(this, 'LowThroughputAlarm', {
      alarmName: `AppSignals-LowThroughput-${uniqueSuffix}`,
      alarmDescription: 'Monitor application throughput from Application Signals',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/ApplicationSignals',
        metricName: 'CallCount',
        dimensionsMap: {
          Service: applicationName.valueAsString
        },
        statistic: 'Sum',
        period: cdk.Duration.minutes(5)
      }),
      threshold: throughputThreshold.valueAsNumber,
      comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
      evaluationPeriods: 3,
      datapointsToAlarm: 2,
      treatMissingData: cloudwatch.TreatMissingData.BREACHING
    });

    // Add alarm actions to SNS topic
    highLatencyAlarm.addAlarmAction(new cloudwatch.SnsAction(alertsTopic));
    highLatencyAlarm.addOkAction(new cloudwatch.SnsAction(alertsTopic));
    
    highErrorRateAlarm.addAlarmAction(new cloudwatch.SnsAction(alertsTopic));
    highErrorRateAlarm.addOkAction(new cloudwatch.SnsAction(alertsTopic));
    
    lowThroughputAlarm.addAlarmAction(new cloudwatch.SnsAction(alertsTopic));
    lowThroughputAlarm.addOkAction(new cloudwatch.SnsAction(alertsTopic));

    // Create CloudWatch Dashboard for monitoring
    const performanceDashboard = new cloudwatch.Dashboard(this, 'PerformanceDashboard', {
      dashboardName: `ApplicationPerformanceMonitoring-${uniqueSuffix}`,
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'Application Performance Metrics',
            width: 12,
            height: 6,
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/ApplicationSignals',
                metricName: 'Latency',
                dimensionsMap: { Service: applicationName.valueAsString },
                statistic: 'Average',
                period: cdk.Duration.minutes(5)
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/ApplicationSignals',
                metricName: 'ErrorRate',
                dimensionsMap: { Service: applicationName.valueAsString },
                statistic: 'Average',
                period: cdk.Duration.minutes(5)
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/ApplicationSignals',
                metricName: 'CallCount',
                dimensionsMap: { Service: applicationName.valueAsString },
                statistic: 'Sum',
                period: cdk.Duration.minutes(5)
              })
            ]
          }),
          new cloudwatch.GraphWidget({
            title: 'Event Processing Metrics',
            width: 12,
            height: 6,
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/Events',
                metricName: 'InvocationsCount',
                dimensionsMap: { RuleName: alarmStateChangeRule.ruleName },
                statistic: 'Sum',
                period: cdk.Duration.minutes(5)
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/Lambda',
                metricName: 'Invocations',
                dimensionsMap: { FunctionName: performanceProcessorFunction.functionName },
                statistic: 'Sum',
                period: cdk.Duration.minutes(5)
              })
            ]
          })
        ]
      ]
    });

    // Stack Outputs
    new cdk.CfnOutput(this, 'SNSTopicArn', {
      value: alertsTopic.topicArn,
      description: 'ARN of the SNS topic for performance alerts',
      exportName: `${this.stackName}-SNSTopicArn`
    });

    new cdk.CfnOutput(this, 'LambdaFunctionArn', {
      value: performanceProcessorFunction.functionArn,
      description: 'ARN of the Lambda function for event processing',
      exportName: `${this.stackName}-LambdaFunctionArn`
    });

    new cdk.CfnOutput(this, 'EventBridgeRuleArn', {
      value: alarmStateChangeRule.ruleArn,
      description: 'ARN of the EventBridge rule for alarm processing',
      exportName: `${this.stackName}-EventBridgeRuleArn`
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${performanceDashboard.dashboardName}`,
      description: 'URL to the CloudWatch dashboard for performance monitoring',
      exportName: `${this.stackName}-DashboardUrl`
    });

    new cdk.CfnOutput(this, 'ApplicationSignalsLogGroup', {
      value: applicationSignalsLogGroup.logGroupName,
      description: 'Log group for Application Signals data collection',
      exportName: `${this.stackName}-ApplicationSignalsLogGroup`
    });

    // Add tags to all resources
    cdk.Tags.of(this).add('Project', 'AutomatedPerformanceMonitoring');
    cdk.Tags.of(this).add('Environment', 'Production');
    cdk.Tags.of(this).add('CostCenter', 'IT-Operations');
  }
}

// Create CDK App
const app = new cdk.App();

// Deploy the stack
new AutomatedApplicationPerformanceMonitoringStack(app, 'AutomatedApplicationPerformanceMonitoringStack', {
  description: 'Automated Application Performance Monitoring with CloudWatch Application Signals and EventBridge',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  terminationProtection: false, // Set to true for production deployments
  tags: {
    Project: 'AutomatedPerformanceMonitoring',
    Environment: 'Production',
    ManagedBy: 'AWS-CDK'
  }
});