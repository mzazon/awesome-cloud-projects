import * as cdk from 'aws-cdk-lib';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';

export interface MonitoringStackProps extends cdk.StackProps {
  stackSetName: string;
  managementAccountId: string;
  emailAddress?: string;
}

/**
 * Stack for monitoring and alerting on StackSets operations
 * 
 * This stack creates:
 * - CloudWatch dashboard for StackSets monitoring
 * - SNS topics for alerts
 * - CloudWatch alarms for failed operations
 * - Lambda function for automated drift detection
 * - EventBridge rules for StackSets events
 */
export class MonitoringStack extends cdk.Stack {
  public readonly alertTopic: sns.Topic;
  public readonly dashboard: cloudwatch.Dashboard;
  public readonly driftDetectionFunction: lambda.Function;
  public readonly stackSetAlarms: cloudwatch.Alarm[];

  constructor(scope: Construct, id: string, props: MonitoringStackProps) {
    super(scope, id, props);

    // Create SNS topic for alerts
    this.alertTopic = this.createAlertTopic(props.emailAddress);

    // Create CloudWatch dashboard
    this.dashboard = this.createDashboard(props.stackSetName);

    // Create CloudWatch alarms
    this.stackSetAlarms = this.createStackSetAlarms(props.stackSetName);

    // Create Lambda function for drift detection
    this.driftDetectionFunction = this.createDriftDetectionFunction(props);

    // Create EventBridge rules for StackSets events
    this.createEventBridgeRules(props.stackSetName);

    // Create outputs
    this.createOutputs();
  }

