#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as cloudwatchActions from 'aws-cdk-lib/aws-cloudwatch-actions';
import { Duration, RemovalPolicy } from 'aws-cdk-lib';

/**
 * Properties for the AgentCore Performance Monitoring Stack
 */
export interface AgentCoreMonitoringStackProps extends cdk.StackProps {
  /**
   * Name of the AgentCore agent to monitor
   * @default 'ai-agent-default'
   */
  readonly agentName?: string;

  /**
   * Retention period for CloudWatch logs in days
   * @default 30
   */
  readonly logRetentionDays?: logs.RetentionDays;

  /**
   * High latency threshold in milliseconds for alerting
   * @default 30000
   */
  readonly highLatencyThreshold?: number;

  /**
   * System error threshold for alerting
   * @default 5
   */
  readonly systemErrorThreshold?: number;

  /**
   * Throttle threshold for alerting
   * @default 10
   */
  readonly throttleThreshold?: number;
}

/**
 * CDK Stack for AWS Bedrock AgentCore Performance Monitoring with CloudWatch
 * 
 * This stack creates comprehensive monitoring infrastructure for AI agents including:
 * - CloudWatch log groups with structured logging
 * - Performance monitoring Lambda function
 * - CloudWatch dashboards for visualization
 * - Automated alerting with CloudWatch alarms
 * - S3 storage for performance reports
 * - Custom metrics collection and analysis
 */
export class AgentCorePerformanceMonitoringStack extends cdk.Stack {
  public readonly monitoringBucket: s3.Bucket;
  public readonly performanceMonitorFunction: lambda.Function;
  public readonly agentLogGroup: logs.LogGroup;
  public readonly dashboard: cloudwatch.Dashboard;

