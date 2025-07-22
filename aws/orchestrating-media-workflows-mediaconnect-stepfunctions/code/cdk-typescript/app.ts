#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as stepfunctions from 'aws-cdk-lib/aws-stepfunctions';
import * as stepfunctionsTasks from 'aws-cdk-lib/aws-stepfunctions-tasks';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as cloudwatchActions from 'aws-cdk-lib/aws-cloudwatch-actions';
import * as events from 'aws-cdk-lib/aws-events';
import * as eventsTargets from 'aws-cdk-lib/aws-events-targets';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3 from 'aws-cdk-lib/aws-s3';
import { Construct } from 'constructs';

/**
 * Interface for MediaWorkflowStack properties
 */
interface MediaWorkflowStackProps extends cdk.StackProps {
  /** Flow name for MediaConnect flow */
  readonly flowName?: string;
  /** Email address for SNS notifications */
  readonly notificationEmail?: string;
  /** Source IP whitelist for MediaConnect flow */
  readonly sourceWhitelistCidr?: string;
  /** Primary output destination IP */
  readonly primaryOutputDestination?: string;
  /** Backup output destination IP */
  readonly backupOutputDestination?: string;
  /** Packet loss threshold percentage (default: 0.1) */
  readonly packetLossThreshold?: number;
  /** Jitter threshold in milliseconds (default: 50) */
  readonly jitterThreshold?: number;
}

/**
 * AWS CDK Stack for orchestrating real-time media workflows with 
 * AWS Elemental MediaConnect and Step Functions
 * 
 * This stack creates:
 * - MediaConnect flow for reliable video transport
 * - Step Functions state machine for workflow orchestration
 * - Lambda functions for stream monitoring and alerting
 * - CloudWatch alarms and dashboard for monitoring
 * - SNS topic for notifications
 * - EventBridge rules for automated workflow execution
 */
export class MediaWorkflowStack extends cdk.Stack {
  public readonly flowArn: string;
  public readonly stateMachineArn: string;
  public readonly snsTopicArn: string;