  /**
   * Create SNS topic for alerts
   */
  private createAlertTopic(emailAddress?: string): sns.Topic {
    const topic = new sns.Topic(this, 'StackSetAlertTopic', {
      topicName: `StackSetAlerts-${this.stackName}`,
      displayName: 'StackSet Operations Alerts',
    });

    // Add email subscription if provided
    if (emailAddress) {
      topic.addSubscription(new snsSubscriptions.EmailSubscription(emailAddress));
    }

    // Add policy for CloudWatch alarms
    topic.addToResourcePolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        principals: [new iam.ServicePrincipal('cloudwatch.amazonaws.com')],
        actions: ['sns:Publish'],
        resources: [topic.topicArn],
      })
    );

    cdk.Tags.of(topic).add('Purpose', 'StackSetAlerting');

    return topic;
  }

  /**
   * Create CloudWatch dashboard
   */
  private createDashboard(stackSetName: string): cloudwatch.Dashboard {
    const dashboard = new cloudwatch.Dashboard(this, 'StackSetDashboard', {
      dashboardName: `StackSet-Monitoring-${stackSetName}`,
    });

    // StackSet operation metrics
    const operationSuccessMetric = new cloudwatch.Metric({
      namespace: 'AWS/CloudFormation',
      metricName: 'StackSetOperationSuccessCount',
      dimensionsMap: {
        StackSetName: stackSetName,
      },
      statistic: 'Sum',
      period: cdk.Duration.minutes(5),
    });

    const operationFailureMetric = new cloudwatch.Metric({
      namespace: 'AWS/CloudFormation',
      metricName: 'StackSetOperationFailureCount',
      dimensionsMap: {
        StackSetName: stackSetName,
      },
      statistic: 'Sum',
      period: cdk.Duration.minutes(5),
    });

    // Add widgets to dashboard
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'StackSet Operation Results',
        left: [operationSuccessMetric, operationFailureMetric],
        width: 12,
        height: 6,
        period: cdk.Duration.minutes(5),
      })
    );

    // StackSet drift detection metrics
    const driftDetectionMetric = new cloudwatch.Metric({
      namespace: 'Custom/StackSets',
      metricName: 'DriftDetectionOperations',
      dimensionsMap: {
        StackSetName: stackSetName,
      },
      statistic: 'Sum',
      period: cdk.Duration.minutes(15),
    });

    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Drift Detection Operations',
        left: [driftDetectionMetric],
        width: 12,
        height: 6,
        period: cdk.Duration.minutes(15),
      })
    );

    // Stack instance status
    const stackInstancesMetric = new cloudwatch.Metric({
      namespace: 'Custom/StackSets',
      metricName: 'StackInstancesCount',
      dimensionsMap: {
        StackSetName: stackSetName,
      },
      statistic: 'Average',
      period: cdk.Duration.minutes(30),
    });

    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Stack Instances Count',
        left: [stackInstancesMetric],
        width: 12,
        height: 6,
        period: cdk.Duration.minutes(30),
      })
    );

    // Log insights widget for recent operations
    dashboard.addWidgets(
      new cloudwatch.LogQueryWidget({
        title: 'Recent StackSet Operations',
        logGroups: [
          logs.LogGroup.fromLogGroupName(this, 'StackSetOperationsLogGroup', '/aws/lambda/stackset-drift-detection'),
        ],
        queryLines: [
          'fields @timestamp, @message',
          `filter @message like /StackSet: ${stackSetName}/`,
          'sort @timestamp desc',
          'limit 20',
        ],
        width: 24,
        height: 6,
      })
    );

    cdk.Tags.of(dashboard).add('Purpose', 'StackSetMonitoring');

    return dashboard;
  }

  /**
   * Create CloudWatch alarms for StackSets
   */
  private createStackSetAlarms(stackSetName: string): cloudwatch.Alarm[] {
    const alarms: cloudwatch.Alarm[] = [];

    // Alarm for failed operations
    const failureAlarm = new cloudwatch.Alarm(this, 'StackSetOperationFailureAlarm', {
      alarmName: `StackSetOperationFailure-${stackSetName}`,
      alarmDescription: 'Alert when StackSet operations fail',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/CloudFormation',
        metricName: 'StackSetOperationFailureCount',
        dimensionsMap: {
          StackSetName: stackSetName,
        },
        statistic: 'Sum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    failureAlarm.addAlarmAction(new cloudwatch.SnsAction(this.alertTopic));
    alarms.push(failureAlarm);

    // Alarm for drift detection
    const driftAlarm = new cloudwatch.Alarm(this, 'StackSetDriftDetectedAlarm', {
      alarmName: `StackSetDriftDetected-${stackSetName}`,
      alarmDescription: 'Alert when StackSet drift is detected',
      metric: new cloudwatch.Metric({
        namespace: 'Custom/StackSets',
        metricName: 'DriftDetected',
        dimensionsMap: {
          StackSetName: stackSetName,
        },
        statistic: 'Sum',
        period: cdk.Duration.minutes(15),
      }),
      threshold: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    driftAlarm.addAlarmAction(new cloudwatch.SnsAction(this.alertTopic));
    alarms.push(driftAlarm);

    // Alarm for high failure rate
    const highFailureRateAlarm = new cloudwatch.Alarm(this, 'StackSetHighFailureRateAlarm', {
      alarmName: `StackSetHighFailureRate-${stackSetName}`,
      alarmDescription: 'Alert when StackSet failure rate is high',
      metric: new cloudwatch.MathExpression({
        expression: 'failures / (successes + failures) * 100',
        usingMetrics: {
          failures: new cloudwatch.Metric({
            namespace: 'AWS/CloudFormation',
            metricName: 'StackSetOperationFailureCount',
            dimensionsMap: {
              StackSetName: stackSetName,
            },
            statistic: 'Sum',
            period: cdk.Duration.minutes(30),
          }),
          successes: new cloudwatch.Metric({
            namespace: 'AWS/CloudFormation',
            metricName: 'StackSetOperationSuccessCount',
            dimensionsMap: {
              StackSetName: stackSetName,
            },
            statistic: 'Sum',
            period: cdk.Duration.minutes(30),
          }),
        },
        period: cdk.Duration.minutes(30),
      }),
      threshold: 10, // 10% failure rate
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    highFailureRateAlarm.addAlarmAction(new cloudwatch.SnsAction(this.alertTopic));
    alarms.push(highFailureRateAlarm);

    return alarms;
  }

  /**
   * Create Lambda function for automated drift detection
   */
  private createDriftDetectionFunction(props: MonitoringStackProps): lambda.Function {
    // Create IAM role for Lambda
    const lambdaRole = new iam.Role(this, 'DriftDetectionLambdaRole', {
      roleName: 'StackSetDriftDetectionRole',
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'Role for StackSet drift detection Lambda function',
    });

    // Add basic Lambda execution policy
    lambdaRole.addManagedPolicy(
      iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
    );

    // Add StackSet permissions
    lambdaRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'cloudformation:DetectStackSetDrift',
          'cloudformation:DescribeStackSetOperation',
          'cloudformation:ListStackInstances',
          'cloudformation:DescribeStackInstance',
          'cloudformation:DescribeStackSet',
        ],
        resources: ['*'],
      })
    );

    // Add SNS permissions
    lambdaRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: ['sns:Publish'],
        resources: [this.alertTopic.topicArn],
      })
    );

    // Add CloudWatch permissions
    lambdaRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'cloudwatch:PutMetricData',
          'logs:CreateLogGroup',
          'logs:CreateLogStream',
          'logs:PutLogEvents',
        ],
        resources: ['*'],
      })
    );

    // Create Lambda function
    const driftDetectionFunction = new lambda.Function(this, 'DriftDetectionFunction', {
      functionName: `stackset-drift-detection-${props.stackSetName}`,
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import boto3
import json
import logging
import os
from datetime import datetime
from typing import Dict, Any, List

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
cf_client = boto3.client('cloudformation')
sns_client = boto3.client('sns')
cloudwatch_client = boto3.client('cloudwatch')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda function to detect and report StackSet drift
    """
    try:
        # Get configuration from environment variables
        stackset_name = os.environ.get('STACKSET_NAME', '${props.stackSetName}')
        sns_topic_arn = os.environ.get('SNS_TOPIC_ARN', '${this.alertTopic.topicArn}')
        
        logger.info(f"Starting drift detection for StackSet: {stackset_name}")
        
        # Get StackSet information
        stackset_info = cf_client.describe_stack_set(StackSetName=stackset_name)
        
        # Initiate drift detection
        response = cf_client.detect_stack_set_drift(StackSetName=stackset_name)
        operation_id = response['OperationId']
        
        logger.info(f"Drift detection initiated with operation ID: {operation_id}")
        
        # Wait for operation to complete (with timeout)
        waiter = cf_client.get_waiter('stack_set_operation_complete')
        try:
            waiter.wait(
                StackSetName=stackset_name,
                OperationId=operation_id,
                WaiterConfig={'Delay': 30, 'MaxAttempts': 20}
            )
        except Exception as e:
            logger.warning(f"Waiter timed out or failed: {str(e)}")
            # Continue with current status
        
        # Get drift detection results
        drift_results = cf_client.describe_stack_set_operation(
            StackSetName=stackset_name,
            OperationId=operation_id
        )
        
        # Get stack instances
        stack_instances = cf_client.list_stack_instances(StackSetName=stackset_name)
        
        # Analyze drift status
        drifted_instances = []
        total_instances = len(stack_instances['Summaries'])
        
        for instance in stack_instances['Summaries']:
            if instance.get('DriftStatus') == 'DRIFTED':
                drifted_instances.append({
                    'Account': instance['Account'],
                    'Region': instance['Region'],
                    'DriftStatus': instance['DriftStatus'],
                    'StatusReason': instance.get('StatusReason', 'No reason provided')
                })
        
        drifted_count = len(drifted_instances)
        
        # Generate report
        report = {
            'timestamp': datetime.utcnow().isoformat(),
            'stackset_name': stackset_name,
            'operation_id': operation_id,
            'total_instances': total_instances,
            'drifted_instances': drifted_count,
            'drift_detected': drifted_count > 0,
            'drifted_details': drifted_instances,
            'operation_status': drift_results['Operation']['Status']
        }
        
        logger.info(f"Drift detection complete. Found {drifted_count} drifted instances out of {total_instances}")
        
        # Send CloudWatch metrics
        send_cloudwatch_metrics(stackset_name, total_instances, drifted_count)
        
        # Send notification if drift detected
        if drifted_instances:
            send_drift_notification(sns_topic_arn, stackset_name, report)
        
        return {
            'statusCode': 200,
            'body': json.dumps(report, indent=2)
        }
        
    except Exception as e:
        logger.error(f"Error in drift detection: {str(e)}")
        
        # Send error notification
        error_report = {
            'timestamp': datetime.utcnow().isoformat(),
            'stackset_name': stackset_name,
            'error': str(e),
            'status': 'ERROR'
        }
        
        if sns_topic_arn:
            try:
                sns_client.publish(
                    TopicArn=sns_topic_arn,
                    Subject=f'StackSet Drift Detection Error: {stackset_name}',
                    Message=json.dumps(error_report, indent=2)
                )
            except Exception as sns_error:
                logger.error(f"Failed to send error notification: {str(sns_error)}")
        
        return {
            'statusCode': 500,
            'body': json.dumps(error_report, indent=2)
        }

def send_cloudwatch_metrics(stackset_name: str, total_instances: int, drifted_count: int):
    """Send custom metrics to CloudWatch"""
    try:
        cloudwatch_client.put_metric_data(
            Namespace='Custom/StackSets',
            MetricData=[
                {
                    'MetricName': 'StackInstancesCount',
                    'Dimensions': [
                        {
                            'Name': 'StackSetName',
                            'Value': stackset_name
                        }
                    ],
                    'Value': total_instances,
                    'Unit': 'Count'
                },
                {
                    'MetricName': 'DriftDetectionOperations',
                    'Dimensions': [
                        {
                            'Name': 'StackSetName',
                            'Value': stackset_name
                        }
                    ],
                    'Value': 1,
                    'Unit': 'Count'
                }
            ]
        )
        
        if drifted_count > 0:
            cloudwatch_client.put_metric_data(
                Namespace='Custom/StackSets',
                MetricData=[
                    {
                        'MetricName': 'DriftDetected',
                        'Dimensions': [
                            {
                                'Name': 'StackSetName',
                                'Value': stackset_name
                            }
                        ],
                        'Value': drifted_count,
                        'Unit': 'Count'
                    }
                ]
            )
    except Exception as e:
        logger.error(f"Failed to send CloudWatch metrics: {str(e)}")

def send_drift_notification(sns_topic_arn: str, stackset_name: str, report: Dict[str, Any]):
    """Send drift detection notification"""
    try:
        message = f"""
StackSet Drift Detected

StackSet: {stackset_name}
Total Instances: {report['total_instances']}
Drifted Instances: {report['drifted_instances']}

Drifted Instance Details:
{json.dumps(report['drifted_details'], indent=2)}

Operation ID: {report['operation_id']}
Timestamp: {report['timestamp']}

Please review and remediate the drifted instances.
"""
        
        sns_client.publish(
            TopicArn=sns_topic_arn,
            Subject=f'StackSet Drift Alert: {stackset_name}',
            Message=message
        )
    except Exception as e:
        logger.error(f"Failed to send drift notification: {str(e)}")
`),
      role: lambdaRole,
      timeout: cdk.Duration.minutes(15),
      environment: {
        STACKSET_NAME: props.stackSetName,
        SNS_TOPIC_ARN: this.alertTopic.topicArn,
      },
      description: 'Automated drift detection for StackSets',
    });

    // Create log group with retention
    new logs.LogGroup(this, 'DriftDetectionLogGroup', {
      logGroupName: `/aws/lambda/${driftDetectionFunction.functionName}`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    cdk.Tags.of(driftDetectionFunction).add('Purpose', 'StackSetDriftDetection');

    return driftDetectionFunction;
  }

  /**
   * Create EventBridge rules for StackSets events
   */
  private createEventBridgeRules(stackSetName: string): void {
    // Rule for StackSet operation state changes
    const stackSetOperationRule = new events.Rule(this, 'StackSetOperationRule', {
      ruleName: `StackSetOperations-${stackSetName}`,
      description: 'Captures StackSet operation state changes',
      eventPattern: {
        source: ['aws.cloudformation'],
        detailType: ['CloudFormation Stack Set Operation Status Change'],
        detail: {
          stackSetName: [stackSetName],
          operationStatus: ['SUCCEEDED', 'FAILED', 'STOPPED'],
        },
      },
    });

    // Add SNS target for operation events
    stackSetOperationRule.addTarget(
      new targets.SnsTopic(this.alertTopic, {
        message: events.RuleTargetInput.fromText(
          `StackSet Operation Status Change:
StackSet: ${stackSetName}
Operation: ${events.EventField.fromPath('$.detail.operationType')}
Status: ${events.EventField.fromPath('$.detail.operationStatus')}
Time: ${events.EventField.fromPath('$.time')}
Region: ${events.EventField.fromPath('$.region')}
Account: ${events.EventField.fromPath('$.account')}`
        ),
      })
    );

    // Schedule drift detection to run daily
    const driftDetectionSchedule = new events.Rule(this, 'DriftDetectionSchedule', {
      ruleName: `DriftDetectionSchedule-${stackSetName}`,
      description: 'Schedule for automated drift detection',
      schedule: events.Schedule.cron({
        minute: '0',
        hour: '9', // Run at 9 AM UTC daily
        day: '*',
        month: '*',
        year: '*',
      }),
    });

    // Add Lambda target for scheduled drift detection
    driftDetectionSchedule.addTarget(
      new targets.LambdaFunction(this.driftDetectionFunction, {
        event: events.RuleTargetInput.fromObject({
          source: 'scheduled-drift-detection',
          stackSetName: stackSetName,
        }),
      })
    );

    cdk.Tags.of(stackSetOperationRule).add('Purpose', 'StackSetEventMonitoring');
    cdk.Tags.of(driftDetectionSchedule).add('Purpose', 'StackSetDriftDetection');
  }

  /**
   * Create stack outputs
   */
  private createOutputs(): void {
    new cdk.CfnOutput(this, 'AlertTopicArn', {
      description: 'ARN of the SNS topic for alerts',
      value: this.alertTopic.topicArn,
      exportName: `${this.stackName}-AlertTopicArn`,
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      description: 'URL of the CloudWatch dashboard',
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${this.dashboard.dashboardName}`,
      exportName: `${this.stackName}-DashboardUrl`,
    });

    new cdk.CfnOutput(this, 'DriftDetectionFunctionArn', {
      description: 'ARN of the drift detection Lambda function',
      value: this.driftDetectionFunction.functionArn,
      exportName: `${this.stackName}-DriftDetectionFunctionArn`,
    });

    new cdk.CfnOutput(this, 'DriftDetectionFunctionName', {
      description: 'Name of the drift detection Lambda function',
      value: this.driftDetectionFunction.functionName,
      exportName: `${this.stackName}-DriftDetectionFunctionName`,
    });

    new cdk.CfnOutput(this, 'AlarmNames', {
      description: 'Names of the CloudWatch alarms',
      value: this.stackSetAlarms.map(alarm => alarm.alarmName).join(', '),
      exportName: `${this.stackName}-AlarmNames`,
    });
  }
}