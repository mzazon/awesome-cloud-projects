#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as ce from 'aws-cdk-lib/aws-ce';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Duration, RemovalPolicy } from 'aws-cdk-lib';

/**
 * Properties for the CostAnomalyDetectionStack
 */
interface CostAnomalyDetectionStackProps extends cdk.StackProps {
  /**
   * Email address for cost anomaly notifications
   */
  readonly notificationEmail: string;

  /**
   * Threshold for cost anomaly detection in USD
   * @default 10.0
   */
  readonly anomalyThreshold?: number;

  /**
   * Environment name for resource naming
   * @default 'dev'
   */
  readonly environment?: string;
}

/**
 * CDK Stack for Automated Cost Anomaly Detection with CloudWatch and Lambda
 * 
 * This stack implements a comprehensive cost monitoring solution that:
 * - Detects cost anomalies using AWS Cost Anomaly Detection service
 * - Processes anomaly events through EventBridge and Lambda
 * - Sends enhanced notifications via SNS
 * - Provides CloudWatch dashboards for monitoring
 * - Publishes custom metrics for cost tracking
 */
export class CostAnomalyDetectionStack extends cdk.Stack {
  
  constructor(scope: Construct, id: string, props: CostAnomalyDetectionStackProps) {
    super(scope, id, props);

    const environment = props.environment || 'dev';
    const anomalyThreshold = props.anomalyThreshold || 10.0;

    // Create SNS Topic for cost anomaly notifications
    const costAnomalyTopic = new sns.Topic(this, 'CostAnomalyTopic', {
      topicName: `cost-anomaly-alerts-${environment}`,
      displayName: 'Cost Anomaly Alerts',
      description: 'Topic for AWS cost anomaly detection notifications',
    });

    // Add email subscription to SNS topic
    costAnomalyTopic.addSubscription(
      new snsSubscriptions.EmailSubscription(props.notificationEmail)
    );

    // Create IAM role for Lambda function with least privilege permissions
    const lambdaRole = new iam.Role(this, 'CostAnomalyLambdaRole', {
      roleName: `CostAnomalyLambdaRole-${environment}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'IAM role for Cost Anomaly Detection Lambda function',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        CostAnomalyPolicy: new iam.PolicyDocument({
          statements: [
            // Cost Explorer permissions for billing data access
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'ce:GetCostAndUsage',
                'ce:GetUsageReport',
                'ce:GetDimensionValues',
                'ce:GetReservationCoverage',
                'ce:GetReservationPurchaseRecommendation',
                'ce:GetReservationUtilization',
              ],
              resources: ['*'],
            }),
            // CloudWatch permissions for custom metrics
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'cloudwatch:PutMetricData',
                'cloudwatch:GetMetricStatistics',
              ],
              resources: ['*'],
            }),
            // SNS permissions for notifications
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['sns:Publish'],
              resources: [costAnomalyTopic.topicArn],
            }),
          ],
        }),
      },
    });

    // Create CloudWatch Log Group for Lambda function with retention
    const lambdaLogGroup = new logs.LogGroup(this, 'CostAnomalyLambdaLogGroup', {
      logGroupName: `/aws/lambda/cost-anomaly-processor-${environment}`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: RemovalPolicy.DESTROY,
    });

    // Create Lambda function for cost anomaly processing
    const costAnomalyFunction = new lambda.Function(this, 'CostAnomalyFunction', {
      functionName: `cost-anomaly-processor-${environment}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: Duration.minutes(5),
      memorySize: 256,
      description: 'Enhanced Cost Anomaly Detection processor with custom metrics and notifications',
      environment: {
        SNS_TOPIC_ARN: costAnomalyTopic.topicArn,
        ENVIRONMENT: environment,
      },
      logGroup: lambdaLogGroup,
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from datetime import datetime, timedelta
from decimal import Decimal

def lambda_handler(event, context):
    """
    Process Cost Anomaly Detection events with enhanced analysis
    """
    print(f"Received event: {json.dumps(event, indent=2)}")
    
    # Initialize AWS clients
    ce_client = boto3.client('ce')
    cloudwatch = boto3.client('cloudwatch')
    sns = boto3.client('sns')
    
    try:
        # Extract anomaly details from EventBridge event
        detail = event['detail']
        anomaly_id = detail['anomalyId']
        total_impact = detail['impact']['totalImpact']
        account_name = detail['accountName']
        dimension_value = detail.get('dimensionValue', 'N/A')
        
        # Calculate percentage impact
        total_actual = detail['impact']['totalActualSpend']
        total_expected = detail['impact']['totalExpectedSpend']
        impact_percentage = detail['impact']['totalImpactPercentage']
        
        # Get additional cost breakdown
        cost_breakdown = get_cost_breakdown(ce_client, detail)
        
        # Publish custom CloudWatch metrics
        publish_metrics(cloudwatch, anomaly_id, total_impact, impact_percentage)
        
        # Send enhanced notification
        send_enhanced_notification(sns, detail, cost_breakdown)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Successfully processed anomaly {anomaly_id}',
                'total_impact': float(total_impact),
                'impact_percentage': float(impact_percentage)
            })
        }
        
