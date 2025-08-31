#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as events from 'aws-cdk-lib/aws-events';
import * as eventsTargets from 'aws-cdk-lib/aws-events-targets';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';
import { Duration, RemovalPolicy, Tags } from 'aws-cdk-lib';

/**
 * Configuration interface for the Simple Log Analysis Stack
 */
export interface SimpleLogAnalysisStackProps extends cdk.StackProps {
  /**
   * Environment stage (e.g., dev, prod)
   */
  readonly stage?: string;
  
  /**
   * Email address for SNS notifications
   */
  readonly notificationEmail?: string;
  
  /**
   * Log retention period in days
   */
  readonly logRetentionDays?: logs.RetentionDays;
  
  /**
   * Analysis schedule rate (in minutes)
   */
  readonly analysisIntervalMinutes?: number;
}

/**
 * CDK Stack for Simple Log Analysis with CloudWatch Insights and SNS
 * 
 * This stack creates:
 * - CloudWatch Log Group for application logs
 * - Lambda function for log analysis using CloudWatch Logs Insights
 * - SNS topic for notifications
 * - EventBridge rule for scheduled execution
 * - IAM roles with least privilege permissions
 */
export class SimpleLogAnalysisStack extends cdk.Stack {
  /**
   * The SNS topic for notifications
   */
  public readonly notificationTopic: sns.Topic;
  
  /**
   * The CloudWatch log group for application logs
   */
  public readonly applicationLogGroup: logs.LogGroup;
  
  /**
   * The Lambda function for log analysis
   */
  public readonly logAnalyzerFunction: lambda.Function;

  constructor(scope: Construct, id: string, props: SimpleLogAnalysisStackProps = {}) {
    super(scope, id, props);

    // Configuration with defaults
    const stage = props.stage ?? 'dev';
    const logRetentionDays = props.logRetentionDays ?? logs.RetentionDays.ONE_WEEK;
    const analysisIntervalMinutes = props.analysisIntervalMinutes ?? 5;

    // Generate unique suffix for resource names
    const uniqueSuffix = this.node.addr.slice(-6);

    // Create CloudWatch Log Group for application logs
    this.applicationLogGroup = this.createApplicationLogGroup(stage, uniqueSuffix, logRetentionDays);

    // Create sample log streams and events for demonstration
    this.createSampleLogData();

    // Create SNS topic for notifications
    this.notificationTopic = this.createNotificationTopic(stage, uniqueSuffix);

    // Subscribe email if provided
    if (props.notificationEmail) {
      this.subscribeEmailToTopic(props.notificationEmail);
    }

    // Create Lambda function for log analysis
    this.logAnalyzerFunction = this.createLogAnalyzerFunction(stage, uniqueSuffix);

    // Create EventBridge rule for scheduled execution
    this.createScheduledAnalysisRule(analysisIntervalMinutes, stage, uniqueSuffix);

    // Add tags to all resources
    this.addResourceTags(stage);

    // Output important resource information
    this.createOutputs(stage);
  }

  /**
   * Creates CloudWatch Log Group for application logs
   */
  private createApplicationLogGroup(stage: string, suffix: string, retention: logs.RetentionDays): logs.LogGroup {
    const logGroup = new logs.LogGroup(this, 'ApplicationLogGroup', {
      logGroupName: `/aws/lambda/demo-app-${stage}-${suffix}`,
      retention: retention,
      removalPolicy: RemovalPolicy.DESTROY, // Use RETAIN for production
    });

    // Enable log insights query optimization
    Tags.of(logGroup).add('Purpose', 'LogAnalysis');
    Tags.of(logGroup).add('Component', 'ApplicationLogs');

    return logGroup;
  }

  /**
   * Creates sample log data for demonstration purposes
   */
  private createSampleLogData(): void {
    // Note: In CDK, we can't directly create log events
    // This would need to be done post-deployment via CLI or separate process
    // Adding custom resource for log data creation would be complex
    // Instead, we'll document this in the deployment instructions
  }

  /**
   * Creates SNS topic for log analysis notifications
   */
  private createNotificationTopic(stage: string, suffix: string): sns.Topic {
    const topic = new sns.Topic(this, 'LogAnalysisNotificationTopic', {
      topicName: `log-analysis-alerts-${stage}-${suffix}`,
      displayName: `Log Analysis Alerts - ${stage.toUpperCase()}`,
    });

    // Add tags for better organization
    Tags.of(topic).add('Purpose', 'LogAnalysisAlerts');
    Tags.of(topic).add('Component', 'Notifications');

    return topic;
  }

  /**
   * Subscribes email address to SNS topic
   */
  private subscribeEmailToTopic(email: string): void {
    this.notificationTopic.addSubscription(
      new snsSubscriptions.EmailSubscription(email)
    );
  }

  /**
   * Creates Lambda function for log analysis using CloudWatch Logs Insights
   */
  private createLogAnalyzerFunction(stage: string, suffix: string): lambda.Function {
    // Create IAM role with minimal required permissions
    const executionRole = new iam.Role(this, 'LogAnalyzerExecutionRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      roleName: `log-analyzer-role-${stage}-${suffix}`,
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
    });

