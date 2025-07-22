#!/usr/bin/env python3
"""
AWS CDK Python Application for Intelligent Document Summarization

This CDK application deploys a serverless document summarization system that:
- Processes documents uploaded to S3
- Extracts text using Amazon Textract
- Generates summaries using Amazon Bedrock (Claude)
- Stores results in S3 with metadata in DynamoDB
- Sends notifications via SNS

Architecture:
- S3 buckets for input documents and output summaries
- Lambda function for processing pipeline
- DynamoDB table for document metadata
- SNS topic for notifications
- CloudWatch dashboard for monitoring
"""

import os
import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_s3 as s3,
    aws_lambda as _lambda,
    aws_iam as iam,
    aws_dynamodb as dynamodb,
    aws_sns as sns,
    aws_cloudwatch as cloudwatch,
    aws_s3_notifications as s3n,
    aws_logs as logs,
)
from constructs import Construct
import json


class DocumentSummarizationStack(Stack):
    """
    CDK Stack for Intelligent Document Summarization System
    
    Creates a complete serverless pipeline for automated document processing
    and AI-powered summarization using AWS managed services.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Stack parameters with sensible defaults
        self.bedrock_model_id = "anthropic.claude-3-sonnet-20240229-v1:0"
        self.lambda_timeout_minutes = 5
        self.lambda_memory_mb = 512

        # Create S3 buckets for document storage
        self._create_storage_resources()
        
        # Create DynamoDB table for metadata
        self._create_database_resources()
        
        # Create SNS topic for notifications
        self._create_notification_resources()
        
        # Create Lambda function and permissions
        self._create_processing_resources()
        
        # Create CloudWatch dashboard
        self._create_monitoring_resources()
        
        # Configure S3 event triggers
        self._configure_event_triggers()
        
        # Create stack outputs
        self._create_outputs()

    def _create_storage_resources(self) -> None:
        """Create S3 buckets for document input and summary output."""
        
        # Input bucket for document uploads
        self.input_bucket = s3.Bucket(
            self, "DocumentInputBucket",
            bucket_name=None,  # Auto-generated name
            versioning=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,  # For demo purposes
            auto_delete_objects=True,  # For demo purposes
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="ArchiveOldDocuments",
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

        # Output bucket for generated summaries
        self.output_bucket = s3.Bucket(
            self, "SummaryOutputBucket",
            bucket_name=None,  # Auto-generated name
            versioning=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,  # For demo purposes
            auto_delete_objects=True,  # For demo purposes
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="RetainSummaries",
                    enabled=True,
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(60)
                        )
                    ]
                )
            ]
        )

    def _create_database_resources(self) -> None:
        """Create DynamoDB table for document metadata and processing status."""
        
        self.metadata_table = dynamodb.Table(
            self, "DocumentMetadataTable",
            table_name=None,  # Auto-generated name
            partition_key=dynamodb.Attribute(
                name="document_id",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="processing_timestamp",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            encryption=dynamodb.TableEncryption.AWS_MANAGED,
            removal_policy=RemovalPolicy.DESTROY,  # For demo purposes
            point_in_time_recovery=True,
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
            time_to_live_attribute="ttl"
        )

        # Add GSI for querying by processing status
        self.metadata_table.add_global_secondary_index(
            index_name="ProcessingStatusIndex",
            partition_key=dynamodb.Attribute(
                name="processing_status",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="processing_timestamp",
                type=dynamodb.AttributeType.STRING
            ),
            projection_type=dynamodb.ProjectionType.ALL
        )

    def _create_notification_resources(self) -> None:
        """Create SNS topic for processing notifications."""
        
        self.notification_topic = sns.Topic(
            self, "DocumentProcessingNotifications",
            topic_name=None,  # Auto-generated name
            display_name="Document Summarization Notifications",
            master_key=None  # Use AWS managed encryption
        )

    def _create_processing_resources(self) -> None:
        """Create Lambda function and associated IAM roles for document processing."""
        
        # Create Lambda execution role with necessary permissions
        self.lambda_role = iam.Role(
            self, "DocumentProcessorRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
            inline_policies={
                "DocumentProcessingPolicy": iam.PolicyDocument(
                    statements=[
                        # S3 permissions for reading input and writing output
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:GetObject",
                                "s3:GetObjectVersion"
                            ],
                            resources=[f"{self.input_bucket.bucket_arn}/*"]
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:PutObject",
                                "s3:PutObjectAcl"
                            ],
                            resources=[f"{self.output_bucket.bucket_arn}/*"]
                        ),
                        # Textract permissions for text extraction
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "textract:DetectDocumentText",
                                "textract:AnalyzeDocument"
                            ],
                            resources=["*"]
                        ),
                        # Bedrock permissions for AI summarization
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=["bedrock:InvokeModel"],
                            resources=[
                                f"arn:aws:bedrock:{self.region}::foundation-model/{self.bedrock_model_id}"
                            ]
                        ),
                        # DynamoDB permissions for metadata storage
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "dynamodb:PutItem",
                                "dynamodb:UpdateItem",
                                "dynamodb:GetItem",
                                "dynamodb:Query"
                            ],
                            resources=[
                                self.metadata_table.table_arn,
                                f"{self.metadata_table.table_arn}/index/*"
                            ]
                        ),
                        # SNS permissions for notifications
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=["sns:Publish"],
                            resources=[self.notification_topic.topic_arn]
                        )
                    ]
                )
            }
        )

        # Create Lambda function
        self.processor_function = _lambda.Function(
            self, "DocumentProcessorFunction",
            function_name=None,  # Auto-generated name
            runtime=_lambda.Runtime.PYTHON_3_11,
            handler="lambda_function.lambda_handler",
            code=_lambda.Code.from_inline(self._get_lambda_code()),
            role=self.lambda_role,
            timeout=Duration.minutes(self.lambda_timeout_minutes),
            memory_size=self.lambda_memory_mb,
            environment={
                "OUTPUT_BUCKET": self.output_bucket.bucket_name,
                "METADATA_TABLE": self.metadata_table.table_name,
                "NOTIFICATION_TOPIC": self.notification_topic.topic_arn,
                "BEDROCK_MODEL_ID": self.bedrock_model_id,
                "AWS_REGION": self.region
            },
            reserved_concurrent_executions=10,  # Limit concurrency for cost control
            retry_attempts=2,
            dead_letter_queue_enabled=True,
            log_retention=logs.RetentionDays.ONE_WEEK
        )

    def _create_monitoring_resources(self) -> None:
        """Create CloudWatch dashboard for system monitoring."""
        
        self.dashboard = cloudwatch.Dashboard(
            self, "DocumentSummarizationDashboard",
            dashboard_name=f"document-summarization-{self.stack_name}",
            widgets=[
                [
                    # Lambda function metrics
                    cloudwatch.GraphWidget(
                        title="Lambda Function Metrics",
                        left=[
                            self.processor_function.metric_invocations(),
                            self.processor_function.metric_errors(),
                            self.processor_function.metric_duration()
                        ],
                        width=12,
                        height=6
                    )
                ],
                [
                    # S3 bucket metrics
                    cloudwatch.GraphWidget(
                        title="S3 Storage Metrics",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/S3",
                                metric_name="NumberOfObjects",
                                dimensions_map={
                                    "BucketName": self.input_bucket.bucket_name,
                                    "StorageType": "AllStorageTypes"
                                }
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/S3",
                                metric_name="BucketSizeBytes",
                                dimensions_map={
                                    "BucketName": self.output_bucket.bucket_name,
                                    "StorageType": "StandardStorage"
                                }
                            )
                        ],
                        width=12,
                        height=6
                    )
                ],
                [
                    # DynamoDB table metrics
                    cloudwatch.GraphWidget(
                        title="DynamoDB Metrics",
                        left=[
                            self.metadata_table.metric_consumed_read_capacity_units(),
                            self.metadata_table.metric_consumed_write_capacity_units()
                        ],
                        width=12,
                        height=6
                    )
                ]
            ]
        )

    def _configure_event_triggers(self) -> None:
        """Configure S3 event notifications to trigger Lambda processing."""
        
        # Add S3 event notification for document uploads
        self.input_bucket.add_event_notification(
            s3.EventType.OBJECT_CREATED,
            s3n.LambdaDestination(self.processor_function),
            s3.NotificationKeyFilter(prefix="documents/")
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource identifiers."""
        
        CfnOutput(
            self, "InputBucketName",
            value=self.input_bucket.bucket_name,
            description="S3 bucket for document uploads",
            export_name=f"{self.stack_name}-InputBucket"
        )

        CfnOutput(
            self, "OutputBucketName",
            value=self.output_bucket.bucket_name,
            description="S3 bucket for generated summaries",
            export_name=f"{self.stack_name}-OutputBucket"
        )

        CfnOutput(
            self, "ProcessorFunctionName",
            value=self.processor_function.function_name,
            description="Lambda function for document processing",
            export_name=f"{self.stack_name}-ProcessorFunction"
        )

        CfnOutput(
            self, "MetadataTableName",
            value=self.metadata_table.table_name,
            description="DynamoDB table for document metadata",
            export_name=f"{self.stack_name}-MetadataTable"
        )

        CfnOutput(
            self, "NotificationTopicArn",
            value=self.notification_topic.topic_arn,
            description="SNS topic for processing notifications",
            export_name=f"{self.stack_name}-NotificationTopic"
        )

        CfnOutput(
            self, "DashboardURL",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.dashboard.dashboard_name}",
            description="CloudWatch dashboard URL for monitoring"
        )

    def _get_lambda_code(self) -> str:
        """Return the Lambda function code as a string."""
        
        return '''
import json
import boto3
import os
from urllib.parse import unquote_plus
import logging
from datetime import datetime, timezone
import uuid
from typing import Dict, Any, Optional

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
s3 = boto3.client('s3')
textract = boto3.client('textract')
bedrock = boto3.client('bedrock-runtime')
dynamodb = boto3.resource('dynamodb')
sns = boto3.client('sns')

# Environment variables
OUTPUT_BUCKET = os.environ['OUTPUT_BUCKET']
METADATA_TABLE = os.environ['METADATA_TABLE']
NOTIFICATION_TOPIC = os.environ['NOTIFICATION_TOPIC']
BEDROCK_MODEL_ID = os.environ['BEDROCK_MODEL_ID']

# DynamoDB table
table = dynamodb.Table(METADATA_TABLE)


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for document processing pipeline.
    
    Processes S3 events for uploaded documents, extracts text using Textract,
    generates summaries using Bedrock, and stores results.
    
    Args:
        event: S3 event notification
        context: Lambda context object
    
    Returns:
        Dictionary with processing results
    """
    try:
        # Parse S3 event
        bucket = event['Records'][0]['s3']['bucket']['name']
        key = unquote_plus(event['Records'][0]['s3']['object']['key'])
        
        logger.info(f"Processing document: {key} from bucket: {bucket}")
        
        # Generate unique document ID
        document_id = str(uuid.uuid4())
        processing_timestamp = datetime.now(timezone.utc).isoformat()
        
        # Store initial metadata
        store_metadata(document_id, key, "PROCESSING", processing_timestamp)
        
        # Extract text from document
        text_content = extract_text(bucket, key)
        logger.info(f"Extracted {len(text_content)} characters of text")
        
        # Generate summary using Bedrock
        summary = generate_summary(text_content)
        logger.info(f"Generated summary of {len(summary)} characters")
        
        # Store summary and update metadata
        summary_key = store_summary(key, summary, text_content)
        store_metadata(document_id, key, "COMPLETED", processing_timestamp, {
            "summary_key": summary_key,
            "text_length": len(text_content),
            "summary_length": len(summary),
            "processing_duration": (datetime.now(timezone.utc) - datetime.fromisoformat(processing_timestamp.replace('Z', '+00:00'))).total_seconds()
        })
        
        # Send notification
        send_notification(document_id, key, summary_key, "SUCCESS")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Document processed successfully',
                'document_id': document_id,
                'document': key,
                'summary_key': summary_key,
                'summary_length': len(summary)
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing document: {str(e)}")
        
        # Update metadata with error status
        try:
            store_metadata(document_id, key, "FAILED", processing_timestamp, {
                "error_message": str(e)
            })
            send_notification(document_id, key, None, "FAILED", str(e))
        except:
            pass  # Don't fail on metadata/notification errors
        
        raise


def extract_text(bucket: str, key: str) -> str:
    """
    Extract text from document using Amazon Textract.
    
    Args:
        bucket: S3 bucket name
        key: S3 object key
    
    Returns:
        Extracted text content
    """
    try:
        response = textract.detect_document_text(
            Document={'S3Object': {'Bucket': bucket, 'Name': key}}
        )
        
        text_blocks = []
        for block in response['Blocks']:
            if block['BlockType'] == 'LINE':
                text_blocks.append(block['Text'])
        
        return '\\n'.join(text_blocks)
        
    except Exception as e:
        logger.error(f"Text extraction failed: {str(e)}")
        raise


def generate_summary(text_content: str) -> str:
    """
    Generate summary using Amazon Bedrock Claude model.
    
    Args:
        text_content: Text to summarize
    
    Returns:
        Generated summary
    """
    try:
        # Truncate text if too long (Bedrock has token limits)
        max_length = 10000
        if len(text_content) > max_length:
            text_content = text_content[:max_length] + "..."
            logger.warning(f"Text truncated to {max_length} characters")
        
        prompt = f"""Please provide a comprehensive summary of the following document. Include:

1. Main topics and key points
2. Important facts, figures, and conclusions
3. Actionable insights or recommendations
4. Any critical deadlines or dates mentioned

Document content:
{text_content}

Summary:"""
        
        response = bedrock.invoke_model(
            modelId=BEDROCK_MODEL_ID,
            body=json.dumps({
                'anthropic_version': 'bedrock-2023-05-31',
                'max_tokens': 1000,
                'messages': [{'role': 'user', 'content': prompt}]
            })
        )
        
        response_body = json.loads(response['body'].read())
        return response_body['content'][0]['text']
        
    except Exception as e:
        logger.error(f"Summary generation failed: {str(e)}")
        raise


def store_summary(original_key: str, summary: str, full_text: str) -> str:
    """
    Store summary and metadata in S3.
    
    Args:
        original_key: Original document key
        summary: Generated summary
        full_text: Full extracted text
    
    Returns:
        S3 key of stored summary
    """
    try:
        summary_key = f"summaries/{original_key}.summary.txt"
        
        # Store summary with metadata
        s3.put_object(
            Bucket=OUTPUT_BUCKET,
            Key=summary_key,
            Body=summary,
            ContentType='text/plain',
            Metadata={
                'original-document': original_key,
                'summary-generated': 'true',
                'text-length': str(len(full_text)),
                'summary-length': str(len(summary)),
                'processing-timestamp': datetime.now(timezone.utc).isoformat()
            }
        )
        
        logger.info(f"Summary stored: {summary_key}")
        return summary_key
        
    except Exception as e:
        logger.error(f"Failed to store summary: {str(e)}")
        raise


def store_metadata(document_id: str, document_key: str, status: str, 
                  timestamp: str, additional_data: Optional[Dict] = None) -> None:
    """
    Store document processing metadata in DynamoDB.
    
    Args:
        document_id: Unique document identifier
        document_key: S3 key of original document
        status: Processing status
        timestamp: Processing timestamp
        additional_data: Additional metadata
    """
    try:
        item = {
            'document_id': document_id,
            'processing_timestamp': timestamp,
            'document_key': document_key,
            'processing_status': status,
            'ttl': int((datetime.now(timezone.utc).timestamp()) + (30 * 24 * 60 * 60))  # 30 days TTL
        }
        
        if additional_data:
            item.update(additional_data)
        
        table.put_item(Item=item)
        logger.info(f"Metadata stored for document {document_id}")
        
    except Exception as e:
        logger.error(f"Failed to store metadata: {str(e)}")
        # Don't raise - metadata storage failure shouldn't stop processing


def send_notification(document_id: str, document_key: str, summary_key: Optional[str], 
                     status: str, error_message: Optional[str] = None) -> None:
    """
    Send SNS notification about processing completion.
    
    Args:
        document_id: Unique document identifier
        document_key: S3 key of original document
        summary_key: S3 key of generated summary
        status: Processing status
        error_message: Error message if failed
    """
    try:
        message = {
            'document_id': document_id,
            'document_key': document_key,
            'status': status,
            'timestamp': datetime.now(timezone.utc).isoformat()
        }
        
        if summary_key:
            message['summary_key'] = summary_key
        
        if error_message:
            message['error_message'] = error_message
        
        sns.publish(
            TopicArn=NOTIFICATION_TOPIC,
            Subject=f"Document Processing {status}: {document_key}",
            Message=json.dumps(message, indent=2)
        )
        
        logger.info(f"Notification sent for document {document_id}")
        
    except Exception as e:
        logger.error(f"Failed to send notification: {str(e)}")
        # Don't raise - notification failure shouldn't stop processing
'''


# Create the CDK application
app = cdk.App()

# Get stack name from context or use default
stack_name = app.node.try_get_context("stackName") or "DocumentSummarizationStack"

# Create the stack
DocumentSummarizationStack(
    app, 
    stack_name,
    description="Intelligent Document Summarization with Amazon Bedrock and Lambda",
    env=cdk.Environment(
        account=os.environ.get('CDK_DEFAULT_ACCOUNT'),
        region=os.environ.get('CDK_DEFAULT_REGION', 'us-east-1')
    ),
    tags={
        "Application": "DocumentSummarization",
        "Environment": app.node.try_get_context("environment") or "development",
        "Owner": "CDK",
        "CostCenter": "AI-ML"
    }
)

# Synthesize the CloudFormation template
app.synth()