#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as subs from 'aws-cdk-lib/aws-sns-subscriptions';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as path from 'path';

/**
 * Props for the LogAnalyticsStack
 */
export interface LogAnalyticsStackProps extends cdk.StackProps {
  /** Email address to receive notifications */
  readonly notificationEmail: string;
  /** Name prefix for resources */
  readonly resourcePrefix?: string;
  /** Log retention period in days */
  readonly logRetentionDays?: logs.RetentionDays;
  /** Analysis schedule expression */
  readonly scheduleExpression?: string;
}

/**
 * Stack for deploying CloudWatch Logs Insights analytics solution
 * 
 * This stack creates:
 * - CloudWatch Log Group for centralized logging
 * - Lambda function for automated log analysis
 * - SNS topic for alert notifications
 * - EventBridge rule for scheduled analysis
 * - IAM roles and policies with least privilege
 */
export class LogAnalyticsStack extends cdk.Stack {
  public readonly logGroup: logs.LogGroup;
  public readonly analyticsFunction: lambda.Function;
  public readonly alertTopic: sns.Topic;

  constructor(scope: Construct, id: string, props: LogAnalyticsStackProps) {
    super(scope, id, props);

    const resourcePrefix = props.resourcePrefix || 'log-analytics';
    const logRetentionDays = props.logRetentionDays || logs.RetentionDays.ONE_MONTH;
    const scheduleExpression = props.scheduleExpression || 'rate(5 minutes)';

    // Create CloudWatch Log Group for centralized logging
    this.logGroup = new logs.LogGroup(this, 'LogGroup', {
      logGroupName: `/aws/lambda/${resourcePrefix}`,
      retention: logRetentionDays,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
    });

    // Create SNS Topic for alert notifications
    this.alertTopic = new sns.Topic(this, 'AlertTopic', {
      topicName: `${resourcePrefix}-alerts`,
      displayName: 'Log Analytics Alerts',
    });

    // Subscribe email to SNS topic
    this.alertTopic.addSubscription(
      new subs.EmailSubscription(props.notificationEmail)
    );

    // Create IAM role for Lambda function
    const lambdaRole = new iam.Role(this, 'LambdaRole', {
      roleName: `${resourcePrefix}-lambda-role`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
    });

    // Add CloudWatch Logs Insights permissions
    lambdaRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'logs:StartQuery',
          'logs:GetQueryResults',
          'logs:DescribeLogGroups',
          'logs:DescribeLogStreams',
        ],
        resources: ['*'], // CloudWatch Logs Insights requires broad permissions
      })
    );

    // Add SNS publish permissions
    this.alertTopic.grantPublish(lambdaRole);

    // Create Lambda function for automated log analysis
    this.analyticsFunction = new lambda.Function(this, 'AnalyticsFunction', {
      functionName: `${resourcePrefix}-processor`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: cdk.Duration.seconds(60),
      environment: {
        LOG_GROUP_NAME: this.logGroup.logGroupName,
        SNS_TOPIC_ARN: this.alertTopic.topicArn,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import time
from datetime import datetime, timedelta
import os

def lambda_handler(event, context):
    """
    Lambda handler for automated log analysis using CloudWatch Logs Insights
    
    This function:
    1. Queries CloudWatch Logs for errors in the last hour
    2. Sends SNS alerts if errors are detected
    3. Returns execution results
    """
    
    logs_client = boto3.client('logs')
    sns_client = boto3.client('sns')
    
    log_group_name = os.environ['LOG_GROUP_NAME']
    sns_topic_arn = os.environ['SNS_TOPIC_ARN']
    
    # Define time range for analysis (last hour)
    end_time = int(time.time())
    start_time = end_time - 3600  # 1 hour ago
    
    # CloudWatch Logs Insights query for error detection
    error_query = '''
    fields @timestamp, @message
    | filter @message like /ERROR/
    | stats count() as error_count
    '''
    
    # Additional query for performance analysis
    performance_query = '''
    fields @timestamp, @message
    | filter @message like /API Request/
    | parse @message "* - * - *ms" as method, status, response_time
    | stats avg(response_time) as avg_response_time, max(response_time) as max_response_time
    '''
    
    try:
        # Execute error detection query
        error_results = execute_logs_insights_query(
            logs_client, log_group_name, start_time, end_time, error_query
        )
        
        # Execute performance analysis query
        performance_results = execute_logs_insights_query(
            logs_client, log_group_name, start_time, end_time, performance_query
        )
        
        # Process results and send alerts if necessary
        alerts_sent = process_analysis_results(
            sns_client, sns_topic_arn, error_results, performance_results
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Log analysis completed successfully',
                'error_results': error_results,
                'performance_results': performance_results,
                'alerts_sent': alerts_sent,
                'timestamp': datetime.now().isoformat()
            })
        }
        
    except Exception as e:
        print(f"Error during log analysis: {str(e)}")
        
        # Send error notification
        try:
            sns_client.publish(
                TopicArn=sns_topic_arn,
                Message=f"Log analysis failed: {str(e)}",
                Subject='Log Analytics Error'
            )
        except Exception as sns_error:
            print(f"Failed to send error notification: {str(sns_error)}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'timestamp': datetime.now().isoformat()
            })
        }

