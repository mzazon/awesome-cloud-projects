#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ce from 'aws-cdk-lib/aws-ce';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as events from 'aws-cdk-lib/aws-events';
import * as eventsTargets from 'aws-cdk-lib/aws-events-targets';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';

/**
 * Interface for Cost Anomaly Detection Stack properties
 */
interface CostAnomalyDetectionStackProps extends cdk.StackProps {
  /**
   * Email address for cost anomaly notifications
   */
  notificationEmail: string;
  
  /**
   * Threshold for daily summary alerts in USD
   * @default 100
   */
  dailySummaryThreshold?: number;
  
  /**
   * Threshold for individual alerts in USD
   * @default 50
   */
  individualAlertThreshold?: number;
  
  /**
   * Environment tag values to monitor for tag-based monitoring
   * @default ['Production', 'Staging']
   */
  environmentTagValues?: string[];
}

/**
 * AWS CDK Stack for implementing Cost Anomaly Detection with automated monitoring and alerting
 * 
 * This stack creates:
 * - Cost Anomaly Detection monitors (Service-based, Account-based, Tag-based)
 * - SNS topic for notifications with email subscription
 * - Cost anomaly subscriptions for daily summaries and individual alerts
 * - EventBridge rule to capture cost anomaly events
 * - Lambda function for automated anomaly processing
 * - CloudWatch dashboard for cost anomaly visualization
 */
class CostAnomalyDetectionStack extends cdk.Stack {
  
  /**
   * SNS topic for cost anomaly notifications
   */
  public readonly snsTopicArn: string;
  
  /**
   * Lambda function ARN for anomaly processing
   */
  public readonly lambdaFunctionArn: string;
  
  /**
   * CloudWatch dashboard URL
   */
  public readonly dashboardUrl: string;

  constructor(scope: Construct, id: string, props: CostAnomalyDetectionStackProps) {
    super(scope, id, props);

    // Validate required properties
    if (!props.notificationEmail) {
      throw new Error('notificationEmail is required');
    }

    // Set default values
    const dailyThreshold = props.dailySummaryThreshold ?? 100;
    const individualThreshold = props.individualAlertThreshold ?? 50;
    const environmentTags = props.environmentTagValues ?? ['Production', 'Staging'];

    // Create SNS topic for cost anomaly notifications
    const costAnomalyTopic = new sns.Topic(this, 'CostAnomalyTopic', {
      topicName: `cost-anomaly-alerts-${this.node.id.toLowerCase()}`,
      displayName: 'Cost Anomaly Detection Alerts',
      description: 'SNS topic for AWS Cost Anomaly Detection notifications',
    });

    // Add email subscription to SNS topic
    costAnomalyTopic.addSubscription(
      new snsSubscriptions.EmailSubscription(props.notificationEmail)
    );

    this.snsTopicArn = costAnomalyTopic.topicArn;

    // Create Cost Anomaly Detection monitors
    const servicesMonitor = this.createServicesMonitor();
    const accountMonitor = this.createAccountMonitor();
    const tagMonitor = this.createTagMonitor(environmentTags);

    // Create anomaly subscriptions
    this.createDailySummarySubscription([servicesMonitor, accountMonitor], props.notificationEmail, dailyThreshold);
    this.createIndividualAlertSubscription([tagMonitor], costAnomalyTopic.topicArn, individualThreshold);

    // Create Lambda function for anomaly processing
    const anomalyProcessor = this.createAnomalyProcessorFunction();
    this.lambdaFunctionArn = anomalyProcessor.functionArn;

    // Create EventBridge rule for cost anomaly events
    this.createEventBridgeRule(anomalyProcessor);

    // Create CloudWatch dashboard
    const dashboard = this.createCloudWatchDashboard(anomalyProcessor);
    this.dashboardUrl = `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${dashboard.dashboardName}`;

    // Output important resource ARNs and URLs
    new cdk.CfnOutput(this, 'SNSTopicArn', {
      value: this.snsTopicArn,
      description: 'SNS Topic ARN for cost anomaly notifications',
      exportName: `${this.stackName}-SNSTopicArn`,
    });

    new cdk.CfnOutput(this, 'LambdaFunctionArn', {
      value: this.lambdaFunctionArn,
      description: 'Lambda function ARN for anomaly processing',
      exportName: `${this.stackName}-LambdaFunctionArn`,
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: this.dashboardUrl,
      description: 'CloudWatch dashboard URL for cost anomaly monitoring',
      exportName: `${this.stackName}-DashboardUrl`,
    });

    // Apply common tags to all resources
    cdk.Tags.of(this).add('Application', 'CostAnomalyDetection');
    cdk.Tags.of(this).add('Environment', 'Production');
    cdk.Tags.of(this).add('Purpose', 'CostGovernance');
  }

