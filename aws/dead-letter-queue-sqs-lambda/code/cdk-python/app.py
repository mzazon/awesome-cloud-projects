#!/usr/bin/env python3
"""
Dead Letter Queue Processing with SQS - CDK Python Application

This CDK application creates a comprehensive dead letter queue processing system
using Amazon SQS and AWS Lambda for resilient message processing with intelligent
error handling and automated recovery workflows.

Architecture:
- Main SQS queue for order processing
- Dead letter queue (DLQ) for failed messages  
- Lambda function for main order processing
- Lambda function for DLQ monitoring and analysis
- CloudWatch alarms for proactive monitoring
- IAM roles with least privilege permissions
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_sqs as sqs,
    aws_lambda as _lambda,
    aws_lambda_event_sources as lambda_event_sources,
    aws_iam as iam,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
    Duration,
    RemovalPolicy,
    CfnOutput,
)
from constructs import Construct
from typing import Dict, Any


class DeadLetterQueueProcessingStack(Stack):
    """
    CDK Stack for Dead Letter Queue Processing with SQS
    
    This stack implements a resilient message processing system with:
    - Automatic retry mechanisms
    - Dead letter queue for failed messages
    - Intelligent error analysis and categorization
    - CloudWatch monitoring and alarms
    - Automated recovery workflows
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        unique_suffix = cdk.Names.unique_id(self)[:8].lower()

        # Create the Dead Letter Queue first
        self.dead_letter_queue = self._create_dead_letter_queue(unique_suffix)
        
        # Create the main processing queue with DLQ configuration
        self.main_queue = self._create_main_queue(unique_suffix)
        
        # Create IAM role for Lambda functions
        self.lambda_role = self._create_lambda_role(unique_suffix)
        
        # Create Lambda functions
        self.order_processor = self._create_order_processor_function(unique_suffix)
        self.dlq_monitor = self._create_dlq_monitor_function(unique_suffix)
        
        # Configure event source mappings
        self._configure_event_source_mappings()
        
        # Create CloudWatch alarms
        self._create_cloudwatch_alarms(unique_suffix)
        
        # Create outputs
        self._create_outputs()

    def _create_dead_letter_queue(self, suffix: str) -> sqs.Queue:
        """
        Create the dead letter queue for capturing failed messages
        
        Args:
            suffix: Unique suffix for resource names
            
        Returns:
            sqs.Queue: The configured dead letter queue
        """
        return sqs.Queue(
            self, "DeadLetterQueue",
            queue_name=f"order-processing-dlq-{suffix}",
            # 14-day message retention for thorough error analysis
            message_retention_period=Duration.days(14),
            # 5-minute visibility timeout for error processing
            visibility_timeout=Duration.minutes(5),
            # Enable server-side encryption
            encryption=sqs.QueueEncryption.KMS_MANAGED,
            # Apply removal policy for cleanup
            removal_policy=RemovalPolicy.DESTROY
        )

    def _create_main_queue(self, suffix: str) -> sqs.Queue:
        """
        Create the main processing queue with dead letter queue configuration
        
        Args:
            suffix: Unique suffix for resource names
            
        Returns:
            sqs.Queue: The configured main processing queue
        """
        return sqs.Queue(
            self, "MainProcessingQueue",
            queue_name=f"order-processing-{suffix}",
            # 14-day message retention period
            message_retention_period=Duration.days(14),
            # 5-minute visibility timeout for processing
            visibility_timeout=Duration.minutes(5),
            # Dead letter queue configuration - 3 retries before DLQ
            dead_letter_queue=sqs.DeadLetterQueue(
                max_receive_count=3,
                queue=self.dead_letter_queue
            ),
            # Enable server-side encryption
            encryption=sqs.QueueEncryption.KMS_MANAGED,
            # Apply removal policy for cleanup
            removal_policy=RemovalPolicy.DESTROY
        )

    def _create_lambda_role(self, suffix: str) -> iam.Role:
        """
        Create IAM role for Lambda functions with least privilege permissions
        
        Args:
            suffix: Unique suffix for resource names
            
        Returns:
            iam.Role: The configured IAM role
        """
        role = iam.Role(
            self, "LambdaExecutionRole",
            role_name=f"dlq-processing-role-{suffix}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ]
        )

        # Add SQS permissions for both queues
        role.add_to_policy(
            iam.PolicyStatement(
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
            )
        )

        # Add CloudWatch permissions for custom metrics
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "cloudwatch:PutMetricData"
                ],
                resources=["*"]
            )
        )

        return role

    def _create_order_processor_function(self, suffix: str) -> _lambda.Function:
        """
        Create the main order processing Lambda function
        
        Args:
            suffix: Unique suffix for resource names
            
        Returns:
            _lambda.Function: The configured Lambda function
        """
        return _lambda.Function(
            self, "OrderProcessorFunction",
            function_name=f"order-processor-{suffix}",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            role=self.lambda_role,
            timeout=Duration.seconds(30),
            memory_size=128,
            # Inline code for the main processor
            code=_lambda.Code.from_inline("""
import json
import logging
import random
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    '''
    Main order processing function that simulates processing failures
    '''
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
            """),
            # Configure log retention
            log_retention=logs.RetentionDays.ONE_WEEK,
            # Apply removal policy for cleanup
            current_version_options=_lambda.VersionOptions(
                removal_policy=RemovalPolicy.DESTROY
            )
        )

    def _create_dlq_monitor_function(self, suffix: str) -> _lambda.Function:
        """
        Create the DLQ monitoring and analysis Lambda function
        
        Args:
            suffix: Unique suffix for resource names
            
        Returns:
            _lambda.Function: The configured Lambda function
        """
        return _lambda.Function(
            self, "DLQMonitorFunction",
            function_name=f"dlq-monitor-{suffix}",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            role=self.lambda_role,
            timeout=Duration.seconds(60),
            memory_size=256,
            environment={
                "MAIN_QUEUE_URL": self.main_queue.queue_url
            },
            # Inline code for DLQ monitoring
            code=_lambda.Code.from_inline("""
import json
import logging
import boto3
import os
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

sqs = boto3.client('sqs')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    '''
    Monitor and analyze messages in the dead letter queue
    '''
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
    '''Categorize the type of error for better analysis'''
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
    '''Determine if a message should be retried'''
    # Retry logic based on error count and order characteristics
    max_retries = 2
    order_value = message_body.get('orderValue', 0)
    
    # High-value orders get more retry attempts
    if order_value > 1000:
        max_retries = 5
    
    return error_count < max_retries

def send_to_retry_queue(message_body):
    '''Send message back to main queue for retry'''
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
            """),
            # Configure log retention
            log_retention=logs.RetentionDays.ONE_WEEK,
            # Apply removal policy for cleanup
            current_version_options=_lambda.VersionOptions(
                removal_policy=RemovalPolicy.DESTROY
            )
        )

    def _configure_event_source_mappings(self) -> None:
        """Configure SQS event source mappings for Lambda functions"""
        
        # Main queue event source mapping
        self.order_processor.add_event_source(
            lambda_event_sources.SqsEventSource(
                self.main_queue,
                batch_size=10,
                max_batching_window=Duration.seconds(5),
                # Enable partial batch failure handling
                report_batch_item_failures=True
            )
        )
        
        # DLQ event source mapping
        self.dlq_monitor.add_event_source(
            lambda_event_sources.SqsEventSource(
                self.dead_letter_queue,
                batch_size=5,
                max_batching_window=Duration.seconds(10),
                # Enable partial batch failure handling
                report_batch_item_failures=True
            )
        )

    def _create_cloudwatch_alarms(self, suffix: str) -> None:
        """
        Create CloudWatch alarms for proactive monitoring
        
        Args:
            suffix: Unique suffix for resource names
        """
        
        # Alarm for DLQ message count
        cloudwatch.Alarm(
            self, "DLQMessageCountAlarm",
            alarm_name=f"DLQ-Messages-{suffix}",
            alarm_description="Alert when messages appear in DLQ",
            metric=self.dead_letter_queue.metric_approximate_number_of_visible_messages(),
            threshold=1,
            evaluation_periods=1,
            period=Duration.minutes(5),
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD
        )
        
        # Alarm for high error rate using custom metric
        error_rate_metric = cloudwatch.Metric(
            namespace="DLQ/Processing",
            metric_name="FailedMessages",
            statistic="Sum",
            period=Duration.minutes(5)
        )
        
        cloudwatch.Alarm(
            self, "DLQErrorRateAlarm",
            alarm_name=f"DLQ-ErrorRate-{suffix}",
            alarm_description="Alert on high error rate",
            metric=error_rate_metric,
            threshold=5,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources"""
        
        CfnOutput(
            self, "MainQueueUrl",
            value=self.main_queue.queue_url,
            description="URL of the main processing queue",
            export_name=f"{self.stack_name}-MainQueueUrl"
        )
        
        CfnOutput(
            self, "MainQueueArn",
            value=self.main_queue.queue_arn,
            description="ARN of the main processing queue",
            export_name=f"{self.stack_name}-MainQueueArn"
        )
        
        CfnOutput(
            self, "DeadLetterQueueUrl",
            value=self.dead_letter_queue.queue_url,
            description="URL of the dead letter queue",
            export_name=f"{self.stack_name}-DeadLetterQueueUrl"
        )
        
        CfnOutput(
            self, "DeadLetterQueueArn",
            value=self.dead_letter_queue.queue_arn,
            description="ARN of the dead letter queue",
            export_name=f"{self.stack_name}-DeadLetterQueueArn"
        )
        
        CfnOutput(
            self, "OrderProcessorFunctionArn",
            value=self.order_processor.function_arn,
            description="ARN of the order processor Lambda function",
            export_name=f"{self.stack_name}-OrderProcessorFunctionArn"
        )
        
        CfnOutput(
            self, "DLQMonitorFunctionArn",
            value=self.dlq_monitor.function_arn,
            description="ARN of the DLQ monitor Lambda function",
            export_name=f"{self.stack_name}-DLQMonitorFunctionArn"
        )


# CDK Application
app = cdk.App()

# Create the stack
DeadLetterQueueProcessingStack(
    app, 
    "DeadLetterQueueProcessingStack",
    description="Dead Letter Queue Processing with SQS - Resilient message processing with automated error handling",
    env=cdk.Environment(
        account=app.node.try_get_context("account"),
        region=app.node.try_get_context("region")
    )
)

# Synthesize the CloudFormation template
app.synth()