    except Exception as e:
        print(f"Error processing anomaly: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def get_cost_breakdown(ce_client, detail):
    """Get detailed cost breakdown for the anomaly period"""
    try:
        end_date = detail['anomalyEndDate'][:10]  # YYYY-MM-DD
        start_date = detail['anomalyStartDate'][:10]
        
        # Get cost and usage data
        response = ce_client.get_cost_and_usage(
            TimePeriod={
                'Start': start_date,
                'End': end_date
            },
            Granularity='DAILY',
            Metrics=['BlendedCost', 'UsageQuantity'],
            GroupBy=[
                {'Type': 'DIMENSION', 'Key': 'SERVICE'}
            ]
        )
        
        return response.get('ResultsByTime', [])
        
    except Exception as e:
        print(f"Error getting cost breakdown: {str(e)}")
        return []

def publish_metrics(cloudwatch, anomaly_id, total_impact, impact_percentage):
    """Publish custom CloudWatch metrics for anomaly tracking"""
    try:
        cloudwatch.put_metric_data(
            Namespace='AWS/CostAnomaly',
            MetricData=[
                {
                    'MetricName': 'AnomalyImpact',
                    'Value': float(total_impact),
                    'Unit': 'None',
                    'Dimensions': [
                        {
                            'Name': 'AnomalyId',
                            'Value': anomaly_id
                        }
                    ]
                },
                {
                    'MetricName': 'AnomalyPercentage',
                    'Value': float(impact_percentage),
                    'Unit': 'Percent',
                    'Dimensions': [
                        {
                            'Name': 'AnomalyId',
                            'Value': anomaly_id
                        }
                    ]
                }
            ]
        )
        print("✅ Custom metrics published to CloudWatch")
        
    except Exception as e:
        print(f"Error publishing metrics: {str(e)}")

def send_enhanced_notification(sns, detail, cost_breakdown):
    """Send enhanced notification with detailed analysis"""
    try:
        # Format the notification message
        message = format_notification_message(detail, cost_breakdown)
        
        # Publish to SNS
        response = sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Subject=f"🚨 AWS Cost Anomaly Detected - ${{detail['impact']['totalImpact']:.2f}}",
            Message=message
        )
        
        print(f"✅ Notification sent: {response['MessageId']}")
        
    except Exception as e:
        print(f"Error sending notification: {str(e)}")

def format_notification_message(detail, cost_breakdown):
    """Format detailed notification message"""
    impact = detail['impact']
    