  /**
   * Create AWS Services Cost Anomaly Monitor
   * 
   * This monitor tracks anomalies across individual AWS services,
   * enabling detection of unusual usage patterns in specific services.
   */
  private createServicesMonitor(): ce.CfnAnomalyDetector {
    return new ce.CfnAnomalyDetector(this, 'ServicesMonitor', {
      anomalyDetectorName: 'AWS-Services-Monitor',
      monitorType: 'DIMENSIONAL',
      monitorSpecification: {
        dimension: 'SERVICE',
        matchOptions: ['EQUALS'],
      },
    });
  }

  /**
   * Create Account-Based Cost Anomaly Monitor
   * 
   * This monitor analyzes spending patterns within specific linked accounts,
   * valuable for organizations using AWS Organizations.
   */
  private createAccountMonitor(): ce.CfnAnomalyDetector {
    return new ce.CfnAnomalyDetector(this, 'AccountMonitor', {
      anomalyDetectorName: 'Account-Based-Monitor',
      monitorType: 'DIMENSIONAL',
      monitorSpecification: {
        dimension: 'LINKED_ACCOUNT',
        matchOptions: ['EQUALS'],
      },
    });
  }

  /**
   * Create Tag-Based Cost Anomaly Monitor
   * 
   * This monitor provides granular control over cost anomaly detection
   * by focusing on specific environments based on resource tagging.
   */
  private createTagMonitor(environmentTagValues: string[]): ce.CfnAnomalyDetector {
    return new ce.CfnAnomalyDetector(this, 'TagMonitor', {
      anomalyDetectorName: 'Environment-Tag-Monitor',
      monitorType: 'CUSTOM',
      monitorSpecification: {
        tags: {
          key: 'Environment',
          values: environmentTagValues,
          matchOptions: ['EQUALS'],
        },
      },
    });
  }

  /**
   * Create Daily Summary Alert Subscription
   * 
   * Provides consolidated anomaly reports sent daily to email,
   * reducing notification fatigue while ensuring comprehensive visibility.
   */
  private createDailySummarySubscription(monitors: ce.CfnAnomalyDetector[], email: string, threshold: number): ce.CfnAnomalySubscription {
    return new ce.CfnAnomalySubscription(this, 'DailySummarySubscription', {
      subscriptionName: 'Daily-Cost-Summary',
      frequency: 'DAILY',
      monitorArnList: monitors.map(monitor => monitor.ref),
      subscribers: [
        {
          address: email,
          type: 'EMAIL',
        },
      ],
      thresholdExpression: {
        and: [
          {
            dimensions: {
              key: 'ANOMALY_TOTAL_IMPACT_ABSOLUTE',
              values: [threshold.toString()],
              matchOptions: ['GREATER_THAN_OR_EQUAL'],
            },
          },
        ],
      },
    });
  }

