#!/usr/bin/env python3
"""
Real-time Database Change Streams with DynamoDB Streams
CDK Python Application

This CDK application creates a complete real-time database change stream processing
system using Amazon DynamoDB Streams and AWS Lambda. It demonstrates event-driven
architecture patterns for processing database changes in near real-time.

Author: AWS CDK Team
Version: 1.0
"""

import os
from typing import Dict, Any
from aws_cdk import (
    App,
    Stack,
    Duration,
    RemovalPolicy,
    CfnOutput,
    Tag,
    aws_dynamodb as dynamodb,
    aws_lambda as _lambda,
    aws_iam as iam,
    aws_s3 as s3,
    aws_sns as sns,
    aws_sqs as sqs,
    aws_cloudwatch as cloudwatch,
    aws_cloudwatch_actions as cloudwatch_actions,
    aws_lambda_event_sources as lambda_event_sources,
    aws_logs as logs,
)
from constructs import Construct


class DynamoDBStreamProcessingStack(Stack):
    """
    CDK Stack for real-time database change stream processing using DynamoDB Streams.
    
    This stack creates:
    - DynamoDB table with streams enabled
    - Lambda function for processing stream records
    - S3 bucket for audit logging
    - SNS topic for notifications
    - SQS dead letter queue for failed processing
    - CloudWatch alarms for monitoring
    - Appropriate IAM roles and policies
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names to avoid conflicts
        unique_suffix = self.node.addr[-8:].lower()

        # Create S3 bucket for audit logs
        self.audit_bucket = self._create_audit_bucket(unique_suffix)

        # Create SNS topic for notifications
        self.notification_topic = self._create_notification_topic(unique_suffix)

        # Create DynamoDB table with streams enabled
        self.table = self._create_dynamodb_table(unique_suffix)

        # Create dead letter queue for failed processing
        self.dead_letter_queue = self._create_dead_letter_queue(unique_suffix)

        # Create IAM role for Lambda function
        self.lambda_role = self._create_lambda_role()

        # Create Lambda function for stream processing
        self.stream_processor = self._create_stream_processor_function(unique_suffix)

        # Create event source mapping for DynamoDB stream
        self.event_source_mapping = self._create_event_source_mapping()

        # Create CloudWatch alarms for monitoring
        self._create_cloudwatch_alarms()

        # Create outputs for important resource identifiers
        self._create_outputs()

    def _create_audit_bucket(self, unique_suffix: str) -> s3.Bucket:
        """
        Create S3 bucket for storing audit logs of database changes.
        
        Args:
            unique_suffix: Unique suffix for bucket naming
            
        Returns:
            s3.Bucket: The created S3 bucket
        """
        bucket = s3.Bucket(
            self,
            "AuditBucket",
            bucket_name=f"activity-audit-{unique_suffix}",
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            versioning=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="AuditLogLifecycle",
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
            ],
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL
        )

        # Add tags for resource management
        bucket.add_tags(
            Environment="Production",
            Project="StreamProcessing",
            Component="AuditStorage"
        )

        return bucket

    def _create_notification_topic(self, unique_suffix: str) -> sns.Topic:
        """
        Create SNS topic for sending notifications about database changes.
        
        Args:
            unique_suffix: Unique suffix for topic naming
            
        Returns:
            sns.Topic: The created SNS topic
        """
        topic = sns.Topic(
            self,
            "NotificationTopic",
            topic_name=f"activity-notifications-{unique_suffix}",
            display_name="Database Activity Notifications",
            delivery_policy={
                "http": {
                    "defaultHealthyRetryPolicy": {
                        "minDelayTarget": 20,
                        "maxDelayTarget": 20,
                        "numRetries": 3,
                        "numMaxDelayRetries": 0,
                        "numMinDelayRetries": 0,
                        "numNoDelayRetries": 0,
                        "backoffFunction": "linear"
                    }
                }
            }
        )

        # Add tags for resource management
        topic.add_tags(
            Environment="Production",
            Project="StreamProcessing",
            Component="Notifications"
        )

        return topic

    def _create_dynamodb_table(self, unique_suffix: str) -> dynamodb.Table:
        """
        Create DynamoDB table with streams enabled for change data capture.
        
        Args:
            unique_suffix: Unique suffix for table naming
            
        Returns:
            dynamodb.Table: The created DynamoDB table
        """
        table = dynamodb.Table(
            self,
            "UserActivitiesTable",
            table_name=f"UserActivities-{unique_suffix}",
            partition_key=dynamodb.Attribute(
                name="UserId",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="ActivityId", 
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PROVISIONED,
            read_capacity=5,
            write_capacity=5,
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
            removal_policy=RemovalPolicy.DESTROY,
            encryption=dynamodb.TableEncryption.AWS_MANAGED,
            point_in_time_recovery=True
        )

        # Add tags for resource management
        table.add_tags(
            Environment="Production",
            Project="StreamProcessing",
            Component="Database"
        )

        return table

    def _create_dead_letter_queue(self, unique_suffix: str) -> sqs.Queue:
        """
        Create SQS dead letter queue for failed stream processing records.
        
        Args:
            unique_suffix: Unique suffix for queue naming
            
        Returns:
            sqs.Queue: The created SQS queue
        """
        dlq = sqs.Queue(
            self,
            "DeadLetterQueue",
            queue_name=f"stream-processor-dlq-{unique_suffix}",
            visibility_timeout=Duration.seconds(300),
            retention_period=Duration.days(14),
            encryption=sqs.QueueEncryption.SQS_MANAGED
        )

        # Add tags for resource management
        dlq.add_tags(
            Environment="Production",
            Project="StreamProcessing",
            Component="ErrorHandling"
        )

        return dlq

    def _create_lambda_role(self) -> iam.Role:
        """
        Create IAM role for Lambda function with appropriate permissions.
        
        Returns:
            iam.Role: The created IAM role
        """
        role = iam.Role(
            self,
            "StreamProcessorRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaDynamoDBExecutionRole"
                )
            ],
            inline_policies={
                "StreamProcessorPolicy": iam.PolicyDocument(
                    statements=[
                        # SNS publish permissions
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=["sns:Publish"],
                            resources=[self.notification_topic.topic_arn]
                        ),
                        # S3 audit bucket permissions
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:PutObject",
                                "s3:PutObjectAcl"
                            ],
                            resources=[f"{self.audit_bucket.bucket_arn}/*"]
                        ),
                        # SQS dead letter queue permissions
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "sqs:SendMessage",
                                "sqs:GetQueueAttributes"
                            ],
                            resources=[self.dead_letter_queue.queue_arn]
                        )
                    ]
                )
            }
        )

        return role

    def _create_stream_processor_function(self, unique_suffix: str) -> _lambda.Function:
        """
        Create Lambda function for processing DynamoDB stream records.
        
        Args:
            unique_suffix: Unique suffix for function naming
            
        Returns:
            _lambda.Function: The created Lambda function
        """
        # Lambda function code for processing stream records
        lambda_code = '''
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
    raise TypeError

def lambda_handler(event, context):
    """
    Main Lambda handler for processing DynamoDB stream records.
    
    Args:
        event: DynamoDB stream event
        context: Lambda context
        
    Returns:
        dict: Success response
    """
    logger.info(f"Processing {len(event['Records'])} stream records")
    
    for record in event['Records']:
        try:
            # Process each stream record
            process_stream_record(record)
        except Exception as e:
            logger.error(f"Error processing record: {str(e)}")
            raise e
    
    return {
        'statusCode': 200,
        'body': json.dumps(f'Successfully processed {len(event["Records"])} records')
    }

def process_stream_record(record):
    """
    Process individual DynamoDB stream record.
    
    Args:
        record: Individual stream record
    """
    event_name = record['eventName']
    user_id = record['dynamodb']['Keys']['UserId']['S']
    activity_id = record['dynamodb']['Keys']['ActivityId']['S']
    
    logger.info(f"Processing {event_name} event for user {user_id}, activity {activity_id}")
    
    # Create audit record
    audit_record = {
        'timestamp': datetime.utcnow().isoformat(),
        'eventName': event_name,
        'userId': user_id,
        'activityId': activity_id,
        'awsRegion': record['awsRegion'],
        'eventSource': record['eventSource']
    }
    
    # Add old and new images if available
    if 'OldImage' in record['dynamodb']:
        audit_record['oldImage'] = record['dynamodb']['OldImage']
    if 'NewImage' in record['dynamodb']:
        audit_record['newImage'] = record['dynamodb']['NewImage']
    
    # Store audit record in S3
    store_audit_record(audit_record)
    
    # Send notification based on event type
    if event_name == 'INSERT':
        send_notification(f"New activity created for user {user_id}", audit_record)
    elif event_name == 'MODIFY':
        send_notification(f"Activity updated for user {user_id}", audit_record)
    elif event_name == 'REMOVE':
        send_notification(f"Activity deleted for user {user_id}", audit_record)

def store_audit_record(audit_record):
    """
    Store audit record in S3 bucket.
    
    Args:
        audit_record: Audit record to store
    """
    try:
        # Generate S3 key with timestamp and user ID
        timestamp = datetime.utcnow().strftime('%Y/%m/%d/%H')
        s3_key = f"audit-logs/{timestamp}/{audit_record['userId']}-{audit_record['activityId']}.json"
        
        # Store in S3
        s3.put_object(
            Bucket=S3_BUCKET_NAME,
            Key=s3_key,
            Body=json.dumps(audit_record, default=decimal_default),
            ContentType='application/json'
        )
        
        logger.info(f"Audit record stored: s3://{S3_BUCKET_NAME}/{s3_key}")
    except Exception as e:
        logger.error(f"Failed to store audit record: {str(e)}")
        raise e

def send_notification(message, audit_record):
    """
    Send SNS notification about database change.
    
    Args:
        message: Notification message
        audit_record: Audit record details
    """
    try:
        # Send SNS notification
        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Message=json.dumps({
                'message': message,
                'details': audit_record
            }, default=decimal_default),
            Subject=f"DynamoDB Activity: {audit_record['eventName']}"
        )
        
        logger.info(f"Notification sent: {message}")
    except Exception as e:
        logger.error(f"Failed to send notification: {str(e)}")
        raise e
'''

        function = _lambda.Function(
            self,
            "StreamProcessor",
            function_name=f"stream-processor-{unique_suffix}",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline(lambda_code),
            role=self.lambda_role,
            timeout=Duration.seconds(60),
            memory_size=256,
            description="Processes DynamoDB stream records for real-time change data capture",
            environment={
                "SNS_TOPIC_ARN": self.notification_topic.topic_arn,
                "S3_BUCKET_NAME": self.audit_bucket.bucket_name
            },
            dead_letter_queue=self.dead_letter_queue,
            log_retention=logs.RetentionDays.TWO_WEEKS,
            tracing=_lambda.Tracing.ACTIVE
        )

        # Add tags for resource management
        function.add_tags(
            Environment="Production",
            Project="StreamProcessing",
            Component="StreamProcessor"
        )

        return function

    def _create_event_source_mapping(self) -> lambda_event_sources.DynamoEventSource:
        """
        Create event source mapping between DynamoDB stream and Lambda function.
        
        Returns:
            lambda_event_sources.DynamoEventSource: The created event source mapping
        """
        event_source = lambda_event_sources.DynamoEventSource(
            table=self.table,
            starting_position=_lambda.StartingPosition.LATEST,
            batch_size=10,
            max_batching_window=Duration.seconds(5),
            max_record_age=Duration.hours(1),
            bisect_batch_on_error=True,
            retry_attempts=3,
            parallelization_factor=2,
            report_batch_item_failures=True
        )

        # Add event source to Lambda function
        self.stream_processor.add_event_source(event_source)

        return event_source

    def _create_cloudwatch_alarms(self) -> None:
        """Create CloudWatch alarms for monitoring stream processing health."""
        
        # Lambda function error alarm
        lambda_error_alarm = cloudwatch.Alarm(
            self,
            "LambdaErrorAlarm",
            alarm_name=f"{self.stream_processor.function_name}-errors",
            alarm_description="Lambda function errors",
            metric=self.stream_processor.metric_errors(
                period=Duration.minutes(5)
            ),
            threshold=1,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD
        )

        # Add SNS notification to alarm
        lambda_error_alarm.add_alarm_action(
            cloudwatch_actions.SnsAction(self.notification_topic)
        )

        # Dead letter queue message alarm
        dlq_message_alarm = cloudwatch.Alarm(
            self,
            "DLQMessageAlarm",
            alarm_name=f"{self.dead_letter_queue.queue_name}-messages",
            alarm_description="Dead letter queue messages",
            metric=self.dead_letter_queue.metric_approximate_number_of_visible_messages(
                period=Duration.minutes(5)
            ),
            threshold=1,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD
        )

        # Add SNS notification to alarm
        dlq_message_alarm.add_alarm_action(
            cloudwatch_actions.SnsAction(self.notification_topic)
        )

        # Lambda duration alarm
        lambda_duration_alarm = cloudwatch.Alarm(
            self,
            "LambdaDurationAlarm",
            alarm_name=f"{self.stream_processor.function_name}-duration",
            alarm_description="Lambda function high duration",
            metric=self.stream_processor.metric_duration(
                period=Duration.minutes(5)
            ),
            threshold=45000,  # 45 seconds
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD
        )

        # Add SNS notification to alarm
        lambda_duration_alarm.add_alarm_action(
            cloudwatch_actions.SnsAction(self.notification_topic)
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource identifiers."""
        
        CfnOutput(
            self,
            "DynamoDBTableName",
            value=self.table.table_name,
            description="Name of the DynamoDB table with streams enabled",
            export_name="DynamoDBTableName"
        )

        CfnOutput(
            self,
            "DynamoDBStreamArn",
            value=self.table.table_stream_arn or "Stream not available",
            description="ARN of the DynamoDB stream",
            export_name="DynamoDBStreamArn"
        )

        CfnOutput(
            self,
            "LambdaFunctionName",
            value=self.stream_processor.function_name,
            description="Name of the Lambda function processing stream records",
            export_name="LambdaFunctionName"
        )

        CfnOutput(
            self,
            "LambdaFunctionArn",
            value=self.stream_processor.function_arn,
            description="ARN of the Lambda function processing stream records",
            export_name="LambdaFunctionArn"
        )

        CfnOutput(
            self,
            "SNSTopicArn",
            value=self.notification_topic.topic_arn,
            description="ARN of the SNS topic for notifications",
            export_name="SNSTopicArn"
        )

        CfnOutput(
            self,
            "S3BucketName",
            value=self.audit_bucket.bucket_name,
            description="Name of the S3 bucket for audit logs",
            export_name="S3BucketName"
        )

        CfnOutput(
            self,
            "DeadLetterQueueUrl",
            value=self.dead_letter_queue.queue_url,
            description="URL of the dead letter queue for failed processing",
            export_name="DeadLetterQueueUrl"
        )


def main() -> None:
    """Main application entry point."""
    app = App()
    
    # Create the main stack
    DynamoDBStreamProcessingStack(
        app,
        "DynamoDBStreamProcessingStack",
        description="Real-time Database Change Streams with DynamoDB Streams",
        env={
            'account': os.environ.get('CDK_DEFAULT_ACCOUNT'),
            'region': os.environ.get('CDK_DEFAULT_REGION')
        }
    )
    
    # Add application-level tags
    app.node.apply_aspect(
        Tag("Application", "DynamoDBStreamProcessing")
    )
    app.node.apply_aspect(
        Tag("CreatedBy", "CDK")
    )
    
    app.synth()


if __name__ == "__main__":
    main()