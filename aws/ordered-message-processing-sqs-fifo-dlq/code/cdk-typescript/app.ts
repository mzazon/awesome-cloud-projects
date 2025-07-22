#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as sqs from 'aws-cdk-lib/aws-sqs';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambdaEventSources from 'aws-cdk-lib/aws-lambda-event-sources';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as cloudwatchActions from 'aws-cdk-lib/aws-cloudwatch-actions';
import { Construct } from 'constructs';
import { Duration, RemovalPolicy } from 'aws-cdk-lib';

/**
 * Stack for ordered message processing with SQS FIFO and dead letter queues
 * 
 * This stack implements a robust ordered message processing system using:
 * - SQS FIFO queues for ordered message delivery
 * - Dead letter queues for poison message handling
 * - Lambda functions for message processing and error handling
 * - DynamoDB for order state management
 * - S3 for message archival
 * - CloudWatch monitoring and alerting
 */
class OrderedMessageProcessingStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names to avoid conflicts
    const uniqueSuffix = this.node.addr.substring(0, 8);

    // =====================================================
    // STORAGE RESOURCES
    // =====================================================

    // DynamoDB table for order state management with GSI for message group queries
    const orderTable = new dynamodb.Table(this, 'OrderTable', {
      tableName: `fifo-processing-orders-${uniqueSuffix}`,
      partitionKey: { name: 'OrderId', type: dynamodb.AttributeType.STRING },
      billingMode: dynamodb.BillingMode.PROVISIONED,
      readCapacity: 10,
      writeCapacity: 10,
      stream: dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
      removalPolicy: RemovalPolicy.DESTROY, // For demo purposes
      pointInTimeRecovery: true, // Production best practice
    });

    // Global Secondary Index for querying by message group
    orderTable.addGlobalSecondaryIndex({
      indexName: 'MessageGroup-ProcessedAt-index',
      partitionKey: { name: 'MessageGroupId', type: dynamodb.AttributeType.STRING },
      sortKey: { name: 'ProcessedAt', type: dynamodb.AttributeType.STRING },
      readCapacity: 5,
      writeCapacity: 5,
      projectionType: dynamodb.ProjectionType.ALL,
    });

    // S3 bucket for archiving poison messages with lifecycle policies
    const archiveBucket = new s3.Bucket(this, 'ArchiveBucket', {
      bucketName: `fifo-processing-archive-${uniqueSuffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: RemovalPolicy.DESTROY, // For demo purposes
      autoDeleteObjects: true, // For demo cleanup
      lifecycleRules: [
        {
          id: 'ArchiveTransition',
          enabled: true,
          prefix: 'poison-messages/',
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: Duration.days(30),
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: Duration.days(90),
            },
          ],
        },
      ],
    });

    // =====================================================
    // MESSAGING RESOURCES
    // =====================================================

    // SNS topic for operational alerts
    const alertTopic = new sns.Topic(this, 'AlertTopic', {
      topicName: `fifo-processing-alerts-${uniqueSuffix}`,
      displayName: 'FIFO Processing Alerts',
    });

    // Dead letter queue (FIFO) for failed messages
    const deadLetterQueue = new sqs.Queue(this, 'DeadLetterQueue', {
      queueName: `fifo-processing-dlq-${uniqueSuffix}.fifo`,
      fifo: true,
      contentBasedDeduplication: true,
      messageRetentionPeriod: Duration.days(14),
      visibilityTimeout: Duration.minutes(5),
      encryption: sqs.QueueEncryption.SQS_MANAGED,
    });

    // Main FIFO queue with advanced configuration for high throughput
    const mainQueue = new sqs.Queue(this, 'MainQueue', {
      queueName: `fifo-processing-main-${uniqueSuffix}.fifo`,
      fifo: true,
      contentBasedDeduplication: false, // Manual deduplication for better control
      deduplicationScope: sqs.DeduplicationScope.MESSAGE_GROUP,
      fifoThroughputLimit: sqs.FifoThroughputLimit.PER_MESSAGE_GROUP_ID,
      messageRetentionPeriod: Duration.days(14),
      visibilityTimeout: Duration.minutes(5),
      encryption: sqs.QueueEncryption.SQS_MANAGED,
      deadLetterQueue: {
        queue: deadLetterQueue,
        maxReceiveCount: 3, // Send to DLQ after 3 failed attempts
      },
    });

    // =====================================================
    // LAMBDA FUNCTIONS
    // =====================================================

    // Message processor Lambda function with reserved concurrency
    const messageProcessor = new lambda.Function(this, 'MessageProcessor', {
      functionName: `fifo-processing-processor-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      timeout: Duration.minutes(5),
      reservedConcurrency: 10, // Prevent overwhelming downstream systems
      environment: {
        ORDER_TABLE_NAME: orderTable.tableName,
        DLQ_URL: deadLetterQueue.queueUrl,
        MAIN_QUEUE_URL: mainQueue.queueUrl,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import time
import os
from datetime import datetime, timedelta
from decimal import Decimal
import random
import uuid

dynamodb = boto3.resource('dynamodb')
cloudwatch = boto3.client('cloudwatch')
sqs = boto3.client('sqs')

def lambda_handler(event, context):
    """
    Process messages from SQS FIFO queue with ordering guarantees
    """
    processed_count = 0
    failed_count = 0
    
    print(f"Processing {len(event['Records'])} messages")
    
    for record in event['Records']:
        try:
            # Extract message details
            message_body = json.loads(record['body'])
            message_group_id = record['attributes']['MessageGroupId']
            message_dedup_id = record['attributes'].get('MessageDeduplicationId', str(uuid.uuid4()))
            
            print(f"Processing message: {message_dedup_id} in group: {message_group_id}")
            
            # Process the order message
            result = process_order_message(message_body, message_group_id, message_dedup_id)
            
            if result['success']:
                processed_count += 1
                publish_processing_metrics(message_group_id, 'SUCCESS', result['processing_time'])
            else:
                failed_count += 1
                publish_processing_metrics(message_group_id, 'FAILURE', result['processing_time'])
                
                # Simulate different failure scenarios for demo
                if should_simulate_failure():
                    raise Exception(f"Simulated processing failure for message {message_dedup_id}")
            
        except Exception as e:
            failed_count += 1
            print(f"Error processing message: {str(e)}")
            
            publish_processing_metrics(
                record['attributes'].get('MessageGroupId', 'unknown'), 
                'ERROR', 
                0
            )
            
            # Re-raise to trigger DLQ behavior
            raise
    
    # Publish batch metrics
    publish_batch_metrics(processed_count, failed_count)
    
    return {
        'statusCode': 200,
        'processedCount': processed_count,
        'failedCount': failed_count
    }

def process_order_message(message_body, message_group_id, message_dedup_id):
    """
    Process individual order message with idempotency
    """
    start_time = time.time()
    
    try:
        # Extract and validate order information
        order_id = message_body.get('orderId')
        order_type = message_body.get('orderType')
        amount = message_body.get('amount')
        timestamp = message_body.get('timestamp')
        
        if not all([order_id, order_type, amount]):
            raise ValueError("Missing required order fields")
        
        table = dynamodb.Table(os.environ['ORDER_TABLE_NAME'])
        
        # Check for duplicate processing (idempotency)
        try:
            existing_item = table.get_item(Key={'OrderId': order_id})
            
            if 'Item' in existing_item:
                if existing_item['Item'].get('MessageDeduplicationId') == message_dedup_id:
                    print(f"Message {message_dedup_id} already processed for order {order_id}")
                    return {
                        'success': True, 
                        'processing_time': time.time() - start_time,
                        'duplicate': True
                    }
        except Exception as e:
            print(f"Error checking for duplicates: {str(e)}")
        
        # Validate order amount (business rule)
        if Decimal(str(amount)) < 0:
            raise ValueError(f"Invalid order amount: {amount}")
        
        # Simulate complex business logic processing
        time.sleep(random.uniform(0.1, 0.5))
        
        # Store order state with message tracking
        table.put_item(
            Item={
                'OrderId': order_id,
                'OrderType': order_type,
                'Amount': Decimal(str(amount)),
                'MessageGroupId': message_group_id,
                'MessageDeduplicationId': message_dedup_id,
                'Status': 'PROCESSED',
                'ProcessedAt': datetime.utcnow().isoformat(),
                'ProcessingTimeMs': int((time.time() - start_time) * 1000),
                'OriginalTimestamp': timestamp or datetime.utcnow().isoformat()
            }
        )
        
        return {
            'success': True, 
            'processing_time': time.time() - start_time,
            'duplicate': False
        }
        
    except Exception as e:
        print(f"Error processing order {message_body.get('orderId', 'unknown')}: {str(e)}")
        return {
            'success': False, 
            'processing_time': time.time() - start_time,
            'error': str(e)
        }

def publish_processing_metrics(message_group_id, status, processing_time):
    """
    Publish detailed processing metrics to CloudWatch
    """
    try:
        cloudwatch.put_metric_data(
            Namespace='FIFO/MessageProcessing',
            MetricData=[
                {
                    'MetricName': 'ProcessingTime',
                    'Value': processing_time * 1000,  # Convert to milliseconds
                    'Unit': 'Milliseconds',
                    'Dimensions': [
                        {'Name': 'MessageGroup', 'Value': message_group_id},
                        {'Name': 'Status', 'Value': status}
                    ]
                },
                {
                    'MetricName': 'MessageStatus',
                    'Value': 1,
                    'Unit': 'Count',
                    'Dimensions': [
                        {'Name': 'MessageGroup', 'Value': message_group_id},
                        {'Name': 'Status', 'Value': status}
                    ]
                }
            ]
        )
    except Exception as e:
        print(f"Error publishing metrics: {str(e)}")

def publish_batch_metrics(processed_count, failed_count):
    """
    Publish batch processing metrics
    """
    try:
        cloudwatch.put_metric_data(
            Namespace='FIFO/MessageProcessing',
            MetricData=[
                {
                    'MetricName': 'ProcessedMessages',
                    'Value': processed_count,
                    'Unit': 'Count',
                    'Dimensions': [{'Name': 'Environment', 'Value': 'Demo'}]
                },
                {
                    'MetricName': 'FailedMessages', 
                    'Value': failed_count,
                    'Unit': 'Count',
                    'Dimensions': [{'Name': 'Environment', 'Value': 'Demo'}]
                }
            ]
        )
    except Exception as e:
        print(f"Error publishing batch metrics: {str(e)}")

def should_simulate_failure():
    """
    Simulate occasional processing failures for testing (10% chance)
    """
    return random.random() < 0.1
`),
    });

    // Poison message handler Lambda function
    const poisonMessageHandler = new lambda.Function(this, 'PoisonMessageHandler', {
      functionName: `fifo-processing-poison-handler-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      timeout: Duration.minutes(5),
      environment: {
        ARCHIVE_BUCKET_NAME: archiveBucket.bucketName,
        SNS_TOPIC_ARN: alertTopic.topicArn,
        MAIN_QUEUE_URL: mainQueue.queueUrl,
        DLQ_URL: deadLetterQueue.queueUrl,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import time
import os
from datetime import datetime
import uuid

s3 = boto3.client('s3')
sns = boto3.client('sns')
sqs = boto3.client('sqs')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    """
    Handle poison messages from dead letter queue
    """
    processed_count = 0
    
    print(f"Processing {len(event['Records'])} poison messages")
    
    for record in event['Records']:
        try:
            # Extract message details
            message_body = json.loads(record['body'])
            message_group_id = record['attributes'].get('MessageGroupId', 'unknown')
            message_dedup_id = record['attributes'].get('MessageDeduplicationId', str(uuid.uuid4()))
            
            print(f"Processing poison message: {message_dedup_id} in group: {message_group_id}")
            
            # Analyze the poison message
            analysis_result = analyze_poison_message(message_body, record)
            
            # Archive the poison message to S3
            archive_key = archive_poison_message(message_body, record, analysis_result)
            
            # Send alert for critical poison messages
            if analysis_result['severity'] == 'CRITICAL':
                send_poison_message_alert(message_body, analysis_result, archive_key)
            
            # Attempt automated recovery if possible
            if analysis_result['recoverable']:
                recovery_result = attempt_message_recovery(message_body, message_group_id)
                if recovery_result['success']:
                    print(f"Successfully recovered message {message_dedup_id}")
            
            processed_count += 1
            
            # Publish metrics
            publish_poison_metrics(message_group_id, analysis_result)
            
        except Exception as e:
            print(f"Error handling poison message: {str(e)}")
            # Continue processing other messages
    
    return {
        'statusCode': 200,
        'processedCount': processed_count
    }

def analyze_poison_message(message_body, record):
    """
    Analyze poison message to determine cause and recovery options
    """
    analysis = {
        'severity': 'MEDIUM',
        'recoverable': False,
        'failure_reason': 'unknown',
        'analysis_timestamp': datetime.utcnow().isoformat()
    }
    
    try:
        # Check for common failure patterns
        required_fields = ['orderId', 'orderType', 'amount']
        missing_fields = [field for field in required_fields if field not in message_body]
        
        if missing_fields:
            analysis['failure_reason'] = f"missing_fields: {', '.join(missing_fields)}"
            analysis['severity'] = 'HIGH'
            analysis['recoverable'] = False
        elif 'amount' in message_body:
            try:
                amount = float(message_body['amount'])
                if amount < 0:
                    analysis['failure_reason'] = 'negative_amount'
                    analysis['severity'] = 'MEDIUM'
                    analysis['recoverable'] = True
            except (ValueError, TypeError):
                analysis['failure_reason'] = 'invalid_amount_format'
                analysis['severity'] = 'HIGH'
                analysis['recoverable'] = False
        
        # Check message attributes for processing history
        approximate_receive_count = int(record.get('attributes', {}).get('ApproximateReceiveCount', 0))
        if approximate_receive_count > 5:
            analysis['severity'] = 'CRITICAL'
            analysis['failure_reason'] = f'excessive_retries: {approximate_receive_count}'
        
        if not isinstance(message_body, dict):
            analysis['failure_reason'] = 'malformed_json'
            analysis['severity'] = 'HIGH'
            analysis['recoverable'] = False
        
    except Exception as e:
        analysis['failure_reason'] = f'analysis_error: {str(e)}'
        analysis['severity'] = 'CRITICAL'
    
    return analysis

def archive_poison_message(message_body, record, analysis):
    """
    Archive poison message to S3 for investigation
    """
    try:
        timestamp = datetime.utcnow()
        archive_key = f"poison-messages/{timestamp.strftime('%Y/%m/%d')}/{timestamp.strftime('%H%M%S')}-{uuid.uuid4()}.json"
        
        archive_data = {
            'originalMessage': message_body,
            'sqsRecord': {
                'messageId': record.get('messageId'),
                'receiptHandle': record.get('receiptHandle'),
                'messageAttributes': record.get('messageAttributes', {}),
                'attributes': record.get('attributes', {})
            },
            'analysis': analysis,
            'archivedAt': timestamp.isoformat()
        }
        
        s3.put_object(
            Bucket=os.environ['ARCHIVE_BUCKET_NAME'],
            Key=archive_key,
            Body=json.dumps(archive_data, indent=2),
            ContentType='application/json',
            Metadata={
                'severity': analysis['severity'],
                'failure-reason': analysis['failure_reason'][:256],
                'message-group-id': record['attributes'].get('MessageGroupId', 'unknown')
            }
        )
        
        print(f"Archived poison message to: s3://{os.environ['ARCHIVE_BUCKET_NAME']}/{archive_key}")
        return archive_key
        
    except Exception as e:
        print(f"Error archiving poison message: {str(e)}")
        return None

def send_poison_message_alert(message_body, analysis, archive_key):
    """
    Send SNS alert for critical poison messages
    """
    try:
        alert_message = {
            'severity': analysis['severity'],
            'failure_reason': analysis['failure_reason'],
            'order_id': message_body.get('orderId', 'unknown'),
            'archive_location': f"s3://{os.environ['ARCHIVE_BUCKET_NAME']}/{archive_key}" if archive_key else 'failed_to_archive',
            'timestamp': datetime.utcnow().isoformat(),
            'requires_investigation': True
        }
        
        sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Subject=f"CRITICAL: Poison Message Detected - {analysis['failure_reason']}",
            Message=json.dumps(alert_message, indent=2)
        )
        
        print(f"Sent poison message alert for order {message_body.get('orderId', 'unknown')}")
        
    except Exception as e:
        print(f"Error sending poison message alert: {str(e)}")

def attempt_message_recovery(message_body, message_group_id):
    """
    Attempt automated recovery for recoverable poison messages
    """
    try:
        # Example recovery: fix negative amounts by taking absolute value
        if 'amount' in message_body and float(message_body['amount']) < 0:
            corrected_message = message_body.copy()
            corrected_message['amount'] = abs(float(message_body['amount']))
            corrected_message['recovery_applied'] = 'negative_amount_correction'
            corrected_message['original_amount'] = message_body['amount']
            
            # Send corrected message back to main queue
            response = sqs.send_message(
                QueueUrl=os.environ['MAIN_QUEUE_URL'],
                MessageBody=json.dumps(corrected_message),
                MessageGroupId=message_group_id,
                MessageDeduplicationId=f"recovered-{uuid.uuid4()}"
            )
            
            return {
                'success': True,
                'recovery_type': 'negative_amount_correction',
                'new_message_id': response['MessageId']
            }
        
        return {'success': False, 'reason': 'no_recovery_strategy'}
        
    except Exception as e:
        print(f"Error attempting message recovery: {str(e)}")
        return {'success': False, 'reason': str(e)}

def publish_poison_metrics(message_group_id, analysis):
    """
    Publish poison message metrics to CloudWatch
    """
    try:
        cloudwatch.put_metric_data(
            Namespace='FIFO/PoisonMessages',
            MetricData=[
                {
                    'MetricName': 'PoisonMessageCount',
                    'Value': 1,
                    'Unit': 'Count',
                    'Dimensions': [
                        {'Name': 'MessageGroup', 'Value': message_group_id},
                        {'Name': 'Severity', 'Value': analysis['severity']},
                        {'Name': 'FailureReason', 'Value': analysis['failure_reason'][:255]}
                    ]
                },
                {
                    'MetricName': 'RecoverableMessages',
                    'Value': 1 if analysis['recoverable'] else 0,
                    'Unit': 'Count',
                    'Dimensions': [{'Name': 'MessageGroup', 'Value': message_group_id}]
                }
            ]
        )
    except Exception as e:
        print(f"Error publishing poison metrics: {str(e)}")
`),
    });

    // Message replay Lambda function for operational recovery
    const messageReplay = new lambda.Function(this, 'MessageReplay', {
      functionName: `fifo-processing-replay-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      timeout: Duration.minutes(5),
      environment: {
        ARCHIVE_BUCKET_NAME: archiveBucket.bucketName,
        MAIN_QUEUE_URL: mainQueue.queueUrl,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from datetime import datetime, timedelta
import uuid

s3 = boto3.client('s3')
sqs = boto3.client('sqs')

def lambda_handler(event, context):
    """
    Replay messages from S3 archive back to processing queue
    """
    try:
        replay_request = event.get('replay_request', {})
        
        start_time = replay_request.get('start_time')
        end_time = replay_request.get('end_time', datetime.utcnow().isoformat())
        message_group_filter = replay_request.get('message_group_id')
        dry_run = replay_request.get('dry_run', True)
        
        if not start_time:
            start_time = (datetime.utcnow() - timedelta(hours=1)).isoformat()
        
        print(f"Replaying messages from {start_time} to {end_time}")
        print(f"Message group filter: {message_group_filter}")
        print(f"Dry run mode: {dry_run}")
        
        archived_messages = list_archived_messages(start_time, end_time, message_group_filter)
        
        replay_results = {
            'total_found': len(archived_messages),
            'replayed': 0,
            'skipped': 0,
            'errors': 0,
            'dry_run': dry_run
        }
        
        for message_info in archived_messages:
            try:
                if should_replay_message(message_info):
                    if not dry_run:
                        replay_result = replay_single_message(message_info)
                        if replay_result['success']:
                            replay_results['replayed'] += 1
                        else:
                            replay_results['errors'] += 1
                    else:
                        replay_results['replayed'] += 1
                        print(f"DRY RUN: Would replay message {message_info['key']}")
                else:
                    replay_results['skipped'] += 1
                    
            except Exception as e:
                print(f"Error processing archived message {message_info['key']}: {str(e)}")
                replay_results['errors'] += 1
        
        return {
            'statusCode': 200,
            'body': json.dumps(replay_results)
        }
        
    except Exception as e:
        print(f"Error in message replay: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def list_archived_messages(start_time, end_time, message_group_filter=None):
    """
    List archived messages within time range
    """
    archived_messages = []
    
    try:
        start_dt = datetime.fromisoformat(start_time.replace('Z', '+00:00'))
        end_dt = datetime.fromisoformat(end_time.replace('Z', '+00:00'))
        
        paginator = s3.get_paginator('list_objects_v2')
        pages = paginator.paginate(
            Bucket=os.environ['ARCHIVE_BUCKET_NAME'],
            Prefix='poison-messages/'
        )
        
        for page in pages:
            for obj in page.get('Contents', []):
                try:
                    key_parts = obj['Key'].split('/')
                    if len(key_parts) >= 5:
                        date_part = '/'.join(key_parts[1:4])
                        filename = key_parts[4]
                        time_part = filename.split('-')[0]
                        
                        timestamp_str = f"{date_part.replace('/', '')}T{time_part[:2]}:{time_part[2:4]}:{time_part[4:6]}"
                        msg_dt = datetime.strptime(timestamp_str, '%Y%m%dT%H:%M:%S')
                        
                        if start_dt <= msg_dt <= end_dt:
                            message_info = {
                                'key': obj['Key'],
                                'timestamp': msg_dt,
                                'size': obj['Size'],
                                'metadata': obj.get('Metadata', {})
                            }
                            
                            if not message_group_filter or obj.get('Metadata', {}).get('message-group-id') == message_group_filter:
                                archived_messages.append(message_info)
                
                except Exception as e:
                    print(f"Error parsing object key {obj['Key']}: {str(e)}")
                    continue
        
        print(f"Found {len(archived_messages)} archived messages in time range")
        return archived_messages
        
    except Exception as e:
        print(f"Error listing archived messages: {str(e)}")
        return []

def should_replay_message(message_info):
    """
    Determine if a message should be replayed based on analysis
    """
    try:
        response = s3.get_object(
            Bucket=os.environ['ARCHIVE_BUCKET_NAME'],
            Key=message_info['key']
        )
        
        message_data = json.loads(response['Body'].read())
        analysis = message_data.get('analysis', {})
        
        if analysis.get('recoverable', False) or analysis.get('severity') in ['MEDIUM', 'LOW']:
            return True
        
        return False
        
    except Exception as e:
        print(f"Error analyzing message for replay: {str(e)}")
        return False

def replay_single_message(message_info):
    """
    Replay a single message back to the processing queue
    """
    try:
        response = s3.get_object(
            Bucket=os.environ['ARCHIVE_BUCKET_NAME'],
            Key=message_info['key']
        )
        
        message_data = json.loads(response['Body'].read())
        original_message = message_data['originalMessage']
        
        replay_message = original_message.copy()
        replay_message['replayed'] = True
        replay_message['replay_timestamp'] = datetime.utcnow().isoformat()
        replay_message['original_archive_key'] = message_info['key']
        
        message_group_id = message_info.get('metadata', {}).get('message-group-id', 'replay-group')
        
        response = sqs.send_message(
            QueueUrl=os.environ['MAIN_QUEUE_URL'],
            MessageBody=json.dumps(replay_message),
            MessageGroupId=message_group_id,
            MessageDeduplicationId=f"replay-{uuid.uuid4()}"
        )
        
        print(f"Successfully replayed message {message_info['key']}: {response['MessageId']}")
        
        return {
            'success': True,
            'message_id': response['MessageId']
        }
        
    except Exception as e:
        print(f"Error replaying message {message_info['key']}: {str(e)}")
        return {
            'success': False,
            'error': str(e)
        }
`),
    });

    // =====================================================
    // IAM PERMISSIONS
    // =====================================================

    // Grant message processor permissions
    orderTable.grantReadWriteData(messageProcessor);
    mainQueue.grantConsumeMessages(messageProcessor);
    deadLetterQueue.grantSendMessages(messageProcessor);

    // Grant CloudWatch permissions for custom metrics
    messageProcessor.addToRolePolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: ['cloudwatch:PutMetricData'],
      resources: ['*'],
    }));

    // Grant poison handler permissions
    deadLetterQueue.grantConsumeMessages(poisonMessageHandler);
    mainQueue.grantSendMessages(poisonMessageHandler);
    archiveBucket.grantReadWrite(poisonMessageHandler);
    alertTopic.grantPublish(poisonMessageHandler);

    // Grant CloudWatch permissions for poison handler
    poisonMessageHandler.addToRolePolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: ['cloudwatch:PutMetricData'],
      resources: ['*'],
    }));

    // Grant replay function permissions
    archiveBucket.grantRead(messageReplay);
    mainQueue.grantSendMessages(messageReplay);

    // =====================================================
    // EVENT SOURCE MAPPINGS
    // =====================================================

    // Configure event source mapping for main queue (single message batches for strict ordering)
    messageProcessor.addEventSource(new lambdaEventSources.SqsEventSource(mainQueue, {
      batchSize: 1, // Process one message at a time to maintain order
      maxBatchingWindow: Duration.seconds(5),
      reportBatchItemFailures: true,
    }));

    // Configure event source mapping for dead letter queue (larger batches for efficiency)
    poisonMessageHandler.addEventSource(new lambdaEventSources.SqsEventSource(deadLetterQueue, {
      batchSize: 5, // Process multiple poison messages for efficiency
      maxBatchingWindow: Duration.seconds(10),
      reportBatchItemFailures: true,
    }));

    // =====================================================
    // CLOUDWATCH MONITORING AND ALARMS
    // =====================================================

    // High failure rate alarm
    const highFailureRateAlarm = new cloudwatch.Alarm(this, 'HighFailureRateAlarm', {
      alarmName: `${uniqueSuffix}-high-failure-rate`,
      alarmDescription: 'High message processing failure rate',
      metric: new cloudwatch.Metric({
        namespace: 'FIFO/MessageProcessing',
        metricName: 'FailedMessages',
        statistic: 'Sum',
        period: Duration.minutes(5),
      }),
      threshold: 5,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    highFailureRateAlarm.addAlarmAction(new cloudwatchActions.SnsAction(alertTopic));

    // Poison message detection alarm
    const poisonMessageAlarm = new cloudwatch.Alarm(this, 'PoisonMessageAlarm', {
      alarmName: `${uniqueSuffix}-poison-messages-detected`,
      alarmDescription: 'Poison messages detected in DLQ',
      metric: new cloudwatch.Metric({
        namespace: 'FIFO/PoisonMessages',
        metricName: 'PoisonMessageCount',
        statistic: 'Sum',
        period: Duration.minutes(5),
      }),
      threshold: 1,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    poisonMessageAlarm.addAlarmAction(new cloudwatchActions.SnsAction(alertTopic));

    // High processing latency alarm
    const highLatencyAlarm = new cloudwatch.Alarm(this, 'HighProcessingLatencyAlarm', {
      alarmName: `${uniqueSuffix}-high-processing-latency`,
      alarmDescription: 'High message processing latency',
      metric: new cloudwatch.Metric({
        namespace: 'FIFO/MessageProcessing',
        metricName: 'ProcessingTime',
        statistic: 'Average',
        period: Duration.minutes(5),
      }),
      threshold: 5000, // 5 seconds in milliseconds
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    highLatencyAlarm.addAlarmAction(new cloudwatchActions.SnsAction(alertTopic));

    // =====================================================
    // STACK OUTPUTS
    // =====================================================

    new cdk.CfnOutput(this, 'MainQueueUrl', {
      value: mainQueue.queueUrl,
      description: 'Main FIFO queue URL for sending messages',
      exportName: `${this.stackName}-MainQueueUrl`,
    });

    new cdk.CfnOutput(this, 'DeadLetterQueueUrl', {
      value: deadLetterQueue.queueUrl,
      description: 'Dead letter queue URL for poison messages',
      exportName: `${this.stackName}-DeadLetterQueueUrl`,
    });

    new cdk.CfnOutput(this, 'OrderTableName', {
      value: orderTable.tableName,
      description: 'DynamoDB table name for order state',
      exportName: `${this.stackName}-OrderTableName`,
    });

    new cdk.CfnOutput(this, 'ArchiveBucketName', {
      value: archiveBucket.bucketName,
      description: 'S3 bucket name for message archival',
      exportName: `${this.stackName}-ArchiveBucketName`,
    });

    new cdk.CfnOutput(this, 'AlertTopicArn', {
      value: alertTopic.topicArn,
      description: 'SNS topic ARN for operational alerts',
      exportName: `${this.stackName}-AlertTopicArn`,
    });

    new cdk.CfnOutput(this, 'MessageProcessorFunctionName', {
      value: messageProcessor.functionName,
      description: 'Lambda function name for message processing',
      exportName: `${this.stackName}-MessageProcessorFunctionName`,
    });

    new cdk.CfnOutput(this, 'PoisonMessageHandlerFunctionName', {
      value: poisonMessageHandler.functionName,
      description: 'Lambda function name for poison message handling',
      exportName: `${this.stackName}-PoisonMessageHandlerFunctionName`,
    });

    new cdk.CfnOutput(this, 'MessageReplayFunctionName', {
      value: messageReplay.functionName,
      description: 'Lambda function name for message replay',
      exportName: `${this.stackName}-MessageReplayFunctionName`,
    });
  }
}

// =====================================================
// CDK APP INSTANTIATION
// =====================================================

const app = new cdk.App();

new OrderedMessageProcessingStack(app, 'OrderedMessageProcessingStack', {
  description: 'Ordered message processing system with SQS FIFO queues and dead letter handling',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'FIFO-Message-Processing',
    Environment: 'Demo',
    CostCenter: 'Engineering',
    Owner: 'AWS-Samples',
  },
});

app.synth();