  /**
   * Create Individual Alert Subscription
   * 
   * Provides immediate notifications via SNS as soon as anomalies are detected,
   * enabling rapid response to cost spikes.
   */
  private createIndividualAlertSubscription(monitors: ce.CfnAnomalyDetector[], topicArn: string, threshold: number): ce.CfnAnomalySubscription {
    return new ce.CfnAnomalySubscription(this, 'IndividualAlertSubscription', {
      subscriptionName: 'Individual-Cost-Alerts',
      frequency: 'IMMEDIATE',
      monitorArnList: monitors.map(monitor => monitor.ref),
      subscribers: [
        {
          address: topicArn,
          type: 'SNS',
        },
      ],
      thresholdExpression: {
        and: [
          {
            dimensions: {
              key: 'ANOMALY_TOTAL_IMPACT_ABSOLUTE',
              values: [threshold.toString()],
              matchOptions: ['GREATER_THAN_OR_EQUAL'],
            },
          },
        ],
      },
    });
  }

  /**
   * Create Lambda function for automated anomaly processing
   * 
   * This function processes cost anomaly events from EventBridge,
   * analyzes severity, and provides structured logging for analysis.
   */
  private createAnomalyProcessorFunction(): lambda.Function {
    // Create CloudWatch log group with appropriate retention
    const logGroup = new logs.LogGroup(this, 'AnomalyProcessorLogGroup', {
      logGroupName: '/aws/lambda/cost-anomaly-processor',
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create IAM role for Lambda function
    const lambdaRole = new iam.Role(this, 'AnomalyProcessorRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'IAM role for Cost Anomaly Processor Lambda function',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        CloudWatchLogsPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents',
              ],
              resources: [
                logGroup.logGroupArn,
                `${logGroup.logGroupArn}:*`,
              ],
            }),
          ],
        }),
      },
    });

    // Create Lambda function
    const anomalyProcessor = new lambda.Function(this, 'AnomalyProcessor', {
      functionName: 'cost-anomaly-processor',
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: cdk.Duration.minutes(1),
      description: 'Process cost anomaly detection events and take automated actions',
      environment: {
        LOG_LEVEL: 'INFO',
      },
      logGroup,
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
import os
from datetime import datetime

# Configure logging
log_level = os.environ.get('LOG_LEVEL', 'INFO')
logger = logging.getLogger()
logger.setLevel(getattr(logging, log_level))

def lambda_handler(event, context):
    """Process cost anomaly detection events and take automated actions"""
    
    try:
        # Log the incoming event
        logger.info(f"Received cost anomaly event: {json.dumps(event)}")
        
        # Extract anomaly details
        detail = event.get('detail', {})
        anomaly_score = detail.get('anomalyScore', 0)
        impact = detail.get('impact', {})
        total_impact = impact.get('totalImpact', 0)
        
        # Determine severity level
        if total_impact > 500:
            severity = "HIGH"
        elif total_impact > 100:
            severity = "MEDIUM"
        else:
            severity = "LOW"
        
        # Log anomaly details
        logger.info(f"Anomaly detected - Score: {anomaly_score}, Impact: ${total_impact}, Severity: {severity}")
        
        # Create structured log entry for analysis
        structured_log = {
            "timestamp": datetime.now().isoformat(),
            "anomaly_score": anomaly_score,
            "total_impact": total_impact,
            "severity": severity,
            "event_detail": detail
        }
        
        # Log structured data for CloudWatch Insights
        print(f"ANOMALY_STRUCTURED_DATA: {json.dumps(structured_log)}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Cost anomaly processed successfully',
                'severity': severity,
                'impact': total_impact
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing cost anomaly: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': 'Error processing cost anomaly',
                'error': str(e)
            })
        }