  constructor(scope: Construct, id: string, props: MediaWorkflowStackProps = {}) {
    super(scope, id, props);

    // Extract properties with defaults
    const flowName = props.flowName || `live-stream-${this.generateRandomSuffix()}`;
    const notificationEmail = props.notificationEmail || 'your-email@example.com';
    const sourceWhitelistCidr = props.sourceWhitelistCidr || '0.0.0.0/0';
    const primaryOutputDestination = props.primaryOutputDestination || '10.0.0.100';
    const backupOutputDestination = props.backupOutputDestination || '10.0.0.101';
    const packetLossThreshold = props.packetLossThreshold || 0.1;
    const jitterThreshold = props.jitterThreshold || 50;

    // Create S3 bucket for Lambda deployment packages
    const lambdaBucket = new s3.Bucket(this, 'LambdaCodeBucket', {
      bucketName: `lambda-code-${this.generateRandomSuffix()}`,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      lifecycleRules: [{
        id: 'CleanupOldVersions',
        expiration: cdk.Duration.days(30),
      }],
    });

    // Create SNS Topic for media alerts
    const alertsTopic = new sns.Topic(this, 'MediaAlertsTopic', {
      topicName: `media-alerts-${this.generateRandomSuffix()}`,
      displayName: 'Media Workflow Alerts',
    });

    // Add email subscription to SNS topic
    alertsTopic.addSubscription(
      new snsSubscriptions.EmailSubscription(notificationEmail)
    );

    // Create IAM role for Lambda functions
    const lambdaRole = new iam.Role(this, 'MediaLambdaRole', {
      roleName: `media-lambda-role-${this.generateRandomSuffix()}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        MediaConnectAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'mediaconnect:DescribeFlow',
                'mediaconnect:ListFlows',
                'cloudwatch:GetMetricStatistics',
                'cloudwatch:GetMetricData',
                'sns:Publish',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // Create stream monitor Lambda function
    const streamMonitorFunction = new lambda.Function(this, 'StreamMonitorFunction', {
      functionName: `stream-monitor-${this.generateRandomSuffix()}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'stream-monitor.lambda_handler',
      code: lambda.Code.fromInline(this.getStreamMonitorCode()),
      timeout: cdk.Duration.seconds(60),
      memorySize: 256,
      role: lambdaRole,
      environment: {
        SNS_TOPIC_ARN: alertsTopic.topicArn,
        PACKET_LOSS_THRESHOLD: packetLossThreshold.toString(),
        JITTER_THRESHOLD: jitterThreshold.toString(),
      },
      description: 'Monitors MediaConnect flow health metrics and detects quality issues',
    });

    // Create alert handler Lambda function
    const alertHandlerFunction = new lambda.Function(this, 'AlertHandlerFunction', {
      functionName: `alert-handler-${this.generateRandomSuffix()}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'alert-handler.lambda_handler',
      code: lambda.Code.fromInline(this.getAlertHandlerCode()),
      timeout: cdk.Duration.seconds(30),
      memorySize: 128,
      role: lambdaRole,
      environment: {
        SNS_TOPIC_ARN: alertsTopic.topicArn,
      },
      description: 'Formats and sends notifications for MediaConnect flow issues',
    });

    // Grant SNS publish permissions to Lambda functions
    alertsTopic.grantPublish(streamMonitorFunction);
    alertsTopic.grantPublish(alertHandlerFunction);

    // Create IAM role for Step Functions
    const stepFunctionsRole = new iam.Role(this, 'MediaStepFunctionsRole', {
      roleName: `media-sf-role-${this.generateRandomSuffix()}`,
      assumedBy: new iam.ServicePrincipal('states.amazonaws.com'),
      inlinePolicies: {
        StepFunctionsExecutionPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'lambda:InvokeFunction',
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // Create Step Functions state machine
    const monitorStreamTask = new stepfunctionsTasks.LambdaInvoke(this, 'MonitorStreamTask', {
      lambdaFunction: streamMonitorFunction,
      payloadResponseOnly: true,
      resultPath: '$.monitoring_result',
    });

    const sendAlertTask = new stepfunctionsTasks.LambdaInvoke(this, 'SendAlertTask', {
      lambdaFunction: alertHandlerFunction,
      payloadResponseOnly: true,
    });

    const healthyFlowPass = new stepfunctions.Pass(this, 'HealthyFlow', {
      result: stepfunctions.Result.fromString('Flow is healthy - no action required'),
    });

    // Define the workflow
    const definition = monitorStreamTask
      .next(
        new stepfunctions.Choice(this, 'EvaluateHealth')
          .when(
            stepfunctions.Condition.booleanEquals('$.monitoring_result.healthy', false),
            sendAlertTask
          )
          .otherwise(healthyFlowPass)
      );

    const stateMachine = new stepfunctions.StateMachine(this, 'MediaWorkflowStateMachine', {
      stateMachineName: `media-workflow-${this.generateRandomSuffix()}`,
      stateMachineType: stepfunctions.StateMachineType.EXPRESS,
      definition,
      role: stepFunctionsRole,
      logs: {
        destination: new cdk.aws_logs.LogGroup(this, 'StateMachineLogGroup', {
          logGroupName: `/aws/stepfunctions/media-workflow-${this.generateRandomSuffix()}`,
          removalPolicy: cdk.RemovalPolicy.DESTROY,
        }),
        level: stepfunctions.LogLevel.ERROR,
        includeExecutionData: false,
      },
    });

    // Create MediaConnect flow using custom resource (L1 construct)
    const mediaConnectFlow = new cdk.CfnResource(this, 'MediaConnectFlow', {
      type: 'AWS::MediaConnect::Flow',
      properties: {
        Name: flowName,
        AvailabilityZone: `${this.region}a`,
        Source: {
          Name: 'PrimarySource',
          Description: 'Primary live stream source',
          Protocol: 'rtp',
          WhitelistCidr: sourceWhitelistCidr,
          IngestPort: 5000,
        },
        Outputs: [
          {
            Name: 'PrimaryOutput',
            Description: 'Primary stream output',
            Protocol: 'rtp',
            Destination: primaryOutputDestination,
            Port: 5001,
          },
          {
            Name: 'BackupOutput',
            Description: 'Backup stream output',
            Protocol: 'rtp',
            Destination: backupOutputDestination,
            Port: 5002,
          },
        ],
      },
    });

    // Create CloudWatch alarms for stream health monitoring
    const packetLossAlarm = new cloudwatch.Alarm(this, 'PacketLossAlarm', {
      alarmName: `${flowName}-packet-loss`,
      alarmDescription: 'Triggers when packet loss exceeds threshold',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/MediaConnect',
        metricName: 'SourcePacketLossPercent',
        dimensionsMap: {
          FlowARN: mediaConnectFlow.ref,
        },
        statistic: 'Maximum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: packetLossThreshold,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      datapointsToAlarm: 1,
      evaluationPeriods: 1,
    });

    const jitterAlarm = new cloudwatch.Alarm(this, 'JitterAlarm', {
      alarmName: `${flowName}-jitter`,
      alarmDescription: 'Triggers when jitter exceeds threshold',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/MediaConnect',
        metricName: 'SourceJitter',
        dimensionsMap: {
          FlowARN: mediaConnectFlow.ref,
        },
        statistic: 'Maximum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: jitterThreshold,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      datapointsToAlarm: 2,
      evaluationPeriods: 2,
    });

    const workflowTriggerAlarm = new cloudwatch.Alarm(this, 'WorkflowTriggerAlarm', {
      alarmName: `${flowName}-workflow-trigger`,
      alarmDescription: 'Triggers media monitoring workflow',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/MediaConnect',
        metricName: 'SourcePacketLossPercent',
        dimensionsMap: {
          FlowARN: mediaConnectFlow.ref,
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(1),
      }),
      threshold: 0.05,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      datapointsToAlarm: 1,
      evaluationPeriods: 1,
    });

    // Add SNS notification actions to alarms
    packetLossAlarm.addAlarmAction(new cloudwatchActions.SnsAction(alertsTopic));
    jitterAlarm.addAlarmAction(new cloudwatchActions.SnsAction(alertsTopic));

    // Create EventBridge rule for automated workflow execution
    const alarmRule = new events.Rule(this, 'AlarmRule', {
      ruleName: `${flowName}-alarm-rule`,
      description: 'Triggers workflow on MediaConnect alarm',
      eventPattern: {
        source: ['aws.cloudwatch'],
        detailType: ['CloudWatch Alarm State Change'],
        detail: {
          alarmName: [workflowTriggerAlarm.alarmName],
          state: {
            value: ['ALARM'],
          },
        },
      },
    });

    // Add Step Functions as target for EventBridge rule
    alarmRule.addTarget(
      new eventsTargets.SfnStateMachine(stateMachine, {
        input: events.RuleTargetInput.fromObject({
          flow_arn: mediaConnectFlow.ref,
        }),
      })
    );

    // Create CloudWatch Dashboard for visualization
    const dashboard = new cloudwatch.Dashboard(this, 'MediaDashboard', {
      dashboardName: `${flowName}-monitoring`,
    });

    // Add widgets to dashboard
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Stream Health Metrics',
        width: 12,
        height: 6,
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/MediaConnect',
            metricName: 'SourcePacketLossPercent',
            dimensionsMap: {
              FlowARN: mediaConnectFlow.ref,
            },
            statistic: 'Maximum',
            period: cdk.Duration.minutes(5),
          }),
        ],
        right: [
          new cloudwatch.Metric({
            namespace: 'AWS/MediaConnect',
            metricName: 'SourceJitter',
            dimensionsMap: {
              FlowARN: mediaConnectFlow.ref,
            },
            statistic: 'Average',
            period: cdk.Duration.minutes(5),
          }),
        ],
      }),
      new cloudwatch.GraphWidget({
        title: 'Stream Performance',
        width: 12,
        height: 6,
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/MediaConnect',
            metricName: 'SourceBitrate',
            dimensionsMap: {
              FlowARN: mediaConnectFlow.ref,
            },
            statistic: 'Average',
            period: cdk.Duration.minutes(5),
          }),
        ],
        right: [
          new cloudwatch.Metric({
            namespace: 'AWS/MediaConnect',
            metricName: 'SourceUptime',
            dimensionsMap: {
              FlowARN: mediaConnectFlow.ref,
            },
            statistic: 'Maximum',
            period: cdk.Duration.minutes(5),
          }),
        ],
      })
    );

    // Set output properties
    this.flowArn = mediaConnectFlow.ref;
    this.stateMachineArn = stateMachine.stateMachineArn;
    this.snsTopicArn = alertsTopic.topicArn;

    // Create CloudFormation outputs
    new cdk.CfnOutput(this, 'MediaConnectFlowArn', {
      description: 'ARN of the MediaConnect flow',
      value: this.flowArn,
      exportName: `${this.stackName}-FlowArn`,
    });

    new cdk.CfnOutput(this, 'StepFunctionsStateMachineArn', {
      description: 'ARN of the Step Functions state machine',
      value: this.stateMachineArn,
      exportName: `${this.stackName}-StateMachineArn`,
    });

    new cdk.CfnOutput(this, 'SNSTopicArn', {
      description: 'ARN of the SNS topic for alerts',
      value: this.snsTopicArn,
      exportName: `${this.stackName}-SNSTopicArn`,
    });

    new cdk.CfnOutput(this, 'DashboardURL', {
      description: 'URL of the CloudWatch dashboard',
      value: `https://console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${flowName}-monitoring`,
    });

    new cdk.CfnOutput(this, 'StreamMonitorLambdaArn', {
      description: 'ARN of the stream monitor Lambda function',
      value: streamMonitorFunction.functionArn,
    });

    new cdk.CfnOutput(this, 'AlertHandlerLambdaArn', {
      description: 'ARN of the alert handler Lambda function',
      value: alertHandlerFunction.functionArn,
    });

    // Add tags to all resources
    cdk.Tags.of(this).add('Environment', 'Production');
    cdk.Tags.of(this).add('Purpose', 'MediaWorkflow');
    cdk.Tags.of(this).add('Application', 'MediaConnect-StepFunctions');
  }

