#!/usr/bin/env python3
"""
CDK Python Application for Event-Driven Data Processing with S3 Event Notifications

This application creates a complete event-driven data processing pipeline using:
- Amazon S3 for data storage and event notifications
- AWS Lambda for data processing and error handling
- Amazon SQS for dead letter queue functionality
- Amazon SNS for alerting and notifications
- Amazon CloudWatch for monitoring and alarms

The architecture automatically processes files uploaded to S3 and provides
comprehensive error handling and monitoring capabilities.
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    aws_s3 as s3,
    aws_lambda as _lambda,
    aws_sqs as sqs,
    aws_sns as sns,
    aws_sns_subscriptions as subscriptions,
    aws_iam as iam,
    aws_cloudwatch as cloudwatch,
    aws_cloudwatch_actions as cw_actions,
    aws_lambda_event_sources as lambda_event_sources,
    aws_s3_notifications as s3_notifications,
)
from constructs import Construct
import os
from typing import Optional


class EventDrivenDataProcessingStack(Stack):
    """
    CDK Stack for Event-Driven Data Processing with S3 Event Notifications
    
    This stack creates a complete serverless data processing pipeline that automatically
    processes files uploaded to S3 using Lambda functions, with comprehensive error
    handling and monitoring capabilities.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        unique_suffix = self.node.try_get_context("unique_suffix") or "demo"
        
        # Create SNS topic for alerting
        self.alert_topic = self._create_alert_topic(unique_suffix)
        
        # Create Dead Letter Queue
        self.dead_letter_queue = self._create_dead_letter_queue(unique_suffix)
        
        # Create S3 bucket for data processing
        self.data_bucket = self._create_data_bucket(unique_suffix)
        
        # Create IAM role for Lambda functions
        self.lambda_role = self._create_lambda_execution_role()
        
        # Create data processing Lambda function
        self.data_processor = self._create_data_processor_function(unique_suffix)
        
        # Create error handler Lambda function
        self.error_handler = self._create_error_handler_function(unique_suffix)
        
        # Configure S3 event notifications
        self._configure_s3_event_notifications()
        
        # Configure SQS event source for error handler
        self._configure_error_handler_event_source()
        
        # Create CloudWatch alarms
        self._create_cloudwatch_alarms()
        
        # Create stack outputs
        self._create_outputs()

    def _create_alert_topic(self, unique_suffix: str) -> sns.Topic:
        """Create SNS topic for error notifications and alerts"""
        topic = sns.Topic(
            self, "DataProcessingAlerts",
            topic_name=f"data-processing-alerts-{unique_suffix}",
            display_name="Data Processing Alerts",
            description="SNS topic for data processing error notifications and alerts"
        )
        
        # Add email subscription if email is provided via context
        email = self.node.try_get_context("alert_email")
        if email:
            topic.add_subscription(
                subscriptions.EmailSubscription(email)
            )
        
        cdk.Tags.of(topic).add("Purpose", "DataProcessingAlerts")
        return topic

    def _create_dead_letter_queue(self, unique_suffix: str) -> sqs.Queue:
        """Create SQS Dead Letter Queue for failed processing events"""
        dlq = sqs.Queue(
            self, "DataProcessingDLQ",
            queue_name=f"data-processing-dlq-{unique_suffix}",
            visibility_timeout=Duration.seconds(300),
            message_retention_period=Duration.days(14),
            description="Dead Letter Queue for failed data processing events"
        )
        
        cdk.Tags.of(dlq).add("Purpose", "DataProcessingDLQ")
        return dlq

    def _create_data_bucket(self, unique_suffix: str) -> s3.Bucket:
        """Create S3 bucket for data processing with versioning enabled"""
        bucket = s3.Bucket(
            self, "DataProcessingBucket",
            bucket_name=f"data-processing-{unique_suffix}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,  # For demo purposes - remove in production
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DataProcessingLifecycle",
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
            ]
        )
        
        cdk.Tags.of(bucket).add("Purpose", "DataProcessing")
        return bucket

    def _create_lambda_execution_role(self) -> iam.Role:
        """Create IAM role for Lambda functions with necessary permissions"""
        role = iam.Role(
            self, "DataProcessingLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Execution role for data processing Lambda functions",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ]
        )
        
        # Add custom inline policy for S3, SQS, and SNS access
        policy_statement = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:GetObjectVersion"
            ],
            resources=[f"{self.data_bucket.bucket_arn}/*"]
        )
        
        dlq_policy_statement = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "sqs:SendMessage",
                "sqs:GetQueueAttributes",
                "sqs:ReceiveMessage",
                "sqs:DeleteMessage"
            ],
            resources=[self.dead_letter_queue.queue_arn]
        )
        
        sns_policy_statement = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=["sns:Publish"],
            resources=[self.alert_topic.topic_arn]
        )
        
        role.add_to_policy(policy_statement)
        role.add_to_policy(dlq_policy_statement)
        role.add_to_policy(sns_policy_statement)
        
        return role

    def _create_data_processor_function(self, unique_suffix: str) -> _lambda.Function:
        """Create Lambda function for processing data files"""
        function = _lambda.Function(
            self, "DataProcessorFunction",
            function_name=f"data-processor-{unique_suffix}",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline(self._get_data_processor_code()),
            timeout=Duration.seconds(300),
            memory_size=512,
            role=self.lambda_role,
            environment={
                "DLQ_URL": self.dead_letter_queue.queue_url,
                "BUCKET_NAME": self.data_bucket.bucket_name,
                "SNS_TOPIC_ARN": self.alert_topic.topic_arn
            },
            dead_letter_queue=self.dead_letter_queue,
            description="Lambda function for processing data files uploaded to S3"
        )
        
        cdk.Tags.of(function).add("Purpose", "DataProcessor")
        return function

    def _create_error_handler_function(self, unique_suffix: str) -> _lambda.Function:
        """Create Lambda function for handling processing errors"""
        function = _lambda.Function(
            self, "ErrorHandlerFunction",
            function_name=f"error-handler-{unique_suffix}",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline(self._get_error_handler_code()),
            timeout=Duration.seconds(60),
            memory_size=256,
            role=self.lambda_role,
            environment={
                "SNS_TOPIC_ARN": self.alert_topic.topic_arn
            },
            description="Lambda function for processing error messages from DLQ"
        )
        
        cdk.Tags.of(function).add("Purpose", "ErrorHandler")
        return function

    def _configure_s3_event_notifications(self) -> None:
        """Configure S3 event notifications to trigger data processing"""
        # Add S3 event notification for data processing
        self.data_bucket.add_event_notification(
            s3.EventType.OBJECT_CREATED,
            s3_notifications.LambdaDestination(self.data_processor),
            s3.NotificationKeyFilter(prefix="data/")
        )

    def _configure_error_handler_event_source(self) -> None:
        """Configure SQS event source for error handler Lambda"""
        self.error_handler.add_event_source(
            lambda_event_sources.SqsEventSource(
                self.dead_letter_queue,
                batch_size=10,
                max_batching_window=Duration.seconds(5)
            )
        )

    def _create_cloudwatch_alarms(self) -> None:
        """Create CloudWatch alarms for monitoring"""
        # Alarm for Lambda function errors
        lambda_error_alarm = cloudwatch.Alarm(
            self, "DataProcessorErrorAlarm",
            alarm_name=f"{self.data_processor.function_name}-errors",
            alarm_description="Monitor data processor Lambda function errors",
            metric=self.data_processor.metric_errors(
                period=Duration.minutes(5),
                statistic="Sum"
            ),
            threshold=1,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD
        )
        
        # Add SNS action to alarm
        lambda_error_alarm.add_alarm_action(
            cw_actions.SnsAction(self.alert_topic)
        )
        
        # Alarm for DLQ message count
        dlq_alarm = cloudwatch.Alarm(
            self, "DLQMessageAlarm",
            alarm_name=f"{self.dead_letter_queue.queue_name}-messages",
            alarm_description="Monitor DLQ message count",
            metric=self.dead_letter_queue.metric_approximate_number_of_visible_messages(
                period=Duration.minutes(5),
                statistic="Average"
            ),
            threshold=5,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD
        )
        
        # Add SNS action to DLQ alarm
        dlq_alarm.add_alarm_action(
            cw_actions.SnsAction(self.alert_topic)
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources"""
        cdk.CfnOutput(
            self, "DataBucketName",
            value=self.data_bucket.bucket_name,
            description="Name of the S3 bucket for data processing"
        )
        
        cdk.CfnOutput(
            self, "DataProcessorFunctionName",
            value=self.data_processor.function_name,
            description="Name of the data processor Lambda function"
        )
        
        cdk.CfnOutput(
            self, "ErrorHandlerFunctionName",
            value=self.error_handler.function_name,
            description="Name of the error handler Lambda function"
        )
        
        cdk.CfnOutput(
            self, "AlertTopicArn",
            value=self.alert_topic.topic_arn,
            description="ARN of the SNS topic for alerts"
        )
        
        cdk.CfnOutput(
            self, "DLQUrl",
            value=self.dead_letter_queue.queue_url,
            description="URL of the Dead Letter Queue"
        )

    def _get_data_processor_code(self) -> str:
        """Return the Python code for the data processor Lambda function"""
        return '''import json
import boto3
import urllib.parse
from datetime import datetime
import os
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
s3 = boto3.client('s3')
sqs = boto3.client('sqs')
sns = boto3.client('sns')

def lambda_handler(event, context):
    """
    Lambda handler for processing S3 event notifications
    
    Args:
        event: S3 event notification
        context: Lambda context
        
    Returns:
        dict: Response with status code and message
    """
    try:
        # Process each S3 event record
        for record in event['Records']:
            bucket = record['s3']['bucket']['name']
            key = urllib.parse.unquote_plus(record['s3']['object']['key'])
            
            logger.info(f"Processing object: {key} from bucket: {bucket}")
            
            # Get object metadata
            response = s3.head_object(Bucket=bucket, Key=key)
            file_size = response['ContentLength']
            
            # Process based on file type
            if key.endswith('.csv'):
                process_csv_file(bucket, key, file_size)
            elif key.endswith('.json'):
                process_json_file(bucket, key, file_size)
            elif key.endswith('.txt'):
                process_text_file(bucket, key, file_size)
            else:
                logger.warning(f"Unsupported file type: {key}")
                continue
            
            # Create processing report
            create_processing_report(bucket, key, file_size)
            
        return {
            'statusCode': 200,
            'body': json.dumps('Successfully processed S3 events')
        }
        
    except Exception as e:
        logger.error(f"Error processing S3 event: {str(e)}")
        # Send to DLQ for retry logic
        send_to_dlq(event, str(e))
        # Also send immediate alert
        send_alert(f"Data processing failed: {str(e)}")
        raise e

def process_csv_file(bucket, key, file_size):
    """Process CSV files - implement your business logic here"""
    logger.info(f"Processing CSV file: {key} (Size: {file_size} bytes)")
    
    # Download and process the CSV file
    try:
        response = s3.get_object(Bucket=bucket, Key=key)
        content = response['Body'].read().decode('utf-8')
        
        # Basic CSV processing - count rows
        lines = content.strip().split('\\n')
        row_count = len(lines) - 1  # Subtract header row
        
        logger.info(f"Processed CSV with {row_count} data rows")
        
        # Store processed result
        processed_key = f"processed/{key.replace('.csv', '_processed.json')}"
        processed_data = {
            'original_file': key,
            'row_count': row_count,
            'file_size': file_size,
            'processing_timestamp': datetime.now().isoformat()
        }
        
        s3.put_object(
            Bucket=bucket,
            Key=processed_key,
            Body=json.dumps(processed_data),
            ContentType='application/json'
        )
        
    except Exception as e:
        logger.error(f"Error processing CSV file {key}: {str(e)}")
        raise e

def process_json_file(bucket, key, file_size):
    """Process JSON files - implement your business logic here"""
    logger.info(f"Processing JSON file: {key} (Size: {file_size} bytes)")
    
    try:
        response = s3.get_object(Bucket=bucket, Key=key)
        content = response['Body'].read().decode('utf-8')
        
        # Parse and validate JSON
        data = json.loads(content)
        
        # Basic JSON processing - count keys
        if isinstance(data, dict):
            key_count = len(data.keys())
        elif isinstance(data, list):
            key_count = len(data)
        else:
            key_count = 1
        
        logger.info(f"Processed JSON with {key_count} elements")
        
        # Store processed result
        processed_key = f"processed/{key.replace('.json', '_processed.json')}"
        processed_data = {
            'original_file': key,
            'element_count': key_count,
            'file_size': file_size,
            'processing_timestamp': datetime.now().isoformat()
        }
        
        s3.put_object(
            Bucket=bucket,
            Key=processed_key,
            Body=json.dumps(processed_data),
            ContentType='application/json'
        )
        
    except Exception as e:
        logger.error(f"Error processing JSON file {key}: {str(e)}")
        raise e

def process_text_file(bucket, key, file_size):
    """Process text files - implement your business logic here"""
    logger.info(f"Processing text file: {key} (Size: {file_size} bytes)")
    
    try:
        response = s3.get_object(Bucket=bucket, Key=key)
        content = response['Body'].read().decode('utf-8')
        
        # Basic text processing - count words and lines
        lines = content.strip().split('\\n')
        words = content.split()
        
        logger.info(f"Processed text with {len(lines)} lines and {len(words)} words")
        
        # Store processed result
        processed_key = f"processed/{key.replace('.txt', '_processed.json')}"
        processed_data = {
            'original_file': key,
            'line_count': len(lines),
            'word_count': len(words),
            'file_size': file_size,
            'processing_timestamp': datetime.now().isoformat()
        }
        
        s3.put_object(
            Bucket=bucket,
            Key=processed_key,
            Body=json.dumps(processed_data),
            ContentType='application/json'
        )
        
    except Exception as e:
        logger.error(f"Error processing text file {key}: {str(e)}")
        raise e

def create_processing_report(bucket, key, file_size):
    """Create a processing report and store it in S3"""
    report_key = f"reports/{key}-report-{datetime.now().strftime('%Y%m%d%H%M%S')}.json"
    
    report = {
        'file_processed': key,
        'file_size': file_size,
        'processing_time': datetime.now().isoformat(),
        'status': 'completed',
        'processor': 'lambda-data-processor'
    }
    
    try:
        s3.put_object(
            Bucket=bucket,
            Key=report_key,
            Body=json.dumps(report, indent=2),
            ContentType='application/json'
        )
        
        logger.info(f"Processing report created: {report_key}")
    except Exception as e:
        logger.error(f"Error creating processing report: {str(e)}")

def send_to_dlq(event, error_message):
    """Send failed event to DLQ for retry"""
    dlq_url = os.environ.get('DLQ_URL')
    
    if dlq_url:
        try:
            message = {
                'original_event': event,
                'error_message': error_message,
                'timestamp': datetime.now().isoformat(),
                'retry_count': 0
            }
            
            sqs.send_message(
                QueueUrl=dlq_url,
                MessageBody=json.dumps(message)
            )
            
            logger.info("Failed event sent to DLQ")
        except Exception as e:
            logger.error(f"Error sending to DLQ: {str(e)}")

def send_alert(message):
    """Send immediate alert via SNS"""
    sns_topic_arn = os.environ.get('SNS_TOPIC_ARN')
    
    if sns_topic_arn:
        try:
            sns.publish(
                TopicArn=sns_topic_arn,
                Message=message,
                Subject='Data Processing Alert'
            )
            logger.info("Alert sent via SNS")
        except Exception as e:
            logger.error(f"Error sending alert: {str(e)}")
'''

    def _get_error_handler_code(self) -> str:
        """Return the Python code for the error handler Lambda function"""
        return '''import json
import boto3
from datetime import datetime
import os
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
sns = boto3.client('sns')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    """
    Lambda handler for processing messages from DLQ
    
    Args:
        event: SQS event from DLQ
        context: Lambda context
        
    Returns:
        dict: Response with status code and message
    """
    try:
        # Process SQS messages from DLQ
        for record in event['Records']:
            message_body = json.loads(record['body'])
            
            # Extract error details
            error_message = message_body.get('error_message', 'Unknown error')
            timestamp = message_body.get('timestamp', datetime.now().isoformat())
            original_event = message_body.get('original_event', {})
            retry_count = message_body.get('retry_count', 0)
            
            logger.info(f"Processing error message: {error_message}")
            
            # Create detailed error report
            error_report = create_error_report(original_event, error_message, timestamp, retry_count)
            
            # Send detailed alert via SNS
            send_detailed_alert(error_report)
            
            # Log error details
            logger.error(f"Processing failed for event: {json.dumps(original_event, indent=2)}")
            logger.error(f"Error: {error_message}")
            
        return {
            'statusCode': 200,
            'body': json.dumps('Error handling completed')
        }
        
    except Exception as e:
        logger.error(f"Error in error handler: {str(e)}")
        raise e

def create_error_report(original_event, error_message, timestamp, retry_count):
    """Create a comprehensive error report"""
    
    # Extract S3 object details if available
    s3_details = {}
    if 'Records' in original_event:
        for record in original_event['Records']:
            if 's3' in record:
                s3_details = {
                    'bucket': record['s3']['bucket']['name'],
                    'key': record['s3']['object']['key'],
                    'size': record['s3']['object']['size'],
                    'event_name': record['eventName']
                }
                break
    
    error_report = {
        'error_id': f"error-{datetime.now().strftime('%Y%m%d%H%M%S')}",
        'timestamp': timestamp,
        'error_message': error_message,
        'retry_count': retry_count,
        's3_object_details': s3_details,
        'original_event': original_event,
        'severity': 'HIGH' if retry_count > 2 else 'MEDIUM',
        'investigation_notes': 'Requires manual investigation'
    }
    
    return error_report

def send_detailed_alert(error_report):
    """Send detailed alert via SNS"""
    sns_topic_arn = os.environ.get('SNS_TOPIC_ARN')
    
    if sns_topic_arn:
        try:
            # Create human-readable alert message
            alert_message = f"""
Data Processing Error Alert

Error ID: {error_report['error_id']}
Timestamp: {error_report['timestamp']}
Severity: {error_report['severity']}

Error Details:
{error_report['error_message']}

S3 Object Details:
"""
            
            if error_report['s3_object_details']:
                s3_details = error_report['s3_object_details']
                alert_message += f"""
- Bucket: {s3_details.get('bucket', 'N/A')}
- Key: {s3_details.get('key', 'N/A')}
- Size: {s3_details.get('size', 'N/A')} bytes
- Event: {s3_details.get('event_name', 'N/A')}
"""
            else:
                alert_message += "\\nNo S3 object details available"
            
            alert_message += f"""

Retry Count: {error_report['retry_count']}

Action Required: {error_report['investigation_notes']}

Please investigate the failed processing job and take appropriate action.
"""
            
            # Send the alert
            sns.publish(
                TopicArn=sns_topic_arn,
                Message=alert_message,
                Subject=f"Data Processing Error Alert - {error_report['severity']} Priority"
            )
            
            logger.info(f"Detailed error alert sent for error ID: {error_report['error_id']}")
            
        except Exception as e:
            logger.error(f"Error sending detailed alert: {str(e)}")

def store_error_report(error_report):
    """Store error report in S3 for analysis"""
    try:
        # This would require the bucket name to be passed as an environment variable
        # For now, we'll just log it
        logger.info(f"Error report: {json.dumps(error_report, indent=2)}")
        
        # In a production environment, you might want to store this in a dedicated
        # error reporting bucket or database for analysis
        
    except Exception as e:
        logger.error(f"Error storing error report: {str(e)}")
'''


# CDK App
app = cdk.App()

# Create the stack
EventDrivenDataProcessingStack(
    app, 
    "EventDrivenDataProcessingStack",
    description="Event-driven data processing pipeline with S3 event notifications",
    env=cdk.Environment(
        account=os.environ.get('CDK_DEFAULT_ACCOUNT'),
        region=os.environ.get('CDK_DEFAULT_REGION')
    )
)

# Synthesize the app
app.synth()