    message = f"""
AWS Cost Anomaly Detection Alert
================================

Anomaly ID: {detail['anomalyId']}
Account: {detail['accountName']}
Service: {detail.get('dimensionValue', 'Multiple Services')}

Cost Impact:
- Total Impact: ${impact['totalImpact']:.2f}
- Actual Spend: ${impact['totalActualSpend']:.2f}
- Expected Spend: ${impact['totalExpectedSpend']:.2f}
- Percentage Increase: {impact['totalImpactPercentage']:.1f}%

Period:
- Start: {detail['anomalyStartDate']}
- End: {detail['anomalyEndDate']}

Anomaly Score:
- Current: {detail['anomalyScore']['currentScore']:.3f}
- Maximum: {detail['anomalyScore']['maxScore']:.3f}

Root Causes:
"""
    
    # Add root cause analysis
    for cause in detail.get('rootCauses', []):
        message += f"""
- Account: {cause.get('linkedAccountName', 'N/A')}
  Service: {cause.get('service', 'N/A')}
  Region: {cause.get('region', 'N/A')}
  Usage Type: {cause.get('usageType', 'N/A')}
  Contribution: ${cause.get('impact', {}).get('contribution', 0):.2f}
"""
    
    message += f"""

Next Steps:
1. Review the affected services and usage patterns
2. Check for any unauthorized usage or misconfigurations
3. Consider implementing cost controls if needed
4. Monitor for additional anomalies

AWS Console Links:
- Cost Explorer: https://console.aws.amazon.com/billing/home#/costexplorer
- Cost Anomaly Detection: https://console.aws.amazon.com/billing/home#/anomaly-detection

Generated by: AWS Cost Anomaly Detection Lambda
Timestamp: {datetime.now().isoformat()}
Environment: {os.environ.get('ENVIRONMENT', 'unknown')}
    """
    