  /**
   * Generate a random suffix for resource names
   */
  private generateRandomSuffix(): string {
    return Math.random().toString(36).substring(2, 8);
  }

  /**
   * Get the Python code for the stream monitor Lambda function
   */
  private getStreamMonitorCode(): string {
    return `
import json
import boto3
import os
from datetime import datetime, timedelta

cloudwatch = boto3.client('cloudwatch')
mediaconnect = boto3.client('mediaconnect')

def lambda_handler(event, context):
    try:
        flow_arn = event['flow_arn']
        packet_loss_threshold = float(os.environ.get('PACKET_LOSS_THRESHOLD', '0.1'))
        jitter_threshold = float(os.environ.get('JITTER_THRESHOLD', '50'))
        
        # Get flow details
        flow = mediaconnect.describe_flow(FlowArn=flow_arn)
        flow_name = flow['Flow']['Name']
        
        # Query CloudWatch metrics for the last 5 minutes
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(minutes=5)
        
        # Check source packet loss
        response = cloudwatch.get_metric_statistics(
            Namespace='AWS/MediaConnect',
            MetricName='SourcePacketLossPercent',
            Dimensions=[
                {'Name': 'FlowARN', 'Value': flow_arn}
            ],
            StartTime=start_time,
            EndTime=end_time,
            Period=300,
            Statistics=['Average', 'Maximum']
        )
        
        # Analyze metrics
        issues = []
        if response['Datapoints']:
            latest = sorted(response['Datapoints'], 
                           key=lambda x: x['Timestamp'])[-1]
            if latest['Maximum'] > packet_loss_threshold:
                issues.append({
                    'metric': 'PacketLoss',
                    'value': latest['Maximum'],
                    'threshold': packet_loss_threshold,
                    'severity': 'HIGH'
                })
        
        # Check source jitter
        jitter_response = cloudwatch.get_metric_statistics(
            Namespace='AWS/MediaConnect',
            MetricName='SourceJitter',
            Dimensions=[
                {'Name': 'FlowARN', 'Value': flow_arn}
            ],
            StartTime=start_time,
            EndTime=end_time,
            Period=300,
            Statistics=['Average', 'Maximum']
        )
        
        if jitter_response['Datapoints']:
            latest_jitter = sorted(jitter_response['Datapoints'], 
                                 key=lambda x: x['Timestamp'])[-1]
            if latest_jitter['Maximum'] > jitter_threshold:
                issues.append({
                    'metric': 'Jitter',
                    'value': latest_jitter['Maximum'],
                    'threshold': jitter_threshold,
                    'severity': 'MEDIUM'
                })
        
        return {
            'statusCode': 200,
            'flow_name': flow_name,
            'flow_arn': flow_arn,
            'timestamp': end_time.isoformat(),
            'issues': issues,
            'healthy': len(issues) == 0
        }
        
    except Exception as e:
        print(f"Error monitoring stream: {str(e)}")
        return {
            'statusCode': 500,
            'error': str(e),
            'healthy': False
        }
`;
  }

