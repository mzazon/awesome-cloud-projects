#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as kinesis from 'aws-cdk-lib/aws-kinesis';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as sqs from 'aws-cdk-lib/aws-sqs';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as logs from 'aws-cdk-lib/aws-logs';
import { KinesisEventSource } from 'aws-cdk-lib/aws-lambda-event-sources';
import { Construct } from 'constructs';

/**
 * Configuration interface for the Real-Time Data Processing Stack
 */
interface RealTimeDataProcessingStackProps extends cdk.StackProps {
  /**
   * Number of shards for the Kinesis Data Stream
   * @default 1
   */
  readonly shardCount?: number;

  /**
   * Batch size for Lambda event source mapping
   * @default 100
   */
  readonly batchSize?: number;

  /**
   * Maximum batching window in seconds for Lambda
   * @default 5
   */
  readonly maxBatchingWindowInSeconds?: number;

  /**
   * Lambda function memory size in MB
   * @default 256
   */
  readonly lambdaMemorySize?: number;

  /**
   * Lambda function timeout in seconds
   * @default 120
   */
  readonly lambdaTimeout?: number;

  /**
   * Email address for CloudWatch alarm notifications
   * Leave empty to skip SNS setup
   */
  readonly alertEmail?: string;

  /**
   * Error threshold for CloudWatch alarm
   * @default 10
   */
  readonly errorThreshold?: number;

  /**
   * Environment prefix for resource naming
   * @default 'retail'
   */
  readonly environmentPrefix?: string;
}

/**
 * CDK Stack for Real-Time Data Processing with Amazon Kinesis and Lambda
 * 
 * This stack creates a complete serverless data processing pipeline that:
 * - Ingests high-volume event data through Kinesis Data Streams
 * - Processes events in real-time using Lambda functions
 * - Stores processed results in DynamoDB for fast access
 * - Provides error handling via Dead Letter Queue
 * - Monitors pipeline health with CloudWatch alarms
 */
export class RealTimeDataProcessingStack extends cdk.Stack {
  
  // Public properties for external access
  public readonly kinesisStream: kinesis.Stream;
  public readonly dynamoTable: dynamodb.Table;
  public readonly processorFunction: lambda.Function;
  public readonly deadLetterQueue: sqs.Queue;