  constructor(scope: Construct, id: string, props: AgentCoreMonitoringStackProps = {}) {
    super(scope, id, props);

    // Extract configuration from props with defaults
    const agentName = props.agentName ?? 'ai-agent-default';
    const logRetentionDays = props.logRetentionDays ?? logs.RetentionDays.ONE_MONTH;
    const highLatencyThreshold = props.highLatencyThreshold ?? 30000;
    const systemErrorThreshold = props.systemErrorThreshold ?? 5;
    const throttleThreshold = props.throttleThreshold ?? 10;

    // Generate unique suffix for resource naming
    const uniqueSuffix = this.node.addr.substring(0, 6);

    // Create S3 bucket for storing performance monitoring data
    this.monitoringBucket = new s3.Bucket(this, 'MonitoringDataBucket', {
      bucketName: `agent-monitoring-data-${uniqueSuffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      lifecycleRules: [
        {
          id: 'PerformanceReportsLifecycle',
          enabled: true,
          expiration: Duration.days(90),
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: Duration.days(30),
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: Duration.days(60),
            },
          ],
        },
      ],
    });

    // Create IAM role for AgentCore with observability permissions
    const agentCoreRole = new iam.Role(this, 'AgentCoreMonitoringRole', {
      roleName: `AgentCoreMonitoringRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('bedrock.amazonaws.com'),
      description: 'IAM role for AgentCore to emit observability data to CloudWatch',
      inlinePolicies: {
        AgentCoreObservabilityPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents',
                'logs:DescribeLogGroups',
                'logs:DescribeLogStreams',
              ],
              resources: [
                `arn:aws:logs:${this.region}:${this.account}:log-group:/aws/bedrock/agentcore/*`,
              ],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['cloudwatch:PutMetricData'],
              resources: ['*'],
              conditions: {
                StringEquals: {
                  'cloudwatch:namespace': 'AWS/BedrockAgentCore',
                },
              },
            }),
          ],
        }),
      },
    });

    // Create CloudWatch log groups for comprehensive observability
    this.agentLogGroup = new logs.LogGroup(this, 'AgentLogGroup', {
      logGroupName: `/aws/bedrock/agentcore/${agentName}`,
      retention: logRetentionDays,
      removalPolicy: RemovalPolicy.DESTROY,
    });

    const memoryLogGroup = new logs.LogGroup(this, 'MemoryLogGroup', {
      logGroupName: `/aws/bedrock/agentcore/memory/${agentName}`,
      retention: logRetentionDays,
      removalPolicy: RemovalPolicy.DESTROY,
    });

    const gatewayLogGroup = new logs.LogGroup(this, 'GatewayLogGroup', {
      logGroupName: `/aws/bedrock/agentcore/gateway/${agentName}`,
      retention: logRetentionDays,
      removalPolicy: RemovalPolicy.DESTROY,
    });

    // Create Lambda function for performance monitoring and optimization
    this.performanceMonitorFunction = new lambda.Function(this, 'PerformanceMonitorFunction', {
      functionName: `agent-performance-optimizer-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_12,
      handler: 'index.lambda_handler',
      timeout: Duration.seconds(60),
      memorySize: 256,
      environment: {
        AGENT_NAME: agentName,
        S3_BUCKET_NAME: this.monitoringBucket.bucketName,
        LOG_GROUP_NAME: this.agentLogGroup.logGroupName,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from datetime import datetime, timedelta

cloudwatch = boto3.client('cloudwatch')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    """
    Monitor AgentCore performance metrics and trigger optimization actions
    """
    try:
        # Handle different event formats (CloudWatch alarm or direct invocation)
        if 'Records' in event and event['Records']:
            # SNS message format from CloudWatch alarm
            message = json.loads(event['Records'][0]['Sns']['Message'])
            alarm_name = message.get('AlarmName', 'Unknown')
            alarm_description = message.get('AlarmDescription', '')
            new_state = message.get('NewStateValue', 'UNKNOWN')
        else:
            # Direct invocation format for testing
            alarm_name = event.get('AlarmName', 'TestAlarm')
            alarm_description = event.get('AlarmDescription', 'Test alarm for performance monitoring')
            new_state = event.get('NewStateValue', 'ALARM')
        
        # Get performance metrics for analysis
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(minutes=5)
        
        # Query AgentCore metrics from CloudWatch
        try:
            response = cloudwatch.get_metric_statistics(
                Namespace='AWS/BedrockAgentCore',
                MetricName='Latency',
                Dimensions=[
                    {'Name': 'AgentId', 'Value': os.environ['AGENT_NAME']}
                ],
                StartTime=start_time,
                EndTime=end_time,
                Period=60,
                Statistics=['Average', 'Maximum', 'Minimum']
            )
        except Exception as metric_error:
            print(f"Warning: Could not retrieve metrics - {str(metric_error)}")
            response = {'Datapoints': []}
        
        # Analyze performance data and generate optimization recommendations
        performance_report = {
            'timestamp': end_time.isoformat(),
            'alarm_triggered': alarm_name,
            'alarm_description': alarm_description,
            'new_state': new_state,
            'agent_name': os.environ['AGENT_NAME'],
            'metrics': response['Datapoints'],
            'optimization_actions': [],
            'performance_analysis': {}
        }
        
        # Generate optimization recommendations based on metrics
        if response['Datapoints']:
            datapoints = response['Datapoints']
            avg_latency = sum(dp['Average'] for dp in datapoints) / len(datapoints)
            max_latency = max((dp['Maximum'] for dp in datapoints), default=0)
            min_latency = min((dp['Minimum'] for dp in datapoints), default=0)
            
            # Store performance analysis
            performance_report['performance_analysis'] = {
                'average_latency_ms': avg_latency,
                'maximum_latency_ms': max_latency,
                'minimum_latency_ms': min_latency,
                'latency_variance': max_latency - min_latency,
                'datapoint_count': len(datapoints)
            }
            
            # Generate specific optimization recommendations
            if avg_latency > 30000:  # 30 seconds
                performance_report['optimization_actions'].append({
                    'priority': 'HIGH',
                    'action': 'increase_memory_allocation',
                    'reason': f'High average latency detected: {avg_latency:.2f}ms',
                    'recommendation': 'Consider increasing Lambda memory or optimizing agent logic'
                })
            
            if max_latency > 60000:  # 60 seconds
                performance_report['optimization_actions'].append({
                    'priority': 'CRITICAL',
                    'action': 'investigate_timeout_issues',
                    'reason': f'Maximum latency threshold exceeded: {max_latency:.2f}ms',
                    'recommendation': 'Investigate potential timeout issues and implement circuit breakers'
                })
            
            if (max_latency - min_latency) > 45000:  # High variance
                performance_report['optimization_actions'].append({
                    'priority': 'MEDIUM',
                    'action': 'optimize_consistency',
                    'reason': f'High latency variance detected: {max_latency - min_latency:.2f}ms',
                    'recommendation': 'Implement consistent resource allocation and caching strategies'
                })
        else:
            performance_report['optimization_actions'].append({
                'priority': 'HIGH',
                'action': 'verify_agent_health',
                'reason': 'No metric data available for performance analysis',
                'recommendation': 'Check agent deployment status and CloudWatch metric configuration'
            })
        
        # Store comprehensive performance report in S3
        report_key = f"performance-reports/{datetime.now().strftime('%Y/%m/%d')}/{alarm_name}-{context.aws_request_id}.json"
        s3.put_object(
            Bucket=os.environ['S3_BUCKET_NAME'],
            Key=report_key,
            Body=json.dumps(performance_report, indent=2, default=str),
            ContentType='application/json',
            Metadata={
                'alarm-name': alarm_name,
                'agent-name': os.environ['AGENT_NAME'],
                'analysis-timestamp': end_time.isoformat()
            }
        )
        
        print(f"Performance analysis completed. Report stored at: s3://{os.environ['S3_BUCKET_NAME']}/{report_key}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Performance analysis completed successfully',
                'report_location': f"s3://{os.environ['S3_BUCKET_NAME']}/{report_key}",
                'optimization_actions_count': len(performance_report['optimization_actions']),
                'performance_summary': performance_report['performance_analysis']
            })
        }
        
    except Exception as e:
        error_msg = f"Error processing performance alert: {str(e)}"
        print(error_msg)
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': error_msg,
                'alarm_name': alarm_name if 'alarm_name' in locals() else 'Unknown'
            })
        }
`),
    });

    // Grant necessary permissions to the Lambda function
    this.monitoringBucket.grantReadWrite(this.performanceMonitorFunction);
    this.performanceMonitorFunction.addToRolePolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'cloudwatch:GetMetricStatistics',
          'cloudwatch:ListMetrics',
          'logs:DescribeLogGroups',
          'logs:DescribeLogStreams',
          'logs:FilterLogEvents',
        ],
        resources: ['*'],
      })
    );

    // Create Lambda log group with shorter retention for cost optimization
    new logs.LogGroup(this, 'LambdaLogGroup', {
      logGroupName: `/aws/lambda/${this.performanceMonitorFunction.functionName}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: RemovalPolicy.DESTROY,
    });

    // Create custom metric filters for advanced analytics
    new logs.MetricFilter(this, 'AgentResponseTimeFilter', {
      logGroup: this.agentLogGroup,
      filterPattern: logs.FilterPattern.literal(
        '[timestamp, requestId, level=INFO, metric="response_time", value]'
      ),
      metricNamespace: 'CustomAgentMetrics',
      metricName: 'AgentResponseTime',
      metricValue: '$value',
      defaultValue: 0,
    });

    new logs.MetricFilter(this, 'ConversationQualityFilter', {
      logGroup: this.agentLogGroup,
      filterPattern: logs.FilterPattern.literal(
        '[timestamp, requestId, level=INFO, metric="quality_score", score]'
      ),
      metricNamespace: 'CustomAgentMetrics',
      metricName: 'ConversationQuality',
      metricValue: '$score',
      defaultValue: 0,
    });

    new logs.MetricFilter(this, 'BusinessOutcomeSuccessFilter', {
      logGroup: this.agentLogGroup,
      filterPattern: logs.FilterPattern.literal(
        '[timestamp, requestId, level=INFO, outcome="SUCCESS"]'
      ),
      metricNamespace: 'CustomAgentMetrics',
      metricName: 'BusinessOutcomeSuccess',
      metricValue: '1',
      defaultValue: 0,
    });

    // Create CloudWatch alarms for performance monitoring
    const highLatencyAlarm = new cloudwatch.Alarm(this, 'HighLatencyAlarm', {
      alarmName: `AgentCore-HighLatency-${uniqueSuffix}`,
      alarmDescription: `Alert when ${agentName} latency exceeds ${highLatencyThreshold}ms`,
      metric: new cloudwatch.Metric({
        namespace: 'AWS/BedrockAgentCore',
        metricName: 'Latency',
        dimensionsMap: {
          AgentId: agentName,
        },
        statistic: 'Average',
        period: Duration.minutes(5),
      }),
      threshold: highLatencyThreshold,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    const systemErrorAlarm = new cloudwatch.Alarm(this, 'SystemErrorAlarm', {
      alarmName: `AgentCore-HighSystemErrors-${uniqueSuffix}`,
      alarmDescription: `Alert when ${agentName} system errors exceed ${systemErrorThreshold} per 5-minute period`,
      metric: new cloudwatch.Metric({
        namespace: 'AWS/BedrockAgentCore',
        metricName: 'SystemErrors',
        dimensionsMap: {
          AgentId: agentName,
        },
        statistic: 'Sum',
        period: Duration.minutes(5),
      }),
      threshold: systemErrorThreshold,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    const throttleAlarm = new cloudwatch.Alarm(this, 'ThrottleAlarm', {
      alarmName: `AgentCore-HighThrottles-${uniqueSuffix}`,
      alarmDescription: `Alert when ${agentName} throttling occurs more than ${throttleThreshold} times per 5-minute period`,
      metric: new cloudwatch.Metric({
        namespace: 'AWS/BedrockAgentCore',
        metricName: 'Throttles',
        dimensionsMap: {
          AgentId: agentName,
        },
        statistic: 'Sum',
        period: Duration.minutes(5),
      }),
      threshold: throttleThreshold,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Configure alarms to trigger the Lambda function
    highLatencyAlarm.addAlarmAction(
      new cloudwatchActions.LambdaAction(this.performanceMonitorFunction)
    );
    systemErrorAlarm.addAlarmAction(
      new cloudwatchActions.LambdaAction(this.performanceMonitorFunction)
    );
    throttleAlarm.addAlarmAction(
      new cloudwatchActions.LambdaAction(this.performanceMonitorFunction)
    );

    // Create comprehensive CloudWatch dashboard
    this.dashboard = new cloudwatch.Dashboard(this, 'PerformanceDashboard', {
      dashboardName: `AgentCore-Performance-${uniqueSuffix}`,
      widgets: [
        [
          // Performance metrics widget
          new cloudwatch.GraphWidget({
            title: 'Agent Performance Metrics',
            width: 12,
            height: 6,
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/BedrockAgentCore',
                metricName: 'Latency',
                dimensionsMap: { AgentId: agentName },
                statistic: 'Average',
                period: Duration.minutes(5),
                label: 'Average Latency',
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/BedrockAgentCore',
                metricName: 'Invocations',
                dimensionsMap: { AgentId: agentName },
                statistic: 'Sum',
                period: Duration.minutes(5),
                label: 'Invocations',
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/BedrockAgentCore',
                metricName: 'SessionCount',
                dimensionsMap: { AgentId: agentName },
                statistic: 'Average',
                period: Duration.minutes(5),
                label: 'Active Sessions',
              }),
            ],
            region: this.region,
          }),
          // Error and throttle metrics widget
          new cloudwatch.GraphWidget({
            title: 'Error and Throttle Rates',
            width: 12,
            height: 6,
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/BedrockAgentCore',
                metricName: 'UserErrors',
                dimensionsMap: { AgentId: agentName },
                statistic: 'Sum',
                period: Duration.minutes(5),
                label: 'User Errors',
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/BedrockAgentCore',
                metricName: 'SystemErrors',
                dimensionsMap: { AgentId: agentName },
                statistic: 'Sum',
                period: Duration.minutes(5),
                label: 'System Errors',
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/BedrockAgentCore',
                metricName: 'Throttles',
                dimensionsMap: { AgentId: agentName },
                statistic: 'Sum',
                period: Duration.minutes(5),
                label: 'Throttles',
              }),
            ],
            region: this.region,
            leftYAxis: {
              min: 0,
            },
          }),
        ],
        [
          // Recent errors log widget
          new cloudwatch.LogQueryWidget({
            title: 'Recent Agent Errors',
            width: 24,
            height: 6,
            logGroups: [this.agentLogGroup],
            queryLines: [
              'fields @timestamp, @message',
              'filter @message like /ERROR/',
              'sort @timestamp desc',
              'limit 20',
            ],
            region: this.region,
          }),
        ],
        [
          // Custom metrics widget
          new cloudwatch.GraphWidget({
            title: 'Business Metrics',
            width: 12,
            height: 6,
            left: [
              new cloudwatch.Metric({
                namespace: 'CustomAgentMetrics',
                metricName: 'ConversationQuality',
                statistic: 'Average',
                period: Duration.minutes(5),
                label: 'Conversation Quality Score',
              }),
              new cloudwatch.Metric({
                namespace: 'CustomAgentMetrics',
                metricName: 'BusinessOutcomeSuccess',
                statistic: 'Sum',
                period: Duration.minutes(5),
                label: 'Successful Outcomes',
              }),
            ],
            region: this.region,
          }),
          // Response time distribution widget
          new cloudwatch.GraphWidget({
            title: 'Response Time Distribution',
            width: 12,
            height: 6,
            left: [
              new cloudwatch.Metric({
                namespace: 'CustomAgentMetrics',
                metricName: 'AgentResponseTime',
                statistic: 'Average',
                period: Duration.minutes(5),
                label: 'Average Response Time',
              }),
              new cloudwatch.Metric({
                namespace: 'CustomAgentMetrics',
                metricName: 'AgentResponseTime',
                statistic: 'Maximum',
                period: Duration.minutes(5),
                label: 'Maximum Response Time',
              }),
            ],
            region: this.region,
          }),
        ],
      ],
    });

    // Output important resource information
    new cdk.CfnOutput(this, 'AgentCoreRoleArn', {
      value: agentCoreRole.roleArn,
      description: 'ARN of the IAM role for AgentCore observability',
      exportName: `${this.stackName}-AgentCoreRoleArn`,
    });

    new cdk.CfnOutput(this, 'MonitoringBucketName', {
      value: this.monitoringBucket.bucketName,
      description: 'Name of the S3 bucket for storing performance reports',
      exportName: `${this.stackName}-MonitoringBucketName`,
    });

    new cdk.CfnOutput(this, 'PerformanceMonitorFunctionName', {
      value: this.performanceMonitorFunction.functionName,
      description: 'Name of the Lambda function for performance monitoring',
      exportName: `${this.stackName}-PerformanceMonitorFunctionName`,
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${this.dashboard.dashboardName}`,
      description: 'URL to the CloudWatch dashboard for agent performance monitoring',
    });

    new cdk.CfnOutput(this, 'AgentLogGroupName', {
      value: this.agentLogGroup.logGroupName,
      description: 'Name of the CloudWatch log group for agent logs',
      exportName: `${this.stackName}-AgentLogGroupName`,
    });

    // Add tags for resource management and cost tracking
    cdk.Tags.of(this).add('Project', 'AgentCore-Performance-Monitoring');
    cdk.Tags.of(this).add('Environment', 'Production');
    cdk.Tags.of(this).add('CostCenter', 'AI-Operations');
    cdk.Tags.of(this).add('Owner', 'Platform-Team');
  }
}

// CDK App instantiation
const app = new cdk.App();

// Get configuration from CDK context or environment variables
const agentName = app.node.tryGetContext('agentName') || process.env.AGENT_NAME || 'ai-agent-default';
const environment = app.node.tryGetContext('environment') || process.env.ENVIRONMENT || 'development';

// Create the main stack
new AgentCorePerformanceMonitoringStack(app, 'AgentCorePerformanceMonitoringStack', {
  stackName: `agentcore-monitoring-${environment}`,
  description: 'AWS CDK Stack for AgentCore Performance Monitoring with CloudWatch',
  agentName: agentName,
  logRetentionDays: logs.RetentionDays.ONE_MONTH,
  highLatencyThreshold: 30000, // 30 seconds
  systemErrorThreshold: 5,
  throttleThreshold: 10,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'us-east-1',
  },
  tags: {
    Project: 'AgentCore-Performance-Monitoring',
    Environment: environment,
    Repository: 'aws-recipes',
    GeneratedBy: 'AWS-CDK',
  },
});

app.synth();