def execute_logs_insights_query(logs_client, log_group_name, start_time, end_time, query):
    """
    Execute a CloudWatch Logs Insights query and return results
    """
    try:
        # Start the query
        response = logs_client.start_query(
            logGroupName=log_group_name,
            startTime=start_time,
            endTime=end_time,
            queryString=query
        )
        
        query_id = response['queryId']
        
        # Wait for query completion (max 30 seconds)
        max_attempts = 30
        attempts = 0
        
        while attempts < max_attempts:
            result = logs_client.get_query_results(queryId=query_id)
            
            if result['status'] == 'Complete':
                return result['results']
            elif result['status'] == 'Failed':
                raise Exception(f"Query failed: {result.get('statusMessage', 'Unknown error')}")
            
            time.sleep(1)
            attempts += 1
        
        raise Exception("Query timed out after 30 seconds")
        
    except Exception as e:
        print(f"Error executing query: {str(e)}")
        return []

def process_analysis_results(sns_client, sns_topic_arn, error_results, performance_results):
    """
    Process analysis results and send alerts if thresholds are exceeded
    """
    alerts_sent = []
    
    try:
        # Check error count
        if error_results and len(error_results) > 0:
            error_count = int(error_results[0][0]['value']) if error_results[0] else 0
            
            if error_count > 0:
                message = f"Alert: {error_count} errors detected in the last hour"
                
                sns_client.publish(
                    TopicArn=sns_topic_arn,
                    Message=message,
                    Subject='Log Analytics Alert - Errors Detected'
                )
                
                alerts_sent.append(f"Error alert sent: {error_count} errors")
        
        # Check performance metrics
        if performance_results and len(performance_results) > 0:
            if performance_results[0]:
                avg_response_time = float(performance_results[0][0]['value']) if performance_results[0][0]['value'] else 0
                max_response_time = float(performance_results[0][1]['value']) if len(performance_results[0]) > 1 and performance_results[0][1]['value'] else 0
                
                # Alert if average response time exceeds 100ms
                if avg_response_time > 100:
                    message = f"Performance Alert: Average response time is {avg_response_time:.2f}ms (threshold: 100ms)"
                    
                    sns_client.publish(
                        TopicArn=sns_topic_arn,
                        Message=message,
                        Subject='Log Analytics Alert - Performance Issue'
                    )
                    
                    alerts_sent.append(f"Performance alert sent: {avg_response_time:.2f}ms avg")
        
        return alerts_sent
        
    except Exception as e:
        print(f"Error processing results: {str(e)}")
        return []