  constructor(scope: Construct, id: string, props: RealTimeDataProcessingStackProps = {}) {
    super(scope, id, props);

    // Extract configuration with defaults
    const {
      shardCount = 1,
      batchSize = 100,
      maxBatchingWindowInSeconds = 5,
      lambdaMemorySize = 256,
      lambdaTimeout = 120,
      alertEmail,
      errorThreshold = 10,
      environmentPrefix = 'retail'
    } = props;

    // Generate unique suffix for resource naming
    const uniqueSuffix = this.node.addr.substring(0, 8);

    // Create Kinesis Data Stream for event ingestion
    this.kinesisStream = new kinesis.Stream(this, 'EventsStream', {
      streamName: `${environmentPrefix}-events-stream-${uniqueSuffix}`,
      shardCount: shardCount,
      retentionPeriod: cdk.Duration.days(1), // 24 hours retention
      encryption: kinesis.StreamEncryption.MANAGED,
      streamModeDetails: kinesis.StreamMode.provisioned(),
    });

    // Apply tags for cost tracking and resource management
    cdk.Tags.of(this.kinesisStream).add('Project', 'RetailAnalytics');
    cdk.Tags.of(this.kinesisStream).add('Component', 'DataIngestion');

    // Create DynamoDB table for processed events storage
    this.dynamoTable = new dynamodb.Table(this, 'EventsDataTable', {
      tableName: `${environmentPrefix}-events-data-${uniqueSuffix}`,
      partitionKey: {
        name: 'userId',
        type: dynamodb.AttributeType.STRING,
      },
      sortKey: {
        name: 'eventTimestamp',
        type: dynamodb.AttributeType.NUMBER,
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST, // On-demand scaling
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      pointInTimeRecovery: true, // Enable backup for production workloads
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
    });

    // Apply tags for cost tracking
    cdk.Tags.of(this.dynamoTable).add('Project', 'RetailAnalytics');
    cdk.Tags.of(this.dynamoTable).add('Component', 'DataStorage');

    // Create Dead Letter Queue for failed processing
    this.deadLetterQueue = new sqs.Queue(this, 'FailedEventsQueue', {
      queueName: `failed-events-dlq-${uniqueSuffix}`,
      retentionPeriod: cdk.Duration.days(14), // 14 days retention for investigation
      visibilityTimeout: cdk.Duration.seconds(30),
      encryption: sqs.QueueEncryption.SQS_MANAGED,
    });

    // Create CloudWatch Log Group for Lambda function
    const logGroup = new logs.LogGroup(this, 'ProcessorLogGroup', {
      logGroupName: `/aws/lambda/${environmentPrefix}-event-processor-${uniqueSuffix}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create Lambda function for stream processing
    this.processorFunction = new lambda.Function(this, 'EventProcessor', {
      functionName: `${environmentPrefix}-event-processor-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      memorySize: lambdaMemorySize,
      timeout: cdk.Duration.seconds(lambdaTimeout),
      logGroup: logGroup,
      tracing: lambda.Tracing.ACTIVE, // Enable X-Ray tracing
      environment: {
        DYNAMODB_TABLE: this.dynamoTable.tableName,
        DLQ_URL: this.deadLetterQueue.queueUrl,
        ENVIRONMENT: environmentPrefix,
      },
      code: lambda.Code.fromInline(`
import json
import base64
import boto3
import time
import os
import uuid
from datetime import datetime

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['DYNAMODB_TABLE'])
cloudwatch = boto3.client('cloudwatch')
sqs = boto3.client('sqs')

def process_event(event_data):
    """Process a single event and return enriched results"""
    try:
        # Extract required fields with validation
        user_id = event_data.get('userId', 'unknown')
        event_type = event_data.get('eventType', 'unknown')
        product_id = event_data.get('productId', 'unknown')
        timestamp = int(event_data.get('timestamp', int(time.time() * 1000)))
        
        # Business logic: Calculate event score based on type
        event_scores = {
            'view': 1,
            'add_to_cart': 5,
            'purchase': 10
        }
        event_score = event_scores.get(event_type, 1)
        
        # Generate business insight
        action_map = {
            'view': 'viewed',
            'add_to_cart': 'added to cart',
            'purchase': 'purchased'
        }
        action = action_map.get(event_type, 'interacted with')
        insight = f"User {user_id} {action} product {product_id}"
        
        # Create enriched data record
        processed_data = {
            'userId': user_id,
            'eventTimestamp': timestamp,
            'eventType': event_type,
            'productId': product_id,
            'eventScore': event_score,
            'insight': insight,
            'processedAt': int(time.time() * 1000),
            'recordId': str(uuid.uuid4()),
            'sessionId': event_data.get('sessionId', 'unknown'),
            'userAgent': event_data.get('userAgent', 'unknown')
        }
        
        return processed_data
        
    except Exception as e:
        raise ValueError(f"Error processing event data: {str(e)}")

def lambda_handler(event, context):
    """Main Lambda handler for processing Kinesis stream records"""
    processed_count = 0
    failed_count = 0
    
    print(f"Processing {len(event['Records'])} records")
    
    # Process each record in the batch
    for record in event['Records']:
        try:
            # Decode Kinesis data (base64 encoded)
            payload = base64.b64decode(record['kinesis']['data']).decode('utf-8')
            event_data = json.loads(payload)
            
            # Process the event data
            processed_data = process_event(event_data)
            
            # Store enriched data in DynamoDB
            table.put_item(Item=processed_data)
            
            processed_count += 1
            
        except Exception as e:
            failed_count += 1
            error_msg = f"Error processing record: {str(e)}"
            print(error_msg)
            
            # Send failed record to Dead Letter Queue
            try:
                sqs.send_message(
                    QueueUrl=os.environ['DLQ_URL'],
                    MessageBody=json.dumps({
                        'error': str(e),
                        'record': record['kinesis']['data'],
                        'timestamp': datetime.utcnow().isoformat(),
                        'sequenceNumber': record['kinesis']['sequenceNumber'],
                        'partitionKey': record['kinesis']['partitionKey']
                    })
                )
            except Exception as dlq_error:
                print(f"Failed to send to DLQ: {str(dlq_error)}")
    
    # Publish custom metrics to CloudWatch
    try:
        cloudwatch.put_metric_data(
            Namespace='RetailEventProcessing',
            MetricData=[
                {
                    'MetricName': 'ProcessedEvents',
                    'Value': processed_count,
                    'Unit': 'Count',
                    'Dimensions': [
                        {
                            'Name': 'Environment',
                            'Value': os.environ.get('ENVIRONMENT', 'unknown')
                        }
                    ]
                },
                {
                    'MetricName': 'FailedEvents',
                    'Value': failed_count,
                    'Unit': 'Count',
                    'Dimensions': [
                        {
                            'Name': 'Environment',
                            'Value': os.environ.get('ENVIRONMENT', 'unknown')
                        }
                    ]
                }
            ]
        )
    except Exception as metric_error:
        print(f"Failed to publish metrics: {str(metric_error)}")
    
    # Log processing summary
    print(f"Processing complete: {processed_count} successful, {failed_count} failed")
    
    return {
        'statusCode': 200,
        'body': {
            'processed': processed_count,
            'failed': failed_count,
            'total': processed_count + failed_count
        }
    }
`),
    });

    // Grant necessary permissions to Lambda function
    
    // DynamoDB permissions - write access to table
    this.dynamoTable.grantWriteData(this.processorFunction);
    
    // Kinesis permissions - read access to stream
    this.kinesisStream.grantRead(this.processorFunction);
    
    // SQS permissions - send messages to DLQ
    this.deadLetterQueue.grantSendMessages(this.processorFunction);
    
    // CloudWatch permissions - publish custom metrics
    this.processorFunction.addToRolePolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: ['cloudwatch:PutMetricData'],
      resources: ['*'],
    }));

    // Create event source mapping to connect Lambda to Kinesis
    this.processorFunction.addEventSource(new KinesisEventSource(this.kinesisStream, {
      batchSize: batchSize,
      maxBatchingWindow: cdk.Duration.seconds(maxBatchingWindowInSeconds),
      startingPosition: lambda.StartingPosition.LATEST,
      retryAttempts: 3,
      onFailure: new lambda.SqsDlq(this.deadLetterQueue),
    }));

    // Create CloudWatch alarm for monitoring failed events
    const failedEventsAlarm = new cloudwatch.Alarm(this, 'FailedEventsAlarm', {
      alarmName: `stream-processing-errors-${uniqueSuffix}`,
      alarmDescription: 'Alert when too many events fail processing',
      metric: new cloudwatch.Metric({
        namespace: 'RetailEventProcessing',
        metricName: 'FailedEvents',
        statistic: 'Sum',
        dimensionsMap: {
          Environment: environmentPrefix,
        },
      }),
      threshold: errorThreshold,
      evaluationPeriods: 1,
      period: cdk.Duration.minutes(1),
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Optional: Set up SNS topic and email notifications
    if (alertEmail) {
      const alertTopic = new sns.Topic(this, 'AlertTopic', {
        topicName: `retail-event-alerts-${uniqueSuffix}`,
        displayName: 'Retail Event Processing Alerts',
      });

      // Subscribe email to SNS topic
      alertTopic.addSubscription(new snsSubscriptions.EmailSubscription(alertEmail));

      // Connect alarm to SNS topic
      failedEventsAlarm.addAlarmAction(new cloudwatch.SnsAction(alertTopic));

      // Output SNS topic ARN
      new cdk.CfnOutput(this, 'AlertTopicArn', {
        value: alertTopic.topicArn,
        description: 'SNS Topic ARN for processing alerts',
        exportName: `${this.stackName}-AlertTopicArn`,
      });
    }

    // CloudFormation Outputs for external consumption
    new cdk.CfnOutput(this, 'KinesisStreamName', {
      value: this.kinesisStream.streamName,
      description: 'Name of the Kinesis Data Stream',
      exportName: `${this.stackName}-StreamName`,
    });

    new cdk.CfnOutput(this, 'KinesisStreamArn', {
      value: this.kinesisStream.streamArn,
      description: 'ARN of the Kinesis Data Stream',
      exportName: `${this.stackName}-StreamArn`,
    });

    new cdk.CfnOutput(this, 'DynamoTableName', {
      value: this.dynamoTable.tableName,
      description: 'Name of the DynamoDB table storing processed events',
      exportName: `${this.stackName}-TableName`,
    });

    new cdk.CfnOutput(this, 'DynamoTableArn', {
      value: this.dynamoTable.tableArn,
      description: 'ARN of the DynamoDB table',
      exportName: `${this.stackName}-TableArn`,
    });

    new cdk.CfnOutput(this, 'ProcessorFunctionName', {
      value: this.processorFunction.functionName,
      description: 'Name of the Lambda processor function',
      exportName: `${this.stackName}-FunctionName`,
    });

    new cdk.CfnOutput(this, 'ProcessorFunctionArn', {
      value: this.processorFunction.functionArn,
      description: 'ARN of the Lambda processor function',
      exportName: `${this.stackName}-FunctionArn`,
    });

    new cdk.CfnOutput(this, 'DeadLetterQueueUrl', {
      value: this.deadLetterQueue.queueUrl,
      description: 'URL of the Dead Letter Queue for failed events',
      exportName: `${this.stackName}-DLQUrl`,
    });

    new cdk.CfnOutput(this, 'DeadLetterQueueArn', {
      value: this.deadLetterQueue.queueArn,
      description: 'ARN of the Dead Letter Queue',
      exportName: `${this.stackName}-DLQArn`,
    });

    new cdk.CfnOutput(this, 'CloudWatchAlarmName', {
      value: failedEventsAlarm.alarmName,
      description: 'Name of the CloudWatch alarm for monitoring errors',
      exportName: `${this.stackName}-AlarmName`,
    });
  }
}

