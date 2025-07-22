#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as sqs from 'aws-cdk-lib/aws-sqs';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as lambdaEventSources from 'aws-cdk-lib/aws-lambda-event-sources';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * Props for the Dead Letter Queue Processing Stack
 */
interface DeadLetterQueueProcessingStackProps extends cdk.StackProps {
  /**
   * Environment prefix for resource naming
   * @default 'dlq-processing'
   */
  readonly environmentPrefix?: string;

  /**
   * Maximum number of receive attempts before sending to DLQ
   * @default 3
   */
  readonly maxReceiveCount?: number;

  /**
   * Visibility timeout for the main queue in seconds
   * @default 300
   */
  readonly visibilityTimeoutSeconds?: number;

  /**
   * Message retention period in days
   * @default 14
   */
  readonly messageRetentionDays?: number;

  /**
   * Lambda function timeout in seconds
   * @default 30
   */
  readonly lambdaTimeoutSeconds?: number;

  /**
   * Lambda memory allocation in MB
   * @default 256
   */
  readonly lambdaMemoryMB?: number;

  /**
   * Enable detailed monitoring and alarms
   * @default true
   */
  readonly enableMonitoring?: boolean;
}

/**
 * CDK Stack for Dead Letter Queue Processing with SQS
 * 
 * This stack implements a comprehensive dead letter queue processing system that:
 * - Creates a main SQS queue with DLQ configuration
 * - Deploys Lambda functions for message processing and DLQ monitoring
 * - Sets up CloudWatch alarms for error detection
 * - Provides observability through logs and metrics
 * 
 * The architecture follows AWS best practices for error handling and message processing,
 * ensuring no critical business messages are lost while providing detailed visibility
 * into failure patterns and automated recovery workflows.
 */
export class DeadLetterQueueProcessingStack extends cdk.Stack {
  public readonly mainQueue: sqs.Queue;
  public readonly deadLetterQueue: sqs.Queue;
  public readonly mainProcessorFunction: lambda.Function;
  public readonly dlqMonitorFunction: lambda.Function;