  /**
   * Get the Python code for the alert handler Lambda function
   */
  private getAlertHandlerCode(): string {
    return `
import json
import boto3
import os

sns = boto3.client('sns')

def lambda_handler(event, context):
    try:
        sns_topic_arn = os.environ.get('SNS_TOPIC_ARN')
        
        # Extract monitoring results
        monitoring_result = event
        
        if not monitoring_result.get('healthy', True):
            # Construct alert message
            subject = f"MediaConnect Alert: {monitoring_result.get('flow_name', 'Unknown Flow')}"
            
            message_lines = [
                f"Flow: {monitoring_result.get('flow_name', 'Unknown')}",
                f"Time: {monitoring_result.get('timestamp', 'Unknown')}",
                f"Status: UNHEALTHY",
                "",
                "Issues Detected:"
            ]
            
            for issue in monitoring_result.get('issues', []):
                message_lines.append(
                    f"- {issue['metric']}: {issue['value']:.2f} "
                    f"(threshold: {issue['threshold']}) "
                    f"[{issue['severity']}]"
                )
            
            message_lines.extend([
                "",
                "Recommended Actions:",
                "1. Check source encoder stability",
                "2. Verify network connectivity",
                "3. Review CloudWatch dashboard for detailed metrics",
                f"4. Access flow in console: https://console.aws.amazon.com/mediaconnect/home?region={context.invoked_function_arn.split(':')[3]}#/flows"
            ])
            
            message = "\\n".join(message_lines)
            
            # Send SNS notification
            response = sns.publish(
                TopicArn=sns_topic_arn,
                Subject=subject,
                Message=message
            )
            
            return {
                'statusCode': 200,
                'notification_sent': True,
                'message_id': response['MessageId']
            }
        
        return {
            'statusCode': 200,
            'notification_sent': False,
            'reason': 'Flow is healthy'
        }
        
    except Exception as e:
        print(f"Error handling alert: {str(e)}")
        return {
            'statusCode': 500,
            'error': str(e),
            'notification_sent': False
        }
`;
  }
}

