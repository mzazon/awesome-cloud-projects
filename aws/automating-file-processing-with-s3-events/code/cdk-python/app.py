#!/usr/bin/env python3
"""
CDK Python application for S3 Event Notifications and Automated Processing.

This application creates an event-driven architecture using S3 event notifications
to trigger automated processing workflows. It includes:
- S3 bucket with event notifications
- Lambda function for immediate processing
- SQS queue for batch processing
- SNS topic for multi-subscriber notifications
- Proper IAM roles and policies
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    aws_s3 as s3,
    aws_lambda as lambda_,
    aws_sqs as sqs,
    aws_sns as sns,
    aws_sns_subscriptions as sns_subscriptions,
    aws_iam as iam,
    aws_logs as logs,
    aws_s3_notifications as s3_notifications,
)
from constructs import Construct
from typing import Dict, Any


class S3EventProcessingStack(Stack):
    """
    CDK Stack for S3 Event Notifications and Automated Processing.
    
    This stack creates a complete event-driven architecture for processing
    files uploaded to S3 with multiple processing pathways based on upload location.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs: Any) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        unique_suffix = self.node.addr[-8:].lower()

        # Create S3 bucket for file uploads
        self.bucket = s3.Bucket(
            self,
            "FileProcessingBucket",
            bucket_name=f"file-processing-demo-{unique_suffix}",
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            versioned=False,
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            encryption=s3.BucketEncryption.S3_MANAGED,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteIncompleteMultipartUploads",
                    abort_incomplete_multipart_upload_after=Duration.days(1),
                )
            ],
        )

        # Create SNS topic for notifications
        self.sns_topic = sns.Topic(
            self,
            "FileProcessingNotifications",
            topic_name=f"file-processing-notifications-{unique_suffix}",
            display_name="File Processing Notifications",
            fifo=False,
        )

        # Create SQS queue for batch processing
        self.sqs_queue = sqs.Queue(
            self,
            "FileProcessingQueue",
            queue_name=f"file-processing-queue-{unique_suffix}",
            visibility_timeout=Duration.minutes(5),
            message_retention_period=Duration.days(14),
            receive_message_wait_time=Duration.seconds(20),  # Enable long polling
            dead_letter_queue=sqs.DeadLetterQueue(
                max_receive_count=3,
                queue=sqs.Queue(
                    self,
                    "FileProcessingDLQ",
                    queue_name=f"file-processing-dlq-{unique_suffix}",
                    message_retention_period=Duration.days(14),
                )
            ),
        )

        # Create Lambda execution role with appropriate permissions
        lambda_role = iam.Role(
            self,
            "FileProcessorLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
            inline_policies={
                "S3ReadPolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:GetObject",
                                "s3:GetObjectMetadata",
                                "s3:GetObjectVersion",
                            ],
                            resources=[f"{self.bucket.bucket_arn}/*"],
                        )
                    ]
                )
            },
        )

        # Create CloudWatch log group for Lambda function
        log_group = logs.LogGroup(
            self,
            "FileProcessorLogGroup",
            log_group_name=f"/aws/lambda/file-processor-{unique_suffix}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )

        # Create Lambda function for immediate file processing
        self.lambda_function = lambda_.Function(
            self,
            "FileProcessor",
            function_name=f"file-processor-{unique_suffix}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="file_processor.lambda_handler",
            code=lambda_.Code.from_inline(self._get_lambda_code()),
            timeout=Duration.seconds(30),
            memory_size=128,
            role=lambda_role,
            log_group=log_group,
            environment={
                "BUCKET_NAME": self.bucket.bucket_name,
                "SNS_TOPIC_ARN": self.sns_topic.topic_arn,
                "SQS_QUEUE_URL": self.sqs_queue.queue_url,
            },
            description="Processes files uploaded to S3 with intelligent routing based on file type",
        )

        # Configure S3 event notifications with intelligent routing
        
        # SNS notification for uploads/ prefix
        self.bucket.add_event_notification(
            s3.EventType.OBJECT_CREATED,
            s3_notifications.SnsDestination(self.sns_topic),
            s3.NotificationKeyFilter(prefix="uploads/"),
        )

        # SQS notification for batch/ prefix
        self.bucket.add_event_notification(
            s3.EventType.OBJECT_CREATED,
            s3_notifications.SqsDestination(self.sqs_queue),
            s3.NotificationKeyFilter(prefix="batch/"),
        )

        # Lambda notification for immediate/ prefix
        self.bucket.add_event_notification(
            s3.EventType.OBJECT_CREATED,
            s3_notifications.LambdaDestination(self.lambda_function),
            s3.NotificationKeyFilter(prefix="immediate/"),
        )

        # Add email subscription to SNS topic (placeholder - requires manual confirmation)
        # Uncomment and replace with actual email address for testing
        # self.sns_topic.add_subscription(
        #     sns_subscriptions.EmailSubscription("your-email@example.com")
        # )

        # Create CloudFormation outputs for easy access
        cdk.CfnOutput(
            self,
            "BucketName",
            value=self.bucket.bucket_name,
            description="Name of the S3 bucket for file uploads",
        )

        cdk.CfnOutput(
            self,
            "BucketArn",
            value=self.bucket.bucket_arn,
            description="ARN of the S3 bucket",
        )

        cdk.CfnOutput(
            self,
            "SNSTopicArn",
            value=self.sns_topic.topic_arn,
            description="ARN of the SNS topic for notifications",
        )

        cdk.CfnOutput(
            self,
            "SQSQueueUrl",
            value=self.sqs_queue.queue_url,
            description="URL of the SQS queue for batch processing",
        )

        cdk.CfnOutput(
            self,
            "SQSQueueArn",
            value=self.sqs_queue.queue_arn,
            description="ARN of the SQS queue",
        )

        cdk.CfnOutput(
            self,
            "LambdaFunctionName",
            value=self.lambda_function.function_name,
            description="Name of the Lambda function for immediate processing",
        )

        cdk.CfnOutput(
            self,
            "LambdaFunctionArn",
            value=self.lambda_function.function_arn,
            description="ARN of the Lambda function",
        )

        # Output test commands for validation
        cdk.CfnOutput(
            self,
            "TestCommands",
            value=f"aws s3 cp test.txt s3://{self.bucket.bucket_name}/uploads/ && "
                  f"aws s3 cp test.txt s3://{self.bucket.bucket_name}/batch/ && "
                  f"aws s3 cp test.txt s3://{self.bucket.bucket_name}/immediate/",
            description="Commands to test the event notification system",
        )

    def _get_lambda_code(self) -> str:
        """
        Returns the Lambda function code for file processing.
        
        Returns:
            str: The complete Lambda function code as a string
        """
        return """
import json
import boto3
import urllib.parse
from datetime import datetime
from typing import Dict, Any, List
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    \"\"\"
    Lambda function to process S3 events for uploaded files.
    
    This function demonstrates intelligent file processing based on file type
    and provides a foundation for building sophisticated content workflows.
    
    Args:
        event: S3 event notification containing file details
        context: Lambda execution context
        
    Returns:
        Dictionary with processing results
    \"\"\"
    
    logger.info(f"Received event: {json.dumps(event, indent=2)}")
    
    processed_files = []
    
    try:
        # Process each record in the event
        for record in event.get('Records', []):
            if 's3' not in record:
                logger.warning(f"Skipping non-S3 record: {record}")
                continue
                
            # Extract S3 event details
            bucket_name = record['s3']['bucket']['name']
            object_key = urllib.parse.unquote_plus(
                record['s3']['object']['key'], 
                encoding='utf-8'
            )
            object_size = record['s3']['object']['size']
            event_name = record['eventName']
            
            logger.info(f"Processing {event_name} for {object_key} in bucket {bucket_name}")
            logger.info(f"File size: {object_size} bytes")
            
            # Process file based on type and characteristics
            processing_result = process_file(bucket_name, object_key, object_size)
            
            processed_files.append({
                'bucket': bucket_name,
                'key': object_key,
                'size': object_size,
                'event': event_name,
                'processing_result': processing_result,
                'timestamp': datetime.now().isoformat()
            })
            
            logger.info(f"Successfully processed {object_key}")
            
    except Exception as e:
        logger.error(f"Error processing S3 event: {str(e)}")
        raise
    
    # Return success response
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'File processing completed successfully',
            'processed_files': processed_files,
            'total_files': len(processed_files)
        }),
        'headers': {
            'Content-Type': 'application/json'
        }
    }

def process_file(bucket_name: str, object_key: str, object_size: int) -> Dict[str, Any]:
    \"\"\"
    Process individual file based on type and characteristics.
    
    Args:
        bucket_name: Name of the S3 bucket
        object_key: S3 object key (file path)
        object_size: Size of the file in bytes
        
    Returns:
        Dictionary with processing results and recommendations
    \"\"\"
    
    file_extension = object_key.lower().split('.')[-1] if '.' in object_key else ''
    processing_type = determine_processing_type(file_extension, object_size)
    
    logger.info(f"File type detected: {processing_type}")
    
    # Simulate different processing workflows
    if processing_type == 'image':
        return process_image_file(bucket_name, object_key, object_size)
    elif processing_type == 'video':
        return process_video_file(bucket_name, object_key, object_size)
    elif processing_type == 'document':
        return process_document_file(bucket_name, object_key, object_size)
    elif processing_type == 'archive':
        return process_archive_file(bucket_name, object_key, object_size)
    else:
        return process_unknown_file(bucket_name, object_key, object_size)

def determine_processing_type(file_extension: str, file_size: int) -> str:
    \"\"\"
    Determine the processing type based on file extension and size.
    
    Args:
        file_extension: File extension (without dot)
        file_size: File size in bytes
        
    Returns:
        Processing type string
    \"\"\"
    
    image_extensions = {'jpg', 'jpeg', 'png', 'gif', 'bmp', 'tiff', 'webp'}
    video_extensions = {'mp4', 'mov', 'avi', 'mkv', 'wmv', 'flv', 'webm'}
    document_extensions = {'pdf', 'doc', 'docx', 'txt', 'rtf', 'odt'}
    archive_extensions = {'zip', 'tar', 'gz', 'rar', '7z', 'bz2'}
    
    if file_extension in image_extensions:
        return 'image'
    elif file_extension in video_extensions:
        return 'video'
    elif file_extension in document_extensions:
        return 'document'
    elif file_extension in archive_extensions:
        return 'archive'
    else:
        return 'unknown'

def process_image_file(bucket_name: str, object_key: str, object_size: int) -> Dict[str, Any]:
    \"\"\"Process image files with thumbnail generation and metadata extraction.\"\"\"
    
    logger.info(f"Processing image file: {object_key}")
    
    # Simulate image processing workflow
    processing_steps = [
        "Validated image format and integrity",
        "Generated thumbnail versions (150x150, 300x300)",
        "Extracted EXIF metadata",
        "Performed content moderation scan",
        "Updated image catalog database"
    ]
    
    recommendations = [
        "Consider enabling S3 Transfer Acceleration for faster uploads",
        "Implement CloudFront distribution for optimized image delivery",
        "Set up automated backup to Glacier for long-term storage"
    ]
    
    return {
        'processing_type': 'image',
        'steps_completed': processing_steps,
        'recommendations': recommendations,
        'estimated_cost': calculate_processing_cost('image', object_size),
        'next_actions': ['thumbnail_generation', 'metadata_indexing']
    }

def process_video_file(bucket_name: str, object_key: str, object_size: int) -> Dict[str, Any]:
    \"\"\"Process video files with transcoding and preview generation.\"\"\"
    
    logger.info(f"Processing video file: {object_key}")
    
    processing_steps = [
        "Validated video format and codec compatibility",
        "Initiated multi-resolution transcoding workflow",
        "Generated video thumbnail and preview clips",
        "Extracted video metadata and duration",
        "Queued for content analysis and indexing"
    ]
    
    recommendations = [
        "Use AWS MediaConvert for professional video processing",
        "Implement adaptive bitrate streaming for optimal delivery",
        "Consider AWS Elemental MediaPackage for live streaming"
    ]
    
    return {
        'processing_type': 'video',
        'steps_completed': processing_steps,
        'recommendations': recommendations,
        'estimated_cost': calculate_processing_cost('video', object_size),
        'next_actions': ['transcoding', 'content_analysis', 'cdn_distribution']
    }

def process_document_file(bucket_name: str, object_key: str, object_size: int) -> Dict[str, Any]:
    \"\"\"Process document files with text extraction and indexing.\"\"\"
    
    logger.info(f"Processing document file: {object_key}")
    
    processing_steps = [
        "Validated document format and accessibility",
        "Performed virus and malware scanning",
        "Extracted text content for search indexing",
        "Generated document preview and thumbnails",
        "Analyzed content for compliance and classification"
    ]
    
    recommendations = [
        "Implement Amazon Textract for advanced text extraction",
        "Use Amazon Kendra for intelligent document search",
        "Consider Amazon Macie for sensitive data detection"
    ]
    
    return {
        'processing_type': 'document',
        'steps_completed': processing_steps,
        'recommendations': recommendations,
        'estimated_cost': calculate_processing_cost('document', object_size),
        'next_actions': ['text_indexing', 'compliance_check', 'search_optimization']
    }

def process_archive_file(bucket_name: str, object_key: str, object_size: int) -> Dict[str, Any]:
    \"\"\"Process archive files with extraction and content analysis.\"\"\"
    
    logger.info(f"Processing archive file: {object_key}")
    
    processing_steps = [
        "Validated archive integrity and format",
        "Scanned for malicious content",
        "Extracted file listing and metadata",
        "Analyzed compression ratio and efficiency",
        "Prepared for selective extraction workflow"
    ]
    
    recommendations = [
        "Implement automated extraction for supported formats",
        "Use AWS Lambda with larger memory for processing large archives",
        "Consider Amazon S3 Glacier for long-term archive storage"
    ]
    
    return {
        'processing_type': 'archive',
        'steps_completed': processing_steps,
        'recommendations': recommendations,
        'estimated_cost': calculate_processing_cost('archive', object_size),
        'next_actions': ['content_extraction', 'virus_scanning', 'cataloging']
    }

def process_unknown_file(bucket_name: str, object_key: str, object_size: int) -> Dict[str, Any]:
    \"\"\"Process unknown file types with basic analysis.\"\"\"
    
    logger.info(f"Processing unknown file type: {object_key}")
    
    processing_steps = [
        "Performed basic file analysis and type detection",
        "Executed security scanning and validation",
        "Generated file hash and metadata",
        "Logged for manual review and classification",
        "Applied default retention and access policies"
    ]
    
    recommendations = [
        "Review file type and update processing rules",
        "Consider implementing custom processing workflow",
        "Enhance file type detection algorithms"
    ]
    
    return {
        'processing_type': 'unknown',
        'steps_completed': processing_steps,
        'recommendations': recommendations,
        'estimated_cost': calculate_processing_cost('unknown', object_size),
        'next_actions': ['manual_review', 'type_classification', 'workflow_update']
    }

def calculate_processing_cost(processing_type: str, file_size: int) -> float:
    \"\"\"
    Calculate estimated processing cost based on file type and size.
    
    Args:
        processing_type: Type of processing required
        file_size: File size in bytes
        
    Returns:
        Estimated cost in USD
    \"\"\"
    
    # Cost per MB for different processing types
    cost_per_mb = {
        'image': 0.001,
        'video': 0.05,
        'document': 0.002,
        'archive': 0.003,
        'unknown': 0.001
    }
    
    file_size_mb = file_size / (1024 * 1024)
    base_cost = cost_per_mb.get(processing_type, 0.001)
    
    return round(file_size_mb * base_cost, 4)
"""


def main() -> None:
    """Main entry point for the CDK application."""
    
    app = cdk.App()
    
    # Create the main stack
    S3EventProcessingStack(
        app, 
        "S3EventProcessingStack",
        description="S3 Event Notifications and Automated Processing Stack",
        env=cdk.Environment(
            account=app.node.try_get_context("account"),
            region=app.node.try_get_context("region"),
        ),
    )
    
    app.synth()


if __name__ == "__main__":
    main()