`),
    });

    return anomalyProcessor;
  }

  /**
   * Create EventBridge rule for cost anomaly events
   * 
   * This rule captures cost anomaly events and triggers the Lambda function
   * for automated processing and response.
   */
  private createEventBridgeRule(lambdaFunction: lambda.Function): events.Rule {
    const rule = new events.Rule(this, 'CostAnomalyRule', {
      ruleName: 'cost-anomaly-detection-rule',
      description: 'Capture AWS Cost Anomaly Detection events',
      eventPattern: {
        source: ['aws.ce'],
        detailType: ['Cost Anomaly Detection'],
      },
    });

    // Add Lambda function as target
    rule.addTarget(new eventsTargets.LambdaFunction(lambdaFunction));

    return rule;
  }

  /**
   * Create CloudWatch Dashboard for cost anomaly monitoring
   * 
   * Provides centralized visualization of cost anomaly patterns and trends.
   */
  private createCloudWatchDashboard(lambdaFunction: lambda.Function): cloudwatch.Dashboard {
    const dashboard = new cloudwatch.Dashboard(this, 'CostAnomalyDashboard', {
      dashboardName: 'Cost-Anomaly-Detection-Dashboard',
    });

    // Add widgets for high impact anomalies
    dashboard.addWidgets(
      new cloudwatch.LogQueryWidget({
        title: 'High Impact Cost Anomalies',
        logGroups: [lambdaFunction.logGroup!],
        queryLines: [
          'fields @timestamp, severity, total_impact, anomaly_score',
          'filter severity = "HIGH"',
          'sort @timestamp desc',
          'limit 20',
        ],
        width: 24,
        height: 6,
      })
    );

    // Add widgets for anomaly count by severity
    dashboard.addWidgets(
      new cloudwatch.LogQueryWidget({
        title: 'Anomaly Count by Severity',
        logGroups: [lambdaFunction.logGroup!],
        queryLines: [
          'fields @timestamp, severity, total_impact',
          'stats count() by severity',
          'sort severity desc',
        ],
        width: 12,
        height: 6,
      }),
      new cloudwatch.LogQueryWidget({
        title: 'Recent Anomaly Trends',
        logGroups: [lambdaFunction.logGroup!],
        queryLines: [
          'fields @timestamp, severity, total_impact',
          'filter @timestamp > now() - 7d',
          'stats count() by bin(5m)',
        ],
        width: 12,
        height: 6,
      })
    );

    return dashboard;
  }
}

/**
 * CDK Application for AWS Cost Anomaly Detection
 * 
 * This application creates a comprehensive cost anomaly detection solution
 * with automated monitoring, alerting, and response capabilities.
 */
class CostAnomalyDetectionApp extends cdk.App {
  constructor() {
    super();

    // Get configuration from context or environment variables
    const notificationEmail = this.node.tryGetContext('notificationEmail') || 
                             process.env.COST_ANOMALY_EMAIL || 
                             'your-email@example.com';
    
    const dailyThreshold = parseInt(this.node.tryGetContext('dailyThreshold') || '100');
    const individualThreshold = parseInt(this.node.tryGetContext('individualThreshold') || '50');
    
    const environmentTags = this.node.tryGetContext('environmentTags') || ['Production', 'Staging'];

    // Validate email format
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(notificationEmail)) {
      throw new Error(`Invalid email format: ${notificationEmail}`);
    }

    // Create the main stack
    const stack = new CostAnomalyDetectionStack(this, 'CostAnomalyDetectionStack', {
      description: 'AWS CDK Stack for Cost Anomaly Detection with automated monitoring and alerting',
      notificationEmail,
      dailySummaryThreshold: dailyThreshold,
      individualAlertThreshold: individualThreshold,
      environmentTagValues: environmentTags,
      env: {
        account: process.env.CDK_DEFAULT_ACCOUNT,
        region: process.env.CDK_DEFAULT_REGION,
      },
    });

    // Add stack-level tags
    cdk.Tags.of(stack).add('Project', 'CostAnomalyDetection');
    cdk.Tags.of(stack).add('Owner', 'FinanceOps');
    cdk.Tags.of(stack).add('DeployedBy', 'CDK');
  }
}

// Create and run the application
const app = new CostAnomalyDetectionApp();