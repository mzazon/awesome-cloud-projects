#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as lambdaEventSources from 'aws-cdk-lib/aws-lambda-event-sources';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as sqs from 'aws-cdk-lib/aws-sqs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as logs from 'aws-cdk-lib/aws-logs';
import { SnsAction } from 'aws-cdk-lib/aws-cloudwatch-actions';

/**
 * Properties for the RealTimeDatabaseChangeStreamsStack
 */
export interface RealTimeDatabaseChangeStreamsStackProps extends cdk.StackProps {
  /**
   * Environment prefix for resource naming
   * @default 'rtdb-streams'
   */
  readonly environmentPrefix?: string;

  /**
   * DynamoDB table read capacity units
   * @default 5
   */
  readonly tableReadCapacity?: number;

  /**
   * DynamoDB table write capacity units
   * @default 5
   */
  readonly tableWriteCapacity?: number;

  /**
   * Lambda function memory size in MB
   * @default 256
   */
  readonly lambdaMemorySize?: number;

  /**
   * Lambda function timeout in seconds
   * @default 60
   */
  readonly lambdaTimeout?: number;

  /**
   * Dead letter queue message retention period in days
   * @default 14
   */
  readonly dlqRetentionDays?: number;

  /**
   * Stream batch size for Lambda processing
   * @default 10
   */
  readonly streamBatchSize?: number;

  /**
   * Maximum batching window in seconds
   * @default 5
   */
  readonly maxBatchingWindow?: number;

  /**
   * Enable CloudWatch monitoring alarms
   * @default true
   */
  readonly enableMonitoring?: boolean;
}

/**
 * CDK Stack for Real-time Database Change Streams with DynamoDB Streams
 * 
 * This stack creates:
 * - DynamoDB table with streams enabled
 * - Lambda function to process stream events
 * - SNS topic for notifications
 * - S3 bucket for audit logging
 * - Dead letter queue for error handling
 * - CloudWatch alarms for monitoring
 */
export class RealTimeDatabaseChangeStreamsStack extends cdk.Stack {
  public readonly dynamoTable: dynamodb.Table;
  public readonly processorFunction: lambda.Function;
  public readonly notificationTopic: sns.Topic;
  public readonly auditBucket: s3.Bucket;
  public readonly deadLetterQueue: sqs.Queue;