`),
    });

    // Create EventBridge rule for scheduled analysis
    const scheduledRule = new events.Rule(this, 'ScheduledAnalysis', {
      ruleName: `${resourcePrefix}-schedule`,
      description: 'Automated log analysis schedule',
      schedule: events.Schedule.expression(scheduleExpression),
    });

    // Add Lambda function as target for the rule
    scheduledRule.addTarget(new targets.LambdaFunction(this.analyticsFunction));

    // Create sample log data for demonstration
    const sampleDataFunction = new lambda.Function(this, 'SampleDataFunction', {
      functionName: `${resourcePrefix}-sample-data`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      timeout: cdk.Duration.seconds(30),
      environment: {
        LOG_GROUP_NAME: this.logGroup.logGroupName,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import time
import random
import os
from datetime import datetime

def lambda_handler(event, context):
    """
    Generate sample log data for demonstration purposes
    """
    
    logs_client = boto3.client('logs')
    log_group_name = os.environ['LOG_GROUP_NAME']
    log_stream_name = f"api-server-{random.randint(1, 999):03d}"
    
    # Create log stream
    try:
        logs_client.create_log_stream(
            logGroupName=log_group_name,
            logStreamName=log_stream_name
        )
    except logs_client.exceptions.ResourceAlreadyExistsException:
        pass  # Stream already exists
    
    # Generate sample log events
    current_time = int(time.time() * 1000)
    
    sample_events = [
        {
            'timestamp': current_time,
            'message': '[INFO] API Request: GET /users/123 - 200 - 45ms'
        },
        {
            'timestamp': current_time + 1000,
            'message': '[ERROR] Database connection failed - Connection timeout'
        },
        {
            'timestamp': current_time + 2000,
            'message': '[INFO] API Request: POST /orders - 201 - 120ms'
        },
        {
            'timestamp': current_time + 3000,
            'message': '[WARN] High memory usage detected: 85%'
        },
        {
            'timestamp': current_time + 4000,
            'message': '[INFO] API Request: GET /products - 200 - 32ms'
        },
        {
            'timestamp': current_time + 5000,
            'message': '[ERROR] API rate limit exceeded for user 456'
        },
        {
            'timestamp': current_time + 6000,
            'message': '[INFO] API Request: DELETE /cache - 204 - 15ms'
        }
    ]
    
    # Send log events
    logs_client.put_log_events(
        logGroupName=log_group_name,
        logStreamName=log_stream_name,
        logEvents=sample_events
    )
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Sample log data generated successfully',
            'log_stream': log_stream_name,
            'events_count': len(sample_events)
        })
    }
`),
    });

    // Grant permissions for sample data function to write logs
    this.logGroup.grantWrite(sampleDataFunction);

    // Stack outputs
    new cdk.CfnOutput(this, 'LogGroupName', {
      value: this.logGroup.logGroupName,
      description: 'CloudWatch Log Group name for centralized logging',
    });

    new cdk.CfnOutput(this, 'AnalyticsFunctionName', {
      value: this.analyticsFunction.functionName,
      description: 'Lambda function name for log analysis',
    });

    new cdk.CfnOutput(this, 'SampleDataFunctionName', {
      value: sampleDataFunction.functionName,
      description: 'Lambda function name for generating sample data',
    });

    new cdk.CfnOutput(this, 'AlertTopicArn', {
      value: this.alertTopic.topicArn,
      description: 'SNS topic ARN for receiving alerts',
    });

    new cdk.CfnOutput(this, 'ScheduledRuleName', {
      value: scheduledRule.ruleName,
      description: 'EventBridge rule name for scheduled analysis',
    });

    // CloudWatch Logs Insights query examples
    new cdk.CfnOutput(this, 'SampleQuery1', {
      value: 'fields @timestamp, @message | filter @message like /ERROR/ | stats count() as error_count',
      description: 'Sample CloudWatch Logs Insights query for error detection',
    });

    new cdk.CfnOutput(this, 'SampleQuery2', {
      value: 'fields @timestamp, @message | filter @message like /API Request/ | parse @message "* - * - *ms" as method, status, response_time | stats avg(response_time) as avg_response_time',
      description: 'Sample CloudWatch Logs Insights query for performance analysis',
    });

    // Add tags to all resources
    cdk.Tags.of(this).add('Project', 'LogAnalytics');
    cdk.Tags.of(this).add('Environment', 'Demo');
    cdk.Tags.of(this).add('CreatedBy', 'CDK');
  }
}

// CDK App
const app = new cdk.App();

// Get configuration from context or environment variables
const notificationEmail = app.node.tryGetContext('notificationEmail') || process.env.NOTIFICATION_EMAIL || 'admin@example.com';
const resourcePrefix = app.node.tryGetContext('resourcePrefix') || process.env.RESOURCE_PREFIX || 'log-analytics';
const environment = app.node.tryGetContext('environment') || process.env.ENVIRONMENT || 'dev';

// Create stack
new LogAnalyticsStack(app, 'LogAnalyticsStack', {
  notificationEmail,
  resourcePrefix: `${resourcePrefix}-${environment}`,
  logRetentionDays: logs.RetentionDays.ONE_MONTH,
  scheduleExpression: 'rate(5 minutes)',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'CloudWatch Logs Insights analytics solution with automated monitoring and alerting',
});