/**
 * CDK Application entry point
 */
const app = new cdk.App();

// Get configuration from context or environment variables
const config = {
  flowName: app.node.tryGetContext('flowName') || process.env.FLOW_NAME,
  notificationEmail: app.node.tryGetContext('notificationEmail') || process.env.NOTIFICATION_EMAIL || 'your-email@example.com',
  sourceWhitelistCidr: app.node.tryGetContext('sourceWhitelistCidr') || process.env.SOURCE_WHITELIST_CIDR || '0.0.0.0/0',
  primaryOutputDestination: app.node.tryGetContext('primaryOutputDestination') || process.env.PRIMARY_OUTPUT_DESTINATION || '10.0.0.100',
  backupOutputDestination: app.node.tryGetContext('backupOutputDestination') || process.env.BACKUP_OUTPUT_DESTINATION || '10.0.0.101',
  packetLossThreshold: parseFloat(app.node.tryGetContext('packetLossThreshold') || process.env.PACKET_LOSS_THRESHOLD || '0.1'),
  jitterThreshold: parseFloat(app.node.tryGetContext('jitterThreshold') || process.env.JITTER_THRESHOLD || '50'),
};

// Create the media workflow stack
new MediaWorkflowStack(app, 'MediaWorkflowStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'us-east-1',
  },
  ...config,
  description: 'Media workflow stack for Orchestrating Media Workflows with MediaConnect and Step Functions',
  tags: {
    Application: 'MediaWorkflow',
    Environment: 'Production',
    Purpose: 'MediaStreaming',
  },
});

// Synthesize the CDK app
app.synth();