  constructor(scope: Construct, id: string, props?: DeadLetterQueueProcessingStackProps) {
    super(scope, id, props);

    // Extract configuration with defaults
    const environmentPrefix = props?.environmentPrefix ?? 'dlq-processing';
    const maxReceiveCount = props?.maxReceiveCount ?? 3;
    const visibilityTimeoutSeconds = props?.visibilityTimeoutSeconds ?? 300;
    const messageRetentionDays = props?.messageRetentionDays ?? 14;
    const lambdaTimeoutSeconds = props?.lambdaTimeoutSeconds ?? 30;
    const lambdaMemoryMB = props?.lambdaMemoryMB ?? 256;
    const enableMonitoring = props?.enableMonitoring ?? true;

    // Create the Dead Letter Queue first
    this.deadLetterQueue = new sqs.Queue(this, 'DeadLetterQueue', {
      queueName: `${environmentPrefix}-dlq`,
      visibilityTimeout: cdk.Duration.seconds(visibilityTimeoutSeconds),
      retentionPeriod: cdk.Duration.days(messageRetentionDays),
      // Enable server-side encryption for security
      encryption: sqs.QueueEncryption.SQS_MANAGED,
    });

    // Create the main processing queue with DLQ configuration
    this.mainQueue = new sqs.Queue(this, 'MainProcessingQueue', {
      queueName: `${environmentPrefix}-main`,
      visibilityTimeout: cdk.Duration.seconds(visibilityTimeoutSeconds),
      retentionPeriod: cdk.Duration.days(messageRetentionDays),
      // Configure dead letter queue with retry policy
      deadLetterQueue: {
        queue: this.deadLetterQueue,
        maxReceiveCount: maxReceiveCount,
      },
      // Enable server-side encryption for security
      encryption: sqs.QueueEncryption.SQS_MANAGED,
    });

    // Create IAM role for Lambda functions with least privilege access
    const lambdaExecutionRole = new iam.Role(this, 'LambdaExecutionRole', {
      roleName: `${environmentPrefix}-lambda-execution-role`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        SQSPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'sqs:ReceiveMessage',
                'sqs:DeleteMessage',
                'sqs:GetQueueAttributes',
                'sqs:SendMessage',
              ],
              resources: [
                this.mainQueue.queueArn,
                this.deadLetterQueue.queueArn,
              ],
            }),
          ],
        }),
        CloudWatchPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'cloudwatch:PutMetricData',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // Create the main order processing Lambda function
    this.mainProcessorFunction = new lambda.Function(this, 'MainProcessorFunction', {
      functionName: `${environmentPrefix}-order-processor`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      timeout: cdk.Duration.seconds(lambdaTimeoutSeconds),
      memorySize: lambdaMemoryMB,
      role: lambdaExecutionRole,
      logRetention: logs.RetentionDays.TWO_WEEKS,
      environment: {
        MAIN_QUEUE_URL: this.mainQueue.queueUrl,
        DLQ_URL: this.deadLetterQueue.queueUrl,
      },
      code: lambda.Code.fromInline(`
import json
import logging
import random
import boto3
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Main order processing function that simulates processing failures
    """
    for record in event['Records']:
        try:
            # Parse the message
            message_body = json.loads(record['body'])
            order_id = message_body.get('orderId')
            
            logger.info(f"Processing order: {order_id}")
            
            # Simulate processing logic with intentional failures
            # In real scenarios, this would be actual business logic
            if random.random() < 0.3:  # 30% failure rate for demo
                raise Exception(f"Processing failed for order {order_id}")
            
            # Simulate successful processing
            logger.info(f"Successfully processed order: {order_id}")
            
            # In real scenarios, you would:
            # - Validate order data
            # - Update inventory
            # - Process payment
            # - Send confirmation email
            
        except Exception as e:
            logger.error(f"Error processing message: {str(e)}")
            # Let SQS handle the retry mechanism
            raise e
    
    return {
        'statusCode': 200,
        'body': json.dumps('Processing completed')
    }
      `),
    });

    // Create the DLQ monitoring Lambda function
    this.dlqMonitorFunction = new lambda.Function(this, 'DLQMonitorFunction', {
      functionName: `${environmentPrefix}-dlq-monitor`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      timeout: cdk.Duration.seconds(60),
      memorySize: 256,
      role: lambdaExecutionRole,
      logRetention: logs.RetentionDays.TWO_WEEKS,
      environment: {
        MAIN_QUEUE_URL: this.mainQueue.queueUrl,
        DLQ_URL: this.deadLetterQueue.queueUrl,
      },
      code: lambda.Code.fromInline(`
import json
import logging
import boto3
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

sqs = boto3.client('sqs')

def lambda_handler(event, context):
    """
    Monitor and analyze messages in the dead letter queue
    """
    for record in event['Records']:
        try:
            # Parse the failed message
            message_body = json.loads(record['body'])
            receipt_handle = record['receiptHandle']
            
            # Extract error information
            order_id = message_body.get('orderId')
            error_count = int(record.get('attributes', {}).get('ApproximateReceiveCount', '1'))
            
            logger.info(f"Analyzing failed message for order: {order_id}")
            logger.info(f"Error count: {error_count}")
            
            # Categorize error types
            error_category = categorize_error(message_body)
            
            # Log detailed error information
            logger.info(f"Error category: {error_category}")
            logger.info(f"Message attributes: {record.get('messageAttributes', {})}")
            
            # Create error metrics
            cloudwatch = boto3.client('cloudwatch')
            cloudwatch.put_metric_data(
                Namespace='DLQ/Processing',
                MetricData=[
                    {
                        'MetricName': 'FailedMessages',
                        'Value': 1,
                        'Unit': 'Count',
                        'Dimensions': [
                            {
                                'Name': 'ErrorCategory',
                                'Value': error_category
                            }
                        ]
                    }
                ]
            )
            
            # Determine if message should be retried
            if should_retry(message_body, error_count):
                logger.info(f"Message will be retried for order: {order_id}")
                send_to_retry_queue(message_body)
            else:
                logger.warning(f"Message permanently failed for order: {order_id}")
                # In production, you might send to a manual review queue
                # or trigger an alert for manual investigation
                
        except Exception as e:
            logger.error(f"Error processing DLQ message: {str(e)}")
            raise e
    
    return {
        'statusCode': 200,
        'body': json.dumps('DLQ monitoring completed')
    }

def categorize_error(message_body):
    """Categorize the type of error for better analysis"""
    # In real scenarios, this would analyze the actual error
    # For demo purposes, we'll categorize based on order value
    order_value = message_body.get('orderValue', 0)
    
    if order_value > 1000:
        return 'HighValueOrder'
    elif order_value > 100:
        return 'MediumValueOrder'
    else:
        return 'LowValueOrder'

def should_retry(message_body, error_count):
    """Determine if a message should be retried"""
    # Retry logic based on error count and order characteristics
    max_retries = 2
    order_value = message_body.get('orderValue', 0)
    
    # High-value orders get more retry attempts
    if order_value > 1000:
        max_retries = 5
    
    return error_count < max_retries

def send_to_retry_queue(message_body):
    """Send message back to main queue for retry"""
    import os
    main_queue_url = os.environ.get('MAIN_QUEUE_URL')
    
    if main_queue_url:
        try:
            sqs.send_message(
                QueueUrl=main_queue_url,
                MessageBody=json.dumps(message_body),
                MessageAttributes={
                    'RetryAttempt': {
                        'StringValue': 'true',
                        'DataType': 'String'
                    }
                }
            )
            logger.info("Message sent to retry queue")
        except Exception as e:
            logger.error(f"Failed to send message to retry queue: {str(e)}")
      `),
    });

    // Configure event source mappings for automatic message processing
    this.mainProcessorFunction.addEventSource(
      new lambdaEventSources.SqsEventSource(this.mainQueue, {
        batchSize: 10,
        maxBatchingWindow: cdk.Duration.seconds(5),
        reportBatchItemFailures: true,
      })
    );

    this.dlqMonitorFunction.addEventSource(
      new lambdaEventSources.SqsEventSource(this.deadLetterQueue, {
        batchSize: 5,
        maxBatchingWindow: cdk.Duration.seconds(10),
        reportBatchItemFailures: true,
      })
    );

    // Create CloudWatch alarms for monitoring (if enabled)
    if (enableMonitoring) {
      this.createMonitoringAlarms(environmentPrefix);
    }

    // Output important resource information
    new cdk.CfnOutput(this, 'MainQueueUrl', {
      value: this.mainQueue.queueUrl,
      description: 'URL of the main processing queue',
      exportName: `${environmentPrefix}-main-queue-url`,
    });

    new cdk.CfnOutput(this, 'DeadLetterQueueUrl', {
      value: this.deadLetterQueue.queueUrl,
      description: 'URL of the dead letter queue',
      exportName: `${environmentPrefix}-dlq-url`,
    });

    new cdk.CfnOutput(this, 'MainProcessorFunctionName', {
      value: this.mainProcessorFunction.functionName,
      description: 'Name of the main processor Lambda function',
      exportName: `${environmentPrefix}-main-processor-name`,
    });

    new cdk.CfnOutput(this, 'DLQMonitorFunctionName', {
      value: this.dlqMonitorFunction.functionName,
      description: 'Name of the DLQ monitor Lambda function',
      exportName: `${environmentPrefix}-dlq-monitor-name`,
    });
  }

  /**
   * Create CloudWatch alarms for proactive monitoring
   */
  private createMonitoringAlarms(environmentPrefix: string): void {
    // Alarm for messages in DLQ
    const dlqMessageAlarm = new cloudwatch.Alarm(this, 'DLQMessageAlarm', {
      alarmName: `${environmentPrefix}-dlq-messages`,
      alarmDescription: 'Alert when messages appear in dead letter queue',
      metric: this.deadLetterQueue.metricApproximateNumberOfVisibleMessages({
        period: cdk.Duration.minutes(5),
        statistic: 'Sum',
      }),
      threshold: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Alarm for Lambda function errors
    const lambdaErrorAlarm = new cloudwatch.Alarm(this, 'LambdaErrorAlarm', {
      alarmName: `${environmentPrefix}-lambda-errors`,
      alarmDescription: 'Alert on Lambda function errors',
      metric: this.mainProcessorFunction.metricErrors({
        period: cdk.Duration.minutes(5),
        statistic: 'Sum',
      }),
      threshold: 5,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Alarm for high DLQ processing rate
    const dlqProcessingAlarm = new cloudwatch.Alarm(this, 'DLQProcessingAlarm', {
      alarmName: `${environmentPrefix}-dlq-processing-rate`,
      alarmDescription: 'Alert on high DLQ processing rate',
      metric: new cloudwatch.Metric({
        namespace: 'DLQ/Processing',
        metricName: 'FailedMessages',
        statistic: 'Sum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 10,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Tag alarms for better organization
    cdk.Tags.of(dlqMessageAlarm).add('Component', 'Monitoring');
    cdk.Tags.of(lambdaErrorAlarm).add('Component', 'Monitoring');
    cdk.Tags.of(dlqProcessingAlarm).add('Component', 'Monitoring');
  }
}

/**
 * CDK Application entry point
 */
const app = new cdk.App();

// Create the dead letter queue processing stack
new DeadLetterQueueProcessingStack(app, 'DeadLetterQueueProcessingStack', {
  description: 'Dead Letter Queue Processing with SQS - Production-ready error handling system',
  
  // Stack configuration
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  
  // Application-specific configuration
  environmentPrefix: process.env.ENVIRONMENT_PREFIX || 'dlq-processing',
  maxReceiveCount: Number(process.env.MAX_RECEIVE_COUNT) || 3,
  visibilityTimeoutSeconds: Number(process.env.VISIBILITY_TIMEOUT_SECONDS) || 300,
  messageRetentionDays: Number(process.env.MESSAGE_RETENTION_DAYS) || 14,
  lambdaTimeoutSeconds: Number(process.env.LAMBDA_TIMEOUT_SECONDS) || 30,
  lambdaMemoryMB: Number(process.env.LAMBDA_MEMORY_MB) || 256,
  enableMonitoring: process.env.ENABLE_MONITORING !== 'false',
  
  // Apply consistent tagging strategy
  tags: {
    Project: 'DeadLetterQueueProcessing',
    Environment: process.env.ENVIRONMENT || 'development',
    CostCenter: process.env.COST_CENTER || 'engineering',
    Owner: process.env.OWNER || 'platform-team',
  },
});

// Synthesize the CloudFormation template
app.synth();