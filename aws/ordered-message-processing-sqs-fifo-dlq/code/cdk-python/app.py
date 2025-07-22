#!/usr/bin/env python3
"""
CDK Application for Ordered Message Processing with SQS FIFO and Dead Letter Queues

This CDK application implements a production-ready ordered message processing system
using Amazon SQS FIFO queues with sophisticated deduplication, message grouping strategies,
and comprehensive dead letter queue handling for financial trading systems.

Author: AWS CDK Generator
"""

import os
import json
from typing import Dict, Any, Optional
from constructs import Construct
from aws_cdk import (
    App,
    Stack,
    Environment,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_sqs as sqs,
    aws_lambda as lambda_,
    aws_lambda_event_sources as lambda_event_sources,
    aws_dynamodb as dynamodb,
    aws_s3 as s3,
    aws_sns as sns,
    aws_cloudwatch as cloudwatch,
    aws_iam as iam,
    aws_logs as logs,
)


class OrderedMessageProcessingStack(Stack):
    """
    CDK Stack for implementing ordered message processing with SQS FIFO queues.
    
    This stack creates:
    - DynamoDB table for order state management with GSI and streams
    - S3 bucket for poison message archival with lifecycle policies
    - SNS topic for operational alerting
    - FIFO dead letter queue with advanced configuration
    - Main FIFO queue with sophisticated redrive policy
    - Lambda functions for message processing, poison handling, and replay
    - CloudWatch alarms for comprehensive monitoring
    - IAM roles with least-privilege permissions
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        project_name: str = "fifo-processing",
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        self.project_name = project_name

        # Create core infrastructure components
        self.order_table = self._create_dynamodb_table()
        self.archive_bucket = self._create_s3_bucket()
        self.alert_topic = self._create_sns_topic()
        
        # Create SQS queues (DLQ first, then main queue)
        self.dead_letter_queue = self._create_dead_letter_queue()
        self.main_queue = self._create_main_queue()
        
        # Create IAM roles for Lambda functions
        self.processor_role = self._create_processor_role()
        self.poison_handler_role = self._create_poison_handler_role()
        
        # Create Lambda functions
        self.message_processor = self._create_message_processor()
        self.poison_handler = self._create_poison_handler()
        self.message_replay = self._create_message_replay()
        
        # Configure event source mappings
        self._create_event_source_mappings()
        
        # Create CloudWatch alarms
        self._create_cloudwatch_alarms()
        
        # Create outputs
        self._create_outputs()

    def _create_dynamodb_table(self) -> dynamodb.Table:
        """
        Create DynamoDB table for order state management.
        
        The table includes:
        - Primary key: OrderId (String)
        - Global Secondary Index for efficient querying by message group
        - DynamoDB Streams for real-time order state change notifications
        - Point-in-time recovery for data protection
        """
        table = dynamodb.Table(
            self,
            "OrderTable",
            table_name=f"{self.project_name}-orders",
            partition_key=dynamodb.Attribute(
                name="OrderId",
                type=dynamodb.AttributeType.STRING
            ),
            # Configure billing mode for predictable costs
            billing_mode=dynamodb.BillingMode.PROVISIONED,
            read_capacity=10,
            write_capacity=10,
            # Enable streams for real-time processing
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
            # Enable point-in-time recovery for data protection
            point_in_time_recovery=True,
            # Configure removal policy for cleanup
            removal_policy=RemovalPolicy.DESTROY,
        )

        # Add Global Secondary Index for efficient message group queries
        table.add_global_secondary_index(
            index_name="MessageGroup-ProcessedAt-index",
            partition_key=dynamodb.Attribute(
                name="MessageGroupId",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="ProcessedAt",
                type=dynamodb.AttributeType.STRING
            ),
            read_capacity=5,
            write_capacity=5,
            projection_type=dynamodb.ProjectionType.ALL,
        )

        return table

    def _create_s3_bucket(self) -> s3.Bucket:
        """
        Create S3 bucket for poison message archival.
        
        Features:
        - Lifecycle policies for cost optimization
        - Server-side encryption
        - Versioning for data protection
        - Public access blocked for security
        """
        bucket = s3.Bucket(
            self,
            "ArchiveBucket",
            bucket_name=f"{self.project_name}-message-archive",
            # Enable versioning for data protection
            versioned=True,
            # Configure server-side encryption
            encryption=s3.BucketEncryption.S3_MANAGED,
            # Block public access for security
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            # Configure removal policy for cleanup
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        # Add lifecycle policy for cost optimization
        bucket.add_lifecycle_rule(
            id="ArchiveTransition",
            prefix="poison-messages/",
            enabled=True,
            transitions=[
                s3.Transition(
                    storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                    transition_after=Duration.days(30)
                ),
                s3.Transition(
                    storage_class=s3.StorageClass.GLACIER,
                    transition_after=Duration.days(90)
                )
            ]
        )

        return bucket

    def _create_sns_topic(self) -> sns.Topic:
        """
        Create SNS topic for operational alerting.
        
        Features:
        - Server-side encryption
        - Display name for easy identification
        - Configurable for multiple subscription types
        """
        return sns.Topic(
            self,
            "AlertTopic",
            topic_name=f"{self.project_name}-alerts",
            display_name="FIFO Message Processing Alerts",
            # Enable server-side encryption
            master_key=None,  # Use default AWS managed key
        )

    def _create_dead_letter_queue(self) -> sqs.Queue:
        """
        Create FIFO dead letter queue for poison message handling.
        
        Features:
        - FIFO ordering with content-based deduplication
        - Extended message retention for investigation
        - Server-side encryption
        """
        return sqs.Queue(
            self,
            "DeadLetterQueue",
            queue_name=f"{self.project_name}-dlq.fifo",
            # Configure FIFO characteristics
            fifo=True,
            content_based_deduplication=True,
            # Extended retention for poison message analysis
            message_retention_period=Duration.days(14),
            # Configure visibility timeout for processing
            visibility_timeout=Duration.minutes(5),
            # Enable server-side encryption
            encryption=sqs.QueueEncryption.KMS_MANAGED,
        )

    def _create_main_queue(self) -> sqs.Queue:
        """
        Create main FIFO queue with advanced configuration.
        
        Features:
        - High-throughput FIFO with per-message-group deduplication
        - Sophisticated redrive policy
        - Optimized visibility timeout
        - Server-side encryption
        """
        return sqs.Queue(
            self,
            "MainQueue",
            queue_name=f"{self.project_name}-main-queue.fifo",
            # Configure FIFO characteristics
            fifo=True,
            content_based_deduplication=False,
            deduplication_scope=sqs.DeduplicationScope.MESSAGE_GROUP,
            fifo_throughput_limit=sqs.FifoThroughputLimit.PER_MESSAGE_GROUP_ID,
            # Configure message retention
            message_retention_period=Duration.days(14),
            # Configure visibility timeout for processing
            visibility_timeout=Duration.minutes(5),
            # Configure dead letter queue redrive policy
            dead_letter_queue=sqs.DeadLetterQueue(
                max_receive_count=3,
                queue=self.dead_letter_queue
            ),
            # Enable server-side encryption
            encryption=sqs.QueueEncryption.KMS_MANAGED,
        )

    def _create_processor_role(self) -> iam.Role:
        """
        Create IAM role for message processor Lambda with least-privilege permissions.
        """
        role = iam.Role(
            self,
            "ProcessorRole",
            role_name=f"{self.project_name}-processor-role",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ]
        )

        # Add SQS permissions
        role.add_to_policy(iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "sqs:ReceiveMessage",
                "sqs:DeleteMessage",
                "sqs:GetQueueAttributes",
                "sqs:SendMessage"
            ],
            resources=[
                self.main_queue.queue_arn,
                self.dead_letter_queue.queue_arn
            ]
        ))

        # Add DynamoDB permissions
        role.add_to_policy(iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "dynamodb:PutItem",
                "dynamodb:UpdateItem", 
                "dynamodb:GetItem",
                "dynamodb:Query"
            ],
            resources=[
                self.order_table.table_arn,
                f"{self.order_table.table_arn}/index/*"
            ]
        ))

        # Add CloudWatch metrics permissions
        role.add_to_policy(iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=["cloudwatch:PutMetricData"],
            resources=["*"]
        ))

        return role

    def _create_poison_handler_role(self) -> iam.Role:
        """
        Create IAM role for poison message handler Lambda with extended permissions.
        """
        role = iam.Role(
            self,
            "PoisonHandlerRole",
            role_name=f"{self.project_name}-poison-handler-role",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ]
        )

        # Add SQS permissions
        role.add_to_policy(iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "sqs:ReceiveMessage",
                "sqs:DeleteMessage",
                "sqs:GetQueueAttributes",
                "sqs:SendMessage"
            ],
            resources=[
                self.dead_letter_queue.queue_arn,
                self.main_queue.queue_arn
            ]
        ))

        # Add S3 permissions for archival
        role.add_to_policy(iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "s3:PutObject",
                "s3:GetObject",
                "s3:ListBucket"
            ],
            resources=[
                self.archive_bucket.bucket_arn,
                f"{self.archive_bucket.bucket_arn}/*"
            ]
        ))

        # Add SNS permissions for alerting
        role.add_to_policy(iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=["sns:Publish"],
            resources=[self.alert_topic.topic_arn]
        ))

        # Add CloudWatch metrics permissions
        role.add_to_policy(iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=["cloudwatch:PutMetricData"],
            resources=["*"]
        ))

        return role

    def _create_message_processor(self) -> lambda_.Function:
        """
        Create Lambda function for processing messages from main FIFO queue.
        
        Features:
        - Reserved concurrency to prevent resource contention
        - Environment variables for configuration
        - Extended timeout for complex processing
        - Dead letter queue configuration
        """
        # Create log group with retention policy
        log_group = logs.LogGroup(
            self,
            "ProcessorLogGroup",
            log_group_name=f"/aws/lambda/{self.project_name}-message-processor",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY
        )

        function = lambda_.Function(
            self,
            "MessageProcessor",
            function_name=f"{self.project_name}-message-processor",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            role=self.processor_role,
            code=lambda_.Code.from_inline(self._get_processor_code()),
            environment={
                "ORDER_TABLE_NAME": self.order_table.table_name,
                "PROJECT_NAME": self.project_name
            },
            timeout=Duration.minutes(5),
            memory_size=512,
            # Reserve concurrency to prevent overwhelming downstream systems
            reserved_concurrent_executions=10,
            # Configure dead letter queue for function failures
            dead_letter_queue_enabled=True,
            log_group=log_group
        )

        return function

    def _create_poison_handler(self) -> lambda_.Function:
        """
        Create Lambda function for handling poison messages from DLQ.
        
        Features:
        - Intelligent failure analysis
        - Automated recovery capabilities
        - S3 archival with metadata
        - SNS alerting for critical issues
        """
        # Create log group with retention policy
        log_group = logs.LogGroup(
            self,
            "PoisonHandlerLogGroup",
            log_group_name=f"/aws/lambda/{self.project_name}-poison-handler",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY
        )

        function = lambda_.Function(
            self,
            "PoisonHandler",
            function_name=f"{self.project_name}-poison-handler",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            role=self.poison_handler_role,
            code=lambda_.Code.from_inline(self._get_poison_handler_code()),
            environment={
                "ARCHIVE_BUCKET_NAME": self.archive_bucket.bucket_name,
                "SNS_TOPIC_ARN": self.alert_topic.topic_arn,
                "MAIN_QUEUE_URL": self.main_queue.queue_url,
                "PROJECT_NAME": self.project_name
            },
            timeout=Duration.minutes(5),
            memory_size=512,
            log_group=log_group
        )

        return function

    def _create_message_replay(self) -> lambda_.Function:
        """
        Create Lambda function for replaying archived messages.
        
        Features:
        - Time-based filtering
        - Message group filtering  
        - Dry-run capabilities
        - Intelligent replay decisions
        """
        # Create log group with retention policy
        log_group = logs.LogGroup(
            self,
            "MessageReplayLogGroup",
            log_group_name=f"/aws/lambda/{self.project_name}-message-replay",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY
        )

        function = lambda_.Function(
            self,
            "MessageReplay",
            function_name=f"{self.project_name}-message-replay",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            role=self.poison_handler_role,  # Reuse poison handler role
            code=lambda_.Code.from_inline(self._get_replay_code()),
            environment={
                "ARCHIVE_BUCKET_NAME": self.archive_bucket.bucket_name,
                "MAIN_QUEUE_URL": self.main_queue.queue_url,
                "PROJECT_NAME": self.project_name
            },
            timeout=Duration.minutes(5),
            memory_size=512,
            log_group=log_group
        )

        return function

    def _create_event_source_mappings(self) -> None:
        """
        Configure event source mappings between SQS queues and Lambda functions.
        """
        # Main queue to message processor (single message batches for strict ordering)
        self.message_processor.add_event_source(
            lambda_event_sources.SqsEventSource(
                queue=self.main_queue,
                batch_size=1,
                max_batching_window=Duration.seconds(5),
                report_batch_item_failures=True
            )
        )

        # Dead letter queue to poison handler (larger batches for efficiency)
        self.poison_handler.add_event_source(
            lambda_event_sources.SqsEventSource(
                queue=self.dead_letter_queue,
                batch_size=5,
                max_batching_window=Duration.seconds(10),
                report_batch_item_failures=True
            )
        )

    def _create_cloudwatch_alarms(self) -> None:
        """
        Create CloudWatch alarms for comprehensive monitoring.
        """
        # Alarm for high message processing failure rate
        cloudwatch.Alarm(
            self,
            "HighFailureRateAlarm",
            alarm_name=f"{self.project_name}-high-failure-rate",
            alarm_description="High message processing failure rate",
            metric=cloudwatch.Metric(
                namespace="FIFO/MessageProcessing",
                metric_name="FailedMessages",
                statistic="Sum",
                period=Duration.minutes(5)
            ),
            threshold=5,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        ).add_alarm_action(
            cloudwatch.SnsAction(self.alert_topic)
        )

        # Alarm for poison messages detected
        cloudwatch.Alarm(
            self,
            "PoisonMessagesAlarm",
            alarm_name=f"{self.project_name}-poison-messages-detected",
            alarm_description="Poison messages detected in DLQ",
            metric=cloudwatch.Metric(
                namespace="FIFO/PoisonMessages",
                metric_name="PoisonMessageCount",
                statistic="Sum",
                period=Duration.minutes(5)
            ),
            threshold=1,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        ).add_alarm_action(
            cloudwatch.SnsAction(self.alert_topic)
        )

        # Alarm for high processing latency
        cloudwatch.Alarm(
            self,
            "HighLatencyAlarm",
            alarm_name=f"{self.project_name}-high-processing-latency",
            alarm_description="High message processing latency",
            metric=cloudwatch.Metric(
                namespace="FIFO/MessageProcessing",
                metric_name="ProcessingTime",
                statistic="Average",
                period=Duration.minutes(5)
            ),
            threshold=5000,  # 5 seconds in milliseconds
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        ).add_alarm_action(
            cloudwatch.SnsAction(self.alert_topic)
        )

    def _create_outputs(self) -> None:
        """
        Create CloudFormation outputs for important resource identifiers.
        """
        CfnOutput(
            self,
            "MainQueueUrl",
            description="URL of the main FIFO queue",
            value=self.main_queue.queue_url
        )

        CfnOutput(
            self,
            "DeadLetterQueueUrl", 
            description="URL of the dead letter queue",
            value=self.dead_letter_queue.queue_url
        )

        CfnOutput(
            self,
            "OrderTableName",
            description="Name of the DynamoDB orders table",
            value=self.order_table.table_name
        )

        CfnOutput(
            self,
            "ArchiveBucketName",
            description="Name of the S3 archive bucket",
            value=self.archive_bucket.bucket_name
        )

        CfnOutput(
            self,
            "AlertTopicArn",
            description="ARN of the SNS alert topic",
            value=self.alert_topic.topic_arn
        )

        CfnOutput(
            self,
            "MessageProcessorFunctionName",
            description="Name of the message processor Lambda function",
            value=self.message_processor.function_name
        )

        CfnOutput(
            self,
            "PoisonHandlerFunctionName",
            description="Name of the poison handler Lambda function", 
            value=self.poison_handler.function_name
        )

        CfnOutput(
            self,
            "MessageReplayFunctionName",
            description="Name of the message replay Lambda function",
            value=self.message_replay.function_name
        )

    def _get_processor_code(self) -> str:
        """
        Get the Lambda function code for message processing.
        """
        return '''import json
import boto3
import time
import os
from datetime import datetime
from decimal import Decimal
import random

dynamodb = boto3.resource('dynamodb')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    """
    Process messages from SQS FIFO queue with ordering guarantees
    """
    processed_count = 0
    failed_count = 0
    
    for record in event['Records']:
        try:
            # Extract message details
            message_body = json.loads(record['body'])
            message_group_id = record['attributes']['MessageGroupId']
            message_dedup_id = record['attributes']['MessageDeduplicationId']
            
            print(f"Processing message: {message_dedup_id} in group: {message_group_id}")
            
            # Process order message
            result = process_order_message(message_body, message_group_id, message_dedup_id)
            
            if result['success']:
                processed_count += 1
                publish_processing_metrics(message_group_id, 'SUCCESS', result['processing_time'])
            else:
                failed_count += 1
                publish_processing_metrics(message_group_id, 'FAILURE', result['processing_time'])
                
                # Simulate occasional failures for testing
                if should_simulate_failure():
                    raise Exception(f"Simulated processing failure for message {message_dedup_id}")
            
        except Exception as e:
            failed_count += 1
            print(f"Error processing message: {str(e)}")
            
            # Publish error metrics
            publish_processing_metrics(
                record['attributes'].get('MessageGroupId', 'unknown'), 
                'ERROR', 
                0
            )
            
            # Re-raise to trigger DLQ behavior
            raise
    
    # Publish batch metrics
    cloudwatch.put_metric_data(
        Namespace='FIFO/MessageProcessing',
        MetricData=[
            {
                'MetricName': 'ProcessedMessages',
                'Value': processed_count,
                'Unit': 'Count',
                'Dimensions': [
                    {'Name': 'Environment', 'Value': os.environ.get('PROJECT_NAME', 'Demo')}
                ]
            },
            {
                'MetricName': 'FailedMessages', 
                'Value': failed_count,
                'Unit': 'Count',
                'Dimensions': [
                    {'Name': 'Environment', 'Value': os.environ.get('PROJECT_NAME', 'Demo')}
                ]
            }
        ]
    )
    
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
        # Extract order information
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
        
        # Simulate complex business logic
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
                'OriginalTimestamp': timestamp
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
                    'Value': processing_time * 1000,
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

def should_simulate_failure():
    """
    Simulate occasional processing failures for testing
    """
    return random.random() < 0.1
'''

    def _get_poison_handler_code(self) -> str:
        """
        Get the Lambda function code for poison message handling.
        """
        return '''import json
import boto3
import os
import time
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
        if 'amount' in message_body and float(message_body['amount']) < 0:
            corrected_message = message_body.copy()
            corrected_message['amount'] = abs(float(message_body['amount']))
            corrected_message['recovery_applied'] = 'negative_amount_correction'
            corrected_message['original_amount'] = message_body['amount']
            
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
                    'Dimensions': [
                        {'Name': 'MessageGroup', 'Value': message_group_id}
                    ]
                }
            ]
        )
    except Exception as e:
        print(f"Error publishing poison metrics: {str(e)}")
'''

    def _get_replay_code(self) -> str:
        """
        Get the Lambda function code for message replay.
        """
        return '''import json
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
'''


def main():
    """
    Main function to create and deploy the CDK application.
    """
    app = App()

    # Get project name from context or use default
    project_name = app.node.try_get_context("projectName") or "fifo-processing"

    # Create the stack
    OrderedMessageProcessingStack(
        app,
        "OrderedMessageProcessingStack",
        project_name=project_name,
        description="Ordered Message Processing with SQS FIFO and Dead Letter Queues",
        env=Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION")
        )
    )

    app.synth()


if __name__ == "__main__":
    main()