    return message
`),
    });

    // Create EventBridge rule to capture Cost Anomaly Detection events
    const costAnomalyRule = new events.Rule(this, 'CostAnomalyRule', {
      ruleName: `cost-anomaly-rule-${environment}`,
      description: 'Rule to capture AWS Cost Anomaly Detection events',
      eventPattern: {
        source: ['aws.ce'],
        detailType: ['Anomaly Detected'],
      },
    });

    // Add Lambda function as target for EventBridge rule
    costAnomalyRule.addTarget(new targets.LambdaFunction(costAnomalyFunction, {
      retryAttempts: 3,
    }));

    // Create Cost Anomaly Monitor for EC2 services
    const costAnomalyMonitor = new ce.CfnAnomalyMonitor(this, 'CostAnomalyMonitor', {
      monitorName: `cost-anomaly-monitor-${environment}`,
      monitorType: 'DIMENSIONAL',
      monitorSpecification: JSON.stringify({
        Dimension: 'SERVICE',
        MatchOptions: ['EQUALS'],
        Values: ['Amazon Elastic Compute Cloud - Compute']
      }),
      monitorDimension: 'SERVICE',
    });

    // Create Cost Anomaly Detector with SNS integration
    const costAnomalyDetector = new ce.CfnAnomalyDetector(this, 'CostAnomalyDetector', {
      detectorName: `cost-anomaly-detector-${environment}`,
      monitorArnList: [costAnomalyMonitor.attrMonitorArn],
      subscribers: [{
        address: costAnomalyTopic.topicArn,
        type: 'SNS',
        status: 'CONFIRMED'
      }],
      threshold: anomalyThreshold,
      frequency: 'IMMEDIATE',
    });

    // Create CloudWatch Dashboard for cost monitoring
    const costMonitoringDashboard = new cloudwatch.Dashboard(this, 'CostMonitoringDashboard', {
      dashboardName: `CostAnomalyDetection-${environment}`,
    });

    // Add cost anomaly metrics widget to dashboard
    costMonitoringDashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Cost Anomaly Metrics',
        width: 12,
        height: 6,
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/CostAnomaly',
            metricName: 'AnomalyImpact',
            statistic: 'Sum',
            period: Duration.minutes(5),
          }),
        ],
        right: [
          new cloudwatch.Metric({
            namespace: 'AWS/CostAnomaly',
            metricName: 'AnomalyPercentage',
            statistic: 'Average',
            period: Duration.minutes(5),
          }),
        ],
      })
    );

    // Add Lambda function metrics widget to dashboard
    costMonitoringDashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Lambda Function Metrics',
        width: 12,
        height: 6,
        left: [
          costAnomalyFunction.metricInvocations({
            statistic: 'Sum',
            period: Duration.minutes(5),
          }),
          costAnomalyFunction.metricErrors({
            statistic: 'Sum',
            period: Duration.minutes(5),
          }),
        ],
        right: [
          costAnomalyFunction.metricDuration({
            statistic: 'Average',
            period: Duration.minutes(5),
          }),
        ],
      })
    );

    // CloudWatch Alarms for monitoring the system health
    const lambdaErrorAlarm = new cloudwatch.Alarm(this, 'LambdaErrorAlarm', {
      alarmName: `cost-anomaly-lambda-errors-${environment}`,
      alarmDescription: 'Alarm for Lambda function errors in cost anomaly processing',
      metric: costAnomalyFunction.metricErrors({
        statistic: 'Sum',
        period: Duration.minutes(5),
      }),
      threshold: 1,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Add alarm action to send notification
    lambdaErrorAlarm.addAlarmAction({
      bind: () => ({ alarmActionArn: costAnomalyTopic.topicArn }),
    });

    // Output important resource identifiers
    new cdk.CfnOutput(this, 'SNSTopicArn', {
      value: costAnomalyTopic.topicArn,
      description: 'ARN of the SNS topic for cost anomaly notifications',
      exportName: `${this.stackName}-SNSTopicArn`,
    });

    new cdk.CfnOutput(this, 'LambdaFunctionArn', {
      value: costAnomalyFunction.functionArn,
      description: 'ARN of the Lambda function processing cost anomalies',
      exportName: `${this.stackName}-LambdaFunctionArn`,
    });

    new cdk.CfnOutput(this, 'CostAnomalyMonitorArn', {
      value: costAnomalyMonitor.attrMonitorArn,
      description: 'ARN of the Cost Anomaly Detection monitor',
      exportName: `${this.stackName}-CostAnomalyMonitorArn`,
    });

    new cdk.CfnOutput(this, 'CostAnomalyDetectorArn', {
      value: costAnomalyDetector.attrDetectorArn,
      description: 'ARN of the Cost Anomaly Detection detector',
      exportName: `${this.stackName}-CostAnomalyDetectorArn`,
    });

    new cdk.CfnOutput(this, 'DashboardURL', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${costMonitoringDashboard.dashboardName}`,
      description: 'URL to the CloudWatch dashboard for cost monitoring',
      exportName: `${this.stackName}-DashboardURL`,
    });

    // Add tags to all resources for cost allocation and management
    cdk.Tags.of(this).add('Project', 'CostAnomalyDetection');
    cdk.Tags.of(this).add('Environment', environment);
    cdk.Tags.of(this).add('Owner', 'FinOps');
    cdk.Tags.of(this).add('Purpose', 'CostMonitoring');
  }
}

// CDK App instantiation and stack deployment
const app = new cdk.App();

// Get configuration from CDK context or environment variables
const notificationEmail = app.node.tryGetContext('notificationEmail') || 
                         process.env.NOTIFICATION_EMAIL ||
                         'admin@example.com';

const environment = app.node.tryGetContext('environment') || 
                   process.env.ENVIRONMENT || 
                   'dev';

const anomalyThreshold = Number(app.node.tryGetContext('anomalyThreshold')) || 
                        Number(process.env.ANOMALY_THRESHOLD) || 
                        10.0;

// Deploy the Cost Anomaly Detection stack
new CostAnomalyDetectionStack(app, 'CostAnomalyDetectionStack', {
  notificationEmail,
  environment,
  anomalyThreshold,
  description: 'Automated Cost Anomaly Detection with CloudWatch and Lambda using AWS CDK',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
});

// Synthesize the CloudFormation template
app.synth();