// CDK App instantiation and stack deployment
const app = new cdk.App();

// Get configuration from CDK context or environment variables
const environmentPrefix = app.node.tryGetContext('environmentPrefix') || process.env.ENVIRONMENT_PREFIX || 'retail';
const alertEmail = app.node.tryGetContext('alertEmail') || process.env.ALERT_EMAIL;
const region = app.node.tryGetContext('region') || process.env.CDK_DEFAULT_REGION || 'us-east-1';
const account = app.node.tryGetContext('account') || process.env.CDK_DEFAULT_ACCOUNT;

// Deploy the stack
new RealTimeDataProcessingStack(app, 'RealTimeDataProcessingStack', {
  env: {
    account: account,
    region: region,
  },
  description: 'Real-time data processing pipeline with Amazon Kinesis, Lambda, and DynamoDB',
  
  // Stack configuration - can be overridden via context
  environmentPrefix: environmentPrefix,
  alertEmail: alertEmail,
  shardCount: Number(app.node.tryGetContext('shardCount')) || 1,
  batchSize: Number(app.node.tryGetContext('batchSize')) || 100,
  maxBatchingWindowInSeconds: Number(app.node.tryGetContext('maxBatchingWindow')) || 5,
  lambdaMemorySize: Number(app.node.tryGetContext('lambdaMemorySize')) || 256,
  lambdaTimeout: Number(app.node.tryGetContext('lambdaTimeout')) || 120,
  errorThreshold: Number(app.node.tryGetContext('errorThreshold')) || 10,
  
  // Stack tags for resource management
  tags: {
    Project: 'RetailAnalytics',
    Environment: environmentPrefix,
    ManagedBy: 'CDK',
    Recipe: 'real-time-data-processing-kinesis-lambda',
  },
});

// Synthesize the CloudFormation template
app.synth();