    // Add CloudWatch Logs permissions for Insights queries
    executionRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'logs:StartQuery',
        'logs:GetQueryResults',
        'logs:StopQuery',
        'logs:DescribeLogGroups',
        'logs:DescribeLogStreams',
      ],
      resources: ['*'], // Logs Insights requires wildcard permissions
    }));

    // Grant SNS publish permissions
    this.notificationTopic.grantPublish(executionRole);

    // Create Lambda function
    const logAnalyzerFunction = new lambda.Function(this, 'LogAnalyzerFunction', {
      functionName: `log-analyzer-${stage}-${suffix}`,
      runtime: lambda.Runtime.PYTHON_3_12,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(this.getLambdaCode()),
      role: executionRole,
      timeout: Duration.seconds(60),
      memorySize: 256,
      environment: {
        LOG_GROUP_NAME: this.applicationLogGroup.logGroupName,
        SNS_TOPIC_ARN: this.notificationTopic.topicArn,
        LOG_LEVEL: 'INFO',
      },
      description: 'Analyzes CloudWatch logs for error patterns and sends SNS notifications',
    });

    // Add tags
    Tags.of(logAnalyzerFunction).add('Purpose', 'LogAnalysis');
    Tags.of(logAnalyzerFunction).add('Component', 'ProcessingFunction');

    return logAnalyzerFunction;
  }

  /**
   * Creates EventBridge rule for scheduled log analysis
   */
  private createScheduledAnalysisRule(intervalMinutes: number, stage: string, suffix: string): void {
    const rule = new events.Rule(this, 'LogAnalysisScheduleRule', {
      ruleName: `log-analysis-schedule-${stage}-${suffix}`,
      description: `Triggers log analysis every ${intervalMinutes} minutes`,
      schedule: events.Schedule.rate(Duration.minutes(intervalMinutes)),
      enabled: true,
    });

    // Add Lambda function as target with error handling
    rule.addTarget(new eventsTargets.LambdaFunction(this.logAnalyzerFunction, {
      retryAttempts: 2,
      maxEventAge: Duration.hours(2),
    }));

    // Add tags
    Tags.of(rule).add('Purpose', 'LogAnalysisScheduling');
    Tags.of(rule).add('Component', 'EventBridge');
  }

  /**
   * Adds consistent tags to all resources
   */
  private addResourceTags(stage: string): void {
    Tags.of(this).add('Project', 'SimpleLogAnalysis');
    Tags.of(this).add('Environment', stage);
    Tags.of(this).add('ManagedBy', 'CDK');
    Tags.of(this).add('Recipe', 'simple-log-analysis-insights-sns');
  }

  /**
   * Creates CloudFormation outputs for important resources
   */
  private createOutputs(stage: string): void {
    new cdk.CfnOutput(this, 'ApplicationLogGroupName', {
      value: this.applicationLogGroup.logGroupName,
      description: 'CloudWatch Log Group name for application logs',
      exportName: `SimpleLogAnalysis-${stage}-LogGroupName`,
    });

    new cdk.CfnOutput(this, 'NotificationTopicArn', {
      value: this.notificationTopic.topicArn,
      description: 'SNS Topic ARN for log analysis notifications',
      exportName: `SimpleLogAnalysis-${stage}-TopicArn`,
    });

    new cdk.CfnOutput(this, 'LogAnalyzerFunctionName', {
      value: this.logAnalyzerFunction.functionName,
      description: 'Lambda function name for log analysis',
      exportName: `SimpleLogAnalysis-${stage}-FunctionName`,
    });

    new cdk.CfnOutput(this, 'LogAnalyzerFunctionArn', {
      value: this.logAnalyzerFunction.functionArn,
      description: 'Lambda function ARN for log analysis',
      exportName: `SimpleLogAnalysis-${stage}-FunctionArn`,
    });
  }

  /**
   * Returns the Lambda function code for log analysis
   */
  private getLambdaCode(): string {
    return `
import json
import boto3
import time
import os
from datetime import datetime, timedelta
from typing import Dict, List, Any, Optional

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda function to analyze CloudWatch logs for error patterns and send SNS notifications.
    
    Args:
        event: EventBridge event (unused in this case)
        context: Lambda runtime context
        
    Returns:
        Response with status and error count
    """
    # Initialize AWS clients
    logs_client = boto3.client('logs')
    sns_client = boto3.client('sns')
    
    # Get environment variables
    log_group = os.environ['LOG_GROUP_NAME']
    sns_topic = os.environ['SNS_TOPIC_ARN']
    log_level = os.environ.get('LOG_LEVEL', 'INFO')
    
    try:
        # Define time range for analysis (last 10 minutes)
        end_time = datetime.now()
        start_time = end_time - timedelta(minutes=10)
        
        if log_level == 'DEBUG':
            print(f"Analyzing logs from {start_time} to {end_time}")
            print(f"Log group: {log_group}")
        
        # CloudWatch Logs Insights query for error patterns
        query = '''
        fields @timestamp, @message
        | filter @message like /ERROR|CRITICAL|FATAL/
        | sort @timestamp desc
        | limit 100
        '''
        
        # Start the query
        print(f"Starting CloudWatch Logs Insights query...")
        response = logs_client.start_query(
            logGroupName=log_group,
            startTime=int(start_time.timestamp()),
            endTime=int(end_time.timestamp()),
            queryString=query
        )
        
        query_id = response['queryId']
        print(f"Query started with ID: {query_id}")
        
        # Wait for query completion with timeout
        max_wait_time = 30  # seconds
        wait_time = 0
        while wait_time < max_wait_time:
            time.sleep(2)
            wait_time += 2
            
            result = logs_client.get_query_results(queryId=query_id)
            
            if result['status'] == 'Complete':
                break
            elif result['status'] == 'Failed':
                raise Exception(f"Query failed: {result.get('statusMessage', 'Unknown error')}")
        
        if wait_time >= max_wait_time:
            raise Exception("Query timeout - analysis took too long")
        
        # Process results
        error_count = len(result['results'])
        print(f"Found {error_count} error/critical log entries")
        
        if error_count > 0:
            # Format alert message
            alert_message = format_alert_message(log_group, error_count, result['results'][:5])
            
            # Send SNS notification
            print("Sending SNS notification...")
            sns_response = sns_client.publish(
                TopicArn=sns_topic,
                Subject=f'🚨 CloudWatch Log Analysis Alert - {error_count} Errors Detected',
                Message=alert_message
            )
            
            print(f"Alert sent successfully. Message ID: {sns_response['MessageId']}")
        else:
            print("No errors detected in recent logs - no notification sent")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'error_count': error_count,
                'status': 'success',
                'analysis_period_minutes': 10,
                'log_group': log_group
            }, default=str)
        }
        
    except Exception as e:
        error_message = f"Error analyzing logs: {str(e)}"
        print(error_message)
        
        # Send error notification
        try:
            sns_client.publish(
                TopicArn=sns_topic,
                Subject='❌ Log Analysis Function Error',
                Message=f"""
Log Analysis Function Error

Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC')}
Error: {str(e)}
Log Group: {log_group}

Please check the Lambda function logs for more details.
"""
            )
        except Exception as sns_error:
            print(f"Failed to send error notification: {str(sns_error)}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'status': 'error',
                'log_group': log_group
            }, default=str)
        }

def format_alert_message(log_group: str, error_count: int, log_entries: List[List[Dict[str, str]]]) -> str:
    """
    Formats the alert message for SNS notification.
    
    Args:
        log_group: CloudWatch log group name
        error_count: Number of errors found
        log_entries: List of log entry dictionaries
        
    Returns:
        Formatted alert message string
    """
    alert_message = f"""🚨 CloudWatch Log Analysis Alert

Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC')}
Log Group: {log_group}
Error Count: {error_count} errors found in the last 10 minutes

Recent Error Entries:
"""
    
    for i, log_entry in enumerate(log_entries, 1):
        try:
            # Extract timestamp and message from the log entry
            timestamp = next((field['value'] for field in log_entry if field['field'] == '@timestamp'), 'N/A')
            message = next((field['value'] for field in log_entry if field['field'] == '@message'), 'N/A')
            
            # Truncate long messages
            if len(message) > 200:
                message = message[:200] + "..."
            
            alert_message += f"\\n{i}. {timestamp}\\n   {message}\\n"
            
        except Exception as e:
            alert_message += f"\\n{i}. Error parsing log entry: {str(e)}\\n"
    
    alert_message += f"""
\\n📊 Analysis Details:
• Query Period: Last 10 minutes
• Pattern: ERROR, CRITICAL, or FATAL messages
• Total Matches: {error_count}

🔗 View logs in CloudWatch Console:
https://console.aws.amazon.com/cloudwatch/home#logsV2:log-groups/log-group/{log_group.replace('/', '$252F')}

This is an automated alert from your log monitoring system.
"""
    
    return alert_message
`;
  }
}

// CDK App
const app = new cdk.App();

// Get configuration from CDK context or environment variables
const stage = app.node.tryGetContext('stage') || process.env.STAGE || 'dev';
const notificationEmail = app.node.tryGetContext('notificationEmail') || process.env.NOTIFICATION_EMAIL;
const analysisInterval = parseInt(app.node.tryGetContext('analysisInterval') || process.env.ANALYSIS_INTERVAL || '5');

new SimpleLogAnalysisStack(app, `SimpleLogAnalysisStack-${stage}`, {
  stage,
  notificationEmail,
  analysisIntervalMinutes: analysisInterval,
  logRetentionDays: logs.RetentionDays.ONE_WEEK,
  
  // Stack configuration
  description: 'Simple Log Analysis with CloudWatch Insights and SNS - CDK TypeScript Implementation',
  
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  
  tags: {
    Project: 'SimpleLogAnalysis',
    Environment: stage,
    Recipe: 'simple-log-analysis-insights-sns',
    ManagedBy: 'CDK',
  },
});

app.synth();