  constructor(scope: Construct, id: string, props?: RealTimeDatabaseChangeStreamsStackProps) {
    super(scope, id, props);

    // Extract configuration with defaults
    const config = {
      environmentPrefix: props?.environmentPrefix ?? 'rtdb-streams',
      tableReadCapacity: props?.tableReadCapacity ?? 5,
      tableWriteCapacity: props?.tableWriteCapacity ?? 5,
      lambdaMemorySize: props?.lambdaMemorySize ?? 256,
      lambdaTimeout: props?.lambdaTimeout ?? 60,
      dlqRetentionDays: props?.dlqRetentionDays ?? 14,
      streamBatchSize: props?.streamBatchSize ?? 10,
      maxBatchingWindow: props?.maxBatchingWindow ?? 5,
      enableMonitoring: props?.enableMonitoring ?? true,
    };

    // Create S3 bucket for audit logging
    this.auditBucket = new s3.Bucket(this, 'AuditBucket', {
      bucketName: `${config.environmentPrefix}-audit-${this.account}-${this.region}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      versioned: true,
      lifecycleRules: [
        {
          id: 'audit-log-lifecycle',
          enabled: true,
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30),
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(90),
            },
            {
              storageClass: s3.StorageClass.DEEP_ARCHIVE,
              transitionAfter: cdk.Duration.days(365),
            },
          ],
          expiration: cdk.Duration.days(2555), // 7 years retention
        },
      ],
      removalPolicy: cdk.RemovalPolicy.RETAIN,
    });

    // Create SNS topic for notifications
    this.notificationTopic = new sns.Topic(this, 'NotificationTopic', {
      topicName: `${config.environmentPrefix}-notifications`,
      displayName: 'Real-time Database Change Notifications',
    });

    // Create Dead Letter Queue
    this.deadLetterQueue = new sqs.Queue(this, 'DeadLetterQueue', {
      queueName: `${config.environmentPrefix}-dlq`,
      messageRetentionPeriod: cdk.Duration.days(config.dlqRetentionDays),
      visibilityTimeout: cdk.Duration.seconds(300),
    });

    // Create DynamoDB table with streams enabled
    this.dynamoTable = new dynamodb.Table(this, 'UserActivitiesTable', {
      tableName: `${config.environmentPrefix}-user-activities`,
      partitionKey: {
        name: 'UserId',
        type: dynamodb.AttributeType.STRING,
      },
      sortKey: {
        name: 'ActivityId',
        type: dynamodb.AttributeType.STRING,
      },
      billingMode: dynamodb.BillingMode.PROVISIONED,
      readCapacity: config.tableReadCapacity,
      writeCapacity: config.tableWriteCapacity,
      stream: dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
      pointInTimeRecovery: true,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
    });

    // Create Lambda execution role with comprehensive permissions
    const lambdaRole = new iam.Role(this, 'StreamProcessorRole', {
      roleName: `${config.environmentPrefix}-stream-processor-role`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaDynamoDBExecutionRole'),
      ],
      inlinePolicies: {
        StreamProcessorPolicy: new iam.PolicyDocument({
          statements: [
            // SNS publish permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['sns:Publish'],
              resources: [this.notificationTopic.topicArn],
            }),
            // S3 audit logging permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['s3:PutObject', 's3:PutObjectAcl'],
              resources: [`${this.auditBucket.bucketArn}/*`],
            }),
            // SQS DLQ permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['sqs:SendMessage'],
              resources: [this.deadLetterQueue.queueArn],
            }),
          ],
        }),
      },
    });

    // Create Lambda function for stream processing
    this.processorFunction = new lambda.Function(this, 'StreamProcessor', {
      functionName: `${config.environmentPrefix}-stream-processor`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      memorySize: config.lambdaMemorySize,
      timeout: cdk.Duration.seconds(config.lambdaTimeout),
      deadLetterQueue: this.deadLetterQueue,
      environment: {
        SNS_TOPIC_ARN: this.notificationTopic.topicArn,
        S3_BUCKET_NAME: this.auditBucket.bucketName,
        TABLE_NAME: this.dynamoTable.tableName,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
from datetime import datetime
from decimal import Decimal
import os

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
sns = boto3.client('sns')
s3 = boto3.client('s3')

# Environment variables
SNS_TOPIC_ARN = os.environ['SNS_TOPIC_ARN']
S3_BUCKET_NAME = os.environ['S3_BUCKET_NAME']

def decimal_default(obj):
    """JSON serializer for Decimal objects"""
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError(f"Object of type {type(obj)} is not JSON serializable")

def lambda_handler(event, context):
    """Main Lambda handler for processing DynamoDB stream records"""
    logger.info(f"Processing {len(event['Records'])} stream records")
    
    processed_count = 0
    failed_count = 0
    
    for record in event['Records']:
        try:
            process_stream_record(record)
            processed_count += 1
        except Exception as e:
            logger.error(f"Error processing record: {str(e)}")
            failed_count += 1
            # Re-raise to trigger DLQ for this batch
            raise e
    
    logger.info(f"Processing complete. Success: {processed_count}, Failed: {failed_count}")
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': f'Successfully processed {processed_count} records',
            'processed': processed_count,
            'failed': failed_count
        })
    }

def process_stream_record(record):
    """Process individual DynamoDB stream record"""
    event_name = record['eventName']
    user_id = record['dynamodb']['Keys']['UserId']['S']
    activity_id = record['dynamodb']['Keys']['ActivityId']['S']
    
    logger.info(f"Processing {event_name} event for user {user_id}, activity {activity_id}")
    
    # Create comprehensive audit record
    audit_record = {
        'timestamp': datetime.utcnow().isoformat(),
        'eventName': event_name,
        'userId': user_id,
        'activityId': activity_id,
        'awsRegion': record['awsRegion'],
        'eventSource': record['eventSource'],
        'eventVersion': record.get('eventVersion', 'Unknown'),
        'eventID': record.get('eventID', 'Unknown'),
        'dynamodb': {
            'approximateCreationDateTime': record['dynamodb'].get('ApproximateCreationDateTime'),
            'sequenceNumber': record['dynamodb'].get('SequenceNumber'),
            'sizeBytes': record['dynamodb'].get('SizeBytes'),
            'streamViewType': record['dynamodb'].get('StreamViewType')
        }
    }
    
    # Add old and new images if available
    if 'OldImage' in record['dynamodb']:
        audit_record['oldImage'] = record['dynamodb']['OldImage']
    if 'NewImage' in record['dynamodb']:
        audit_record['newImage'] = record['dynamodb']['NewImage']
    
    # Store audit record in S3
    store_audit_record(audit_record)
    
    # Send appropriate notification based on event type
    notification_message = generate_notification_message(event_name, audit_record)
    send_notification(notification_message, audit_record)

def store_audit_record(audit_record):
    """Store audit record in S3 with organized structure"""
    try:
        # Generate hierarchical S3 key for efficient querying
        timestamp = datetime.utcnow()
        s3_key = (f"audit-logs/"
                 f"year={timestamp.year}/"
                 f"month={timestamp.month:02d}/"
                 f"day={timestamp.day:02d}/"
                 f"hour={timestamp.hour:02d}/"
                 f"{audit_record['userId']}-{audit_record['activityId']}-{timestamp.strftime('%Y%m%d%H%M%S')}.json")
        
        # Store in S3 with metadata
        s3.put_object(
            Bucket=S3_BUCKET_NAME,
            Key=s3_key,
            Body=json.dumps(audit_record, default=decimal_default, indent=2),
            ContentType='application/json',
            Metadata={
                'userId': audit_record['userId'],
                'eventName': audit_record['eventName'],
                'timestamp': audit_record['timestamp']
            },
            ServerSideEncryption='AES256'
        )
        
        logger.info(f"Audit record stored: s3://{S3_BUCKET_NAME}/{s3_key}")
        
    except Exception as e:
        logger.error(f"Failed to store audit record: {str(e)}")
        raise e

def generate_notification_message(event_name, audit_record):
    """Generate contextual notification message based on event type"""
    user_id = audit_record['userId']
    activity_id = audit_record['activityId']
    
    if event_name == 'INSERT':
        return f"🆕 New activity '{activity_id}' created for user {user_id}"
    elif event_name == 'MODIFY':
        return f"📝 Activity '{activity_id}' updated for user {user_id}"
    elif event_name == 'REMOVE':
        return f"🗑️ Activity '{activity_id}' deleted for user {user_id}"
    else:
        return f"🔄 Unknown event '{event_name}' for user {user_id}, activity {activity_id}"

def send_notification(message, audit_record):
    """Send SNS notification with structured data"""
    try:
        # Create structured notification payload
        notification_payload = {
            'version': '1.0',
            'source': 'DynamoDB-Streams-Processor',
            'timestamp': audit_record['timestamp'],
            'message': message,
            'details': {
                'eventName': audit_record['eventName'],
                'userId': audit_record['userId'],
                'activityId': audit_record['activityId'],
                'region': audit_record['awsRegion']
            }
        }
        
        # Add change details for MODIFY events
        if audit_record['eventName'] == 'MODIFY' and 'oldImage' in audit_record and 'newImage' in audit_record:
            notification_payload['details']['hasChanges'] = True
        
        # Send SNS notification
        response = sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Message=json.dumps(notification_payload, default=decimal_default, indent=2),
            Subject=f"Database Change Alert: {audit_record['eventName']}",
            MessageAttributes={
                'eventType': {
                    'DataType': 'String',
                    'StringValue': audit_record['eventName']
                },
                'userId': {
                    'DataType': 'String',
                    'StringValue': audit_record['userId']
                }
            }
        )
        
        logger.info(f"Notification sent successfully: {message} (MessageId: {response['MessageId']})")
        
    except Exception as e:
        logger.error(f"Failed to send notification: {str(e)}")
        raise e
`),
      description: 'Processes DynamoDB stream events for real-time change notifications and audit logging',
    });

    // Create event source mapping for DynamoDB stream
    new lambdaEventSources.DynamoEventSource(this.dynamoTable, {
      startingPosition: lambda.StartingPosition.LATEST,
      batchSize: config.streamBatchSize,
      maxBatchingWindow: cdk.Duration.seconds(config.maxBatchingWindow),
      maxRecordAge: cdk.Duration.hours(1),
      bisectBatchOnError: true,
      retryAttempts: 3,
      parallelizationFactor: 2,
      reportBatchItemFailures: true,
    });

    // Create CloudWatch Log Group with retention policy
    new logs.LogGroup(this, 'ProcessorLogGroup', {
      logGroupName: `/aws/lambda/${this.processorFunction.functionName}`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create CloudWatch monitoring alarms
    if (config.enableMonitoring) {
      this.createMonitoringAlarms(config);
    }

    // Add resource tags
    this.addResourceTags();

    // Create stack outputs
    this.createOutputs();
  }

  /**
   * Create CloudWatch alarms for monitoring
   */
  private createMonitoringAlarms(config: any): void {
    // Lambda function error alarm
    const lambdaErrorAlarm = new cloudwatch.Alarm(this, 'LambdaErrorAlarm', {
      alarmName: `${config.environmentPrefix}-lambda-errors`,
      alarmDescription: 'Lambda function errors',
      metric: this.processorFunction.metricErrors({
        period: cdk.Duration.minutes(5),
        statistic: 'Sum',
      }),
      threshold: 1,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Lambda function duration alarm
    const lambdaDurationAlarm = new cloudwatch.Alarm(this, 'LambdaDurationAlarm', {
      alarmName: `${config.environmentPrefix}-lambda-duration`,
      alarmDescription: 'Lambda function duration exceeding 80% of timeout',
      metric: this.processorFunction.metricDuration({
        period: cdk.Duration.minutes(5),
        statistic: 'Average',
      }),
      threshold: config.lambdaTimeout * 0.8 * 1000, // 80% of timeout in milliseconds
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Dead letter queue alarm
    const dlqAlarm = new cloudwatch.Alarm(this, 'DeadLetterQueueAlarm', {
      alarmName: `${config.environmentPrefix}-dlq-messages`,
      alarmDescription: 'Messages in dead letter queue',
      metric: this.deadLetterQueue.metricApproximateNumberOfVisibleMessages({
        period: cdk.Duration.minutes(5),
        statistic: 'Average',
      }),
      threshold: 1,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // DynamoDB throttling alarm
    const dynamoThrottleAlarm = new cloudwatch.Alarm(this, 'DynamoThrottleAlarm', {
      alarmName: `${config.environmentPrefix}-dynamodb-throttles`,
      alarmDescription: 'DynamoDB read/write throttling events',
      metric: new cloudwatch.MathExpression({
        expression: 'readThrottles + writeThrottles',
        usingMetrics: {
          readThrottles: this.dynamoTable.metricThrottledRequestsForOperations({
            operations: [dynamodb.Operation.GET_ITEM, dynamodb.Operation.QUERY, dynamodb.Operation.SCAN],
            period: cdk.Duration.minutes(5),
            statistic: 'Sum',
          }),
          writeThrottles: this.dynamoTable.metricThrottledRequestsForOperations({
            operations: [dynamodb.Operation.PUT_ITEM, dynamodb.Operation.UPDATE_ITEM, dynamodb.Operation.DELETE_ITEM],
            period: cdk.Duration.minutes(5),
            statistic: 'Sum',
          }),
        },
        period: cdk.Duration.minutes(5),
      }),
      threshold: 5,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Add SNS actions to alarms
    const snsAction = new SnsAction(this.notificationTopic);
    lambdaErrorAlarm.addAlarmAction(snsAction);
    lambdaDurationAlarm.addAlarmAction(snsAction);
    dlqAlarm.addAlarmAction(snsAction);
    dynamoThrottleAlarm.addAlarmAction(snsAction);
  }

  /**
   * Add consistent resource tags
   */
  private addResourceTags(): void {
    const tags = {
      Project: 'Real-Time Database Change Streams',
      Environment: 'Production',
      Component: 'Stream Processing',
      Owner: 'DataEngineering',
      CostCenter: 'Engineering',
    };

    Object.entries(tags).forEach(([key, value]) => {
      cdk.Tags.of(this).add(key, value);
    });
  }

  /**
   * Create CloudFormation outputs
   */
  private createOutputs(): void {
    new cdk.CfnOutput(this, 'DynamoTableName', {
      value: this.dynamoTable.tableName,
      description: 'Name of the DynamoDB table with streams enabled',
      exportName: `${this.stackName}-DynamoTableName`,
    });

    new cdk.CfnOutput(this, 'DynamoTableStreamArn', {
      value: this.dynamoTable.tableStreamArn!,
      description: 'ARN of the DynamoDB table stream',
      exportName: `${this.stackName}-DynamoTableStreamArn`,
    });

    new cdk.CfnOutput(this, 'ProcessorFunctionName', {
      value: this.processorFunction.functionName,
      description: 'Name of the Lambda stream processor function',
      exportName: `${this.stackName}-ProcessorFunctionName`,
    });

    new cdk.CfnOutput(this, 'ProcessorFunctionArn', {
      value: this.processorFunction.functionArn,
      description: 'ARN of the Lambda stream processor function',
      exportName: `${this.stackName}-ProcessorFunctionArn`,
    });

    new cdk.CfnOutput(this, 'NotificationTopicArn', {
      value: this.notificationTopic.topicArn,
      description: 'ARN of the SNS notification topic',
      exportName: `${this.stackName}-NotificationTopicArn`,
    });

    new cdk.CfnOutput(this, 'AuditBucketName', {
      value: this.auditBucket.bucketName,
      description: 'Name of the S3 bucket for audit logs',
      exportName: `${this.stackName}-AuditBucketName`,
    });

    new cdk.CfnOutput(this, 'DeadLetterQueueUrl', {
      value: this.deadLetterQueue.queueUrl,
      description: 'URL of the dead letter queue',
      exportName: `${this.stackName}-DeadLetterQueueUrl`,
    });

    new cdk.CfnOutput(this, 'DeadLetterQueueArn', {
      value: this.deadLetterQueue.queueArn,
      description: 'ARN of the dead letter queue',
      exportName: `${this.stackName}-DeadLetterQueueArn`,
    });
  }
}

// Main CDK application
const app = new cdk.App();

// Get configuration from CDK context or environment variables
const environmentPrefix = app.node.tryGetContext('environmentPrefix') || process.env.CDK_ENVIRONMENT_PREFIX || 'rtdb-streams';
const enableMonitoring = app.node.tryGetContext('enableMonitoring') !== false;

// Create the stack
new RealTimeDatabaseChangeStreamsStack(app, 'RealTimeDatabaseChangeStreamsStack', {
  environmentPrefix,
  enableMonitoring,
  description: 'Real-time database change streams processing with DynamoDB Streams, Lambda, and comprehensive monitoring',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'Real-Time Database Change Streams',
    Repository: 'aws-recipes',
    Recipe: 'real-time-database-change-streams-dynamodb-streams',
  },
});

// Synthesize the CDK app
app.synth();