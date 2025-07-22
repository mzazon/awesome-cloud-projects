#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as cloudwatchActions from 'aws-cdk-lib/aws-cloudwatch-actions';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import { Construct } from 'constructs';

/**
 * Properties for the OperationalAnalyticsStack
 */
export interface OperationalAnalyticsStackProps extends cdk.StackProps {
  /**
   * Email address for alert notifications
   */
  readonly alertEmail?: string;
  
  /**
   * Environment prefix for resource naming
   */
  readonly environmentPrefix?: string;
  
  /**
   * Log retention period in days
   */
  readonly logRetentionDays?: logs.RetentionDays;
  
  /**
   * Enable anomaly detection
   */
  readonly enableAnomalyDetection?: boolean;
}

/**
 * CDK Stack for Analyzing Operational Data with CloudWatch Insights
 * 
 * This stack creates:
 * - Lambda function for log generation
 * - CloudWatch Log Groups with appropriate retention
 * - CloudWatch Dashboard with Insights queries
 * - SNS Topic for alerting
 * - CloudWatch Alarms for error monitoring
 * - Metric Filters for custom metrics
 * - Anomaly Detection for intelligent monitoring
 */
export class OperationalAnalyticsStack extends cdk.Stack {
  public readonly logGroup: logs.LogGroup;
  public readonly lambdaFunction: lambda.Function;
  public readonly snsTopic: sns.Topic;
  public readonly dashboard: cloudwatch.Dashboard;

  constructor(scope: Construct, id: string, props?: OperationalAnalyticsStackProps) {
    super(scope, id, props);

    // Extract properties with defaults
    const alertEmail = props?.alertEmail;
    const envPrefix = props?.environmentPrefix || 'operational-analytics';
    const retentionDays = props?.logRetentionDays || logs.RetentionDays.ONE_MONTH;
    const enableAnomalyDetection = props?.enableAnomalyDetection ?? true;

    // Generate unique suffix for resource naming
    const uniqueSuffix = this.node.addr.substring(0, 8);

    // Create CloudWatch Log Group for operational analytics
    this.logGroup = new logs.LogGroup(this, 'OperationalLogGroup', {
      logGroupName: `/aws/lambda/${envPrefix}-demo-${uniqueSuffix}`,
      retention: retentionDays,
      logGroupClass: logs.LogGroupClass.STANDARD,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
    });

    // Create IAM role for Lambda function with CloudWatch Logs permissions
    const lambdaRole = new iam.Role(this, 'LogGeneratorRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        CloudWatchLogsPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:CreateLogStream',
                'logs:PutLogEvents',
              ],
              resources: [this.logGroup.logGroupArn],
            }),
          ],
        }),
      },
    });

    // Create Lambda function for generating realistic log data
    this.lambdaFunction = new lambda.Function(this, 'LogGeneratorFunction', {
      functionName: `log-generator-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: cdk.Duration.seconds(30),
      logGroup: this.logGroup,
      code: lambda.Code.fromInline(`
import json
import random
import time
import logging
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Generate various log patterns for operational analytics demonstration.
    Creates realistic log entries with different severity levels, performance metrics,
    and business events to showcase CloudWatch Insights capabilities.
    """
    # Generate various log patterns for analytics
    log_patterns = [
        {"level": "INFO", "message": "User authentication successful", "user_id": f"user_{random.randint(1000, 9999)}", "response_time": random.randint(100, 500)},
        {"level": "ERROR", "message": "Database connection failed", "error_code": "DB_CONN_ERR", "retry_count": random.randint(1, 3)},
        {"level": "WARN", "message": "High memory usage detected", "memory_usage": random.randint(70, 95), "threshold": 80},
        {"level": "INFO", "message": "API request processed", "endpoint": f"/api/v1/users/{random.randint(1, 100)}", "method": random.choice(["GET", "POST", "PUT"])},
        {"level": "ERROR", "message": "Payment processing failed", "transaction_id": f"txn_{random.randint(100000, 999999)}", "amount": random.randint(10, 1000)},
        {"level": "INFO", "message": "Cache hit", "cache_key": f"user_profile_{random.randint(1, 1000)}", "hit_rate": random.uniform(0.7, 0.95)},
        {"level": "DEBUG", "message": "SQL query executed", "query_time": random.randint(50, 2000), "table": random.choice(["users", "orders", "products"])},
        {"level": "WARN", "message": "Rate limit approaching", "current_rate": random.randint(80, 99), "limit": 100}
    ]
    
    # Generate 5-10 random log entries
    for i in range(random.randint(5, 10)):
        log_entry = random.choice(log_patterns)
        log_entry["timestamp"] = datetime.utcnow().isoformat()
        log_entry["request_id"] = f"req_{random.randint(1000000, 9999999)}"
        
        # Log with different levels
        if log_entry["level"] == "ERROR":
            logger.error(json.dumps(log_entry))
        elif log_entry["level"] == "WARN":
            logger.warning(json.dumps(log_entry))
        elif log_entry["level"] == "DEBUG":
            logger.debug(json.dumps(log_entry))
        else:
            logger.info(json.dumps(log_entry))
        
        # Small delay to spread timestamps
        time.sleep(0.1)
    
    return {
        'statusCode': 200,
        'body': json.dumps('Log generation completed successfully')
    }
`),
    });

    // Create SNS Topic for operational alerts
    this.snsTopic = new sns.Topic(this, 'OperationalAlertsTopic', {
      topicName: `operational-alerts-${uniqueSuffix}`,
      displayName: 'Operational Analytics Alerts',
    });

    // Add email subscription if provided
    if (alertEmail) {
      this.snsTopic.addSubscription(new snsSubscriptions.EmailSubscription(alertEmail));
    }

    // Create metric filter for error rate monitoring
    const errorMetricFilter = new logs.MetricFilter(this, 'ErrorRateMetricFilter', {
      logGroup: this.logGroup,
      filterName: 'ErrorRateFilter',
      filterPattern: logs.FilterPattern.allTerms('ERROR'),
      metricNamespace: 'OperationalAnalytics',
      metricName: 'ErrorRate',
      metricValue: '1',
      defaultValue: 0,
    });

    // Create metric filter for log volume monitoring
    const logVolumeMetricFilter = new logs.MetricFilter(this, 'LogVolumeMetricFilter', {
      logGroup: this.logGroup,
      filterName: 'LogVolumeFilter',
      filterPattern: logs.FilterPattern.allEvents(),
      metricNamespace: 'OperationalAnalytics',
      metricName: 'LogVolume',
      metricValue: '1',
      defaultValue: 0,
    });

    // Create CloudWatch Alarm for high error rate
    const errorRateAlarm = new cloudwatch.Alarm(this, 'HighErrorRateAlarm', {
      alarmName: `HighErrorRate-${uniqueSuffix}`,
      alarmDescription: 'Alert when error rate exceeds threshold',
      metric: errorMetricFilter.metric({
        statistic: cloudwatch.Statistic.SUM,
        period: cdk.Duration.minutes(5),
      }),
      threshold: 5,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Add SNS action to error rate alarm
    errorRateAlarm.addAlarmAction(new cloudwatchActions.SnsAction(this.snsTopic));

    // Create CloudWatch Alarm for excessive log volume
    const logVolumeAlarm = new cloudwatch.Alarm(this, 'HighLogVolumeAlarm', {
      alarmName: `HighLogVolume-${uniqueSuffix}`,
      alarmDescription: 'Alert when log volume exceeds budget threshold',
      metric: logVolumeMetricFilter.metric({
        statistic: cloudwatch.Statistic.SUM,
        period: cdk.Duration.hours(1),
      }),
      threshold: 10000,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Add SNS action to log volume alarm
    logVolumeAlarm.addAlarmAction(new cloudwatchActions.SnsAction(this.snsTopic));

    // Create anomaly detection for log ingestion (if enabled)
    if (enableAnomalyDetection) {
      // Create anomaly detector for log ingestion bytes
      const anomalyDetector = new cloudwatch.CfnAnomalyDetector(this, 'LogIngestionAnomalyDetector', {
        namespace: 'AWS/Logs',
        metricName: 'IncomingBytes',
        stat: 'Average',
        dimensions: [
          {
            name: 'LogGroupName',
            value: this.logGroup.logGroupName,
          },
        ],
      });

      // Create anomaly alarm
      const anomalyAlarm = new cloudwatch.CfnAlarm(this, 'LogIngestionAnomalyAlarm', {
        alarmName: `LogIngestionAnomaly-${uniqueSuffix}`,
        alarmDescription: 'Detect anomalies in log ingestion patterns',
        comparisonOperator: 'LessThanLowerOrGreaterThanUpperThreshold',
        evaluationPeriods: 2,
        threshold: 2,
        treatMissingData: 'notBreaching',
        metrics: [
          {
            id: 'm1',
            metricStat: {
              metric: {
                namespace: 'AWS/Logs',
                metricName: 'IncomingBytes',
                dimensions: [
                  {
                    name: 'LogGroupName',
                    value: this.logGroup.logGroupName,
                  },
                ],
              },
              period: 300,
              stat: 'Average',
            },
          },
          {
            id: 'ad1',
            expression: 'ANOMALY_DETECTION_FUNCTION(m1, 2)',
          },
        ],
        alarmActions: [this.snsTopic.topicArn],
      });

      // Add dependency to ensure anomaly detector is created first
      anomalyAlarm.addDependency(anomalyDetector);
    }

    // Create CloudWatch Dashboard with Insights queries
    this.dashboard = new cloudwatch.Dashboard(this, 'OperationalAnalyticsDashboard', {
      dashboardName: `OperationalAnalytics-${uniqueSuffix}`,
    });

    // Add log insights widgets to dashboard
    this.dashboard.addWidgets(
      // Error Analysis Widget
      new cloudwatch.LogQueryWidget({
        title: 'Error Analysis',
        logGroups: [this.logGroup],
        query: `fields @timestamp, @message, @logStream
| filter @message like /ERROR/
| stats count() as error_count by bin(5m)
| sort @timestamp desc
| limit 50`,
        width: 12,
        height: 6,
        view: cloudwatch.LogQueryVisualizationType.TABLE,
      }),

      // Performance Metrics Widget
      new cloudwatch.LogQueryWidget({
        title: 'Performance Metrics',
        logGroups: [this.logGroup],
        query: `fields @timestamp, @message
| filter @message like /response_time/
| parse @message '"response_time": *' as response_time
| stats avg(response_time) as avg_response_time, max(response_time) as max_response_time by bin(1m)
| sort @timestamp desc`,
        width: 12,
        height: 6,
        view: cloudwatch.LogQueryVisualizationType.TABLE,
      }),
    );

    // Add second row of widgets
    this.dashboard.addWidgets(
      // Top Active Users Widget
      new cloudwatch.LogQueryWidget({
        title: 'Top Active Users',
        logGroups: [this.logGroup],
        query: `fields @timestamp, @message
| filter @message like /user_id/
| parse @message '"user_id": "*"' as user_id
| stats count() as activity_count by user_id
| sort activity_count desc
| limit 20`,
        width: 24,
        height: 6,
        view: cloudwatch.LogQueryVisualizationType.TABLE,
      }),
    );

    // Create EventBridge rule to trigger log generation periodically (for demo)
    const logGenerationRule = new events.Rule(this, 'LogGenerationRule', {
      ruleName: `log-generation-${uniqueSuffix}`,
      description: 'Trigger log generation every 5 minutes for demo purposes',
      schedule: events.Schedule.rate(cdk.Duration.minutes(5)),
      enabled: false, // Disabled by default to avoid costs
    });

    // Add Lambda target to the rule
    logGenerationRule.addTarget(new targets.LambdaFunction(this.lambdaFunction));

    // Stack outputs
    new cdk.CfnOutput(this, 'LogGroupName', {
      value: this.logGroup.logGroupName,
      description: 'CloudWatch Log Group for operational analytics',
    });

    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: this.lambdaFunction.functionName,
      description: 'Lambda function for generating log data',
    });

    new cdk.CfnOutput(this, 'SNSTopicArn', {
      value: this.snsTopic.topicArn,
      description: 'SNS Topic ARN for operational alerts',
    });

    new cdk.CfnOutput(this, 'DashboardName', {
      value: this.dashboard.dashboardName,
      description: 'CloudWatch Dashboard for operational analytics',
    });

    new cdk.CfnOutput(this, 'DashboardURL', {
      value: `https://console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${this.dashboard.dashboardName}`,
      description: 'URL to access the CloudWatch Dashboard',
    });

    new cdk.CfnOutput(this, 'LogInsightsURL', {
      value: `https://console.aws.amazon.com/cloudwatch/home?region=${this.region}#logsV2:logs-insights`,
      description: 'URL to access CloudWatch Logs Insights',
    });

    // Add tags to all resources
    cdk.Tags.of(this).add('Project', 'OperationalAnalytics');
    cdk.Tags.of(this).add('Environment', envPrefix);
    cdk.Tags.of(this).add('Purpose', 'Demonstration');
  }
}

/**
 * CDK App entry point
 */
const app = new cdk.App();

// Get context values from cdk.json or command line
const alertEmail = app.node.tryGetContext('alertEmail');
const environmentPrefix = app.node.tryGetContext('environmentPrefix') || 'operational-analytics';
const enableAnomalyDetection = app.node.tryGetContext('enableAnomalyDetection') !== 'false';

// Create the operational analytics stack
new OperationalAnalyticsStack(app, 'OperationalAnalyticsStack', {
  description: 'Operational Analytics with CloudWatch Insights - Comprehensive log analysis and monitoring solution',
  alertEmail: alertEmail,
  environmentPrefix: environmentPrefix,
  logRetentionDays: logs.RetentionDays.ONE_MONTH,
  enableAnomalyDetection: enableAnomalyDetection,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
});

// Synthesize the app
app.synth();