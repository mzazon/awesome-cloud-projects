#!/usr/bin/env python3
"""
CDK Python Application for Intelligent Document Processing with Amazon Textract

This application creates a serverless document processing pipeline using:
- Amazon S3 for document storage
- AWS Lambda for processing orchestration
- Amazon Textract for intelligent text extraction
- CloudWatch for monitoring and logging

The pipeline automatically processes documents uploaded to S3 and extracts
text, handwriting, and structured data using machine learning.

Recipe: intelligent-document-processing-amazon-textract
Version: 1.1
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    aws_s3 as s3,
    aws_lambda as lambda_,
    aws_iam as iam,
    aws_s3_notifications as s3_notifications,
    aws_logs as logs,
    CfnOutput,
    Tags,
)
from constructs import Construct


class IntelligentDocumentProcessingStack(Stack):
    """
    CDK Stack for Intelligent Document Processing with Amazon Textract
    
    This stack deploys a complete serverless document processing pipeline
    that automatically extracts text and structured data from documents
    using Amazon Textract's machine learning capabilities.
    
    Components:
    - S3 bucket for document storage with security and lifecycle policies
    - Lambda function for orchestrating Textract processing
    - IAM roles with least privilege permissions
    - CloudWatch Logs for monitoring and debugging
    - S3 event notifications for automated processing
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names to avoid conflicts
        unique_suffix = self.node.try_get_context("unique_suffix") or cdk.Names.unique_id(self)[:8].lower()
        
        # Create S3 bucket for document storage and processing
        self.document_bucket = self._create_document_bucket(unique_suffix)
        
        # Create IAM role for Lambda function with required permissions
        self.lambda_role = self._create_lambda_execution_role()
        
        # Create Lambda function for document processing
        self.processing_function = self._create_processing_function(unique_suffix)
        
        # Configure S3 event notifications to trigger Lambda
        self._configure_s3_notifications()
        
        # Create CloudWatch log group for better log management
        self.log_group = self._create_log_group(unique_suffix)
        
        # Apply tags to all resources in this stack
        self._apply_tags()
        
        # Create CloudFormation outputs for important resource information
        self._create_outputs()

    def _create_document_bucket(self, suffix: str) -> s3.Bucket:
        """
        Create S3 bucket for document storage with proper configuration
        
        Args:
            suffix: Unique suffix for bucket naming
            
        Returns:
            s3.Bucket: Configured S3 bucket for document storage
        """
        bucket = s3.Bucket(
            self,
            "DocumentBucket",
            bucket_name=f"textract-documents-{suffix}",
            # Enable versioning for document history and audit trails
            versioned=True,
            # Configure lifecycle rules for cost optimization
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="ArchiveOldVersions",
                    enabled=True,
                    noncurrent_version_transitions=[
                        s3.NoncurrentVersionTransition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30)
                        ),
                        s3.NoncurrentVersionTransition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(90)
                        )
                    ]
                ),
                s3.LifecycleRule(
                    id="OptimizeCurrentVersions",
                    enabled=True,
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30),
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(90),
                        ),
                    ],
                ),
            ],
            # Enable server-side encryption for data protection
            encryption=s3.BucketEncryption.S3_MANAGED,
            # Block public access for security
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            # Configure removal policy for cleanup
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True
        )
        
        return bucket

    def _create_lambda_execution_role(self) -> iam.Role:
        """
        Create IAM role for Lambda function with least privilege permissions
        
        Returns:
            iam.Role: Configured IAM role for Lambda execution
        """
        role = iam.Role(
            self,
            "ProcessorLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="IAM role for Textract document processing Lambda function",
            managed_policies=[
                # Basic Lambda execution permissions for CloudWatch logs
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ]
        )
        
        # Add S3 permissions for reading documents and storing results
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:PutObject",
                    "s3:GetObjectVersion"
                ],
                resources=[f"{self.document_bucket.bucket_arn}/*"]
            )
        )
        
        # Add Textract permissions for document analysis
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "textract:DetectDocumentText",
                    "textract:AnalyzeDocument",
                    "textract:GetDocumentAnalysis",
                    "textract:GetDocumentTextDetection"
                ],
                resources=["*"]  # Textract doesn't support resource-level permissions
            )
        )
        
        return role

    def _create_processing_function(self, suffix: str) -> lambda_.Function:
        """
        Create Lambda function for document processing with Textract
        
        Args:
            suffix: Unique suffix for function naming
            
        Returns:
            lambda_.Function: Configured Lambda function
        """
        function = lambda_.Function(
            self,
            "ProcessorFunction",
            function_name=f"textract-processor-{suffix}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            role=self.lambda_role,
            # Set appropriate timeout for document processing
            timeout=Duration.minutes(5),
            # Configure memory for optimal performance
            memory_size=512,
            # Set environment variables for configuration
            environment={
                "BUCKET_NAME": self.document_bucket.bucket_name,
                "LOG_LEVEL": "INFO"
            },
            description="Processes documents using Amazon Textract for intelligent text extraction",
            # Inline code for the Lambda function
            code=lambda_.Code.from_inline(self._get_lambda_code())
        )
        
        return function

    def _configure_s3_notifications(self) -> None:
        """
        Configure S3 bucket notifications to trigger Lambda function
        """
        # Add S3 event notification for object creation in documents/ prefix
        self.document_bucket.add_event_notification(
            s3.EventType.OBJECT_CREATED,
            s3_notifications.LambdaDestination(self.processing_function),
            s3.NotificationKeyFilter(prefix="documents/")
        )

    def _create_log_group(self, suffix: str) -> logs.LogGroup:
        """
        Create CloudWatch log group for Lambda function with retention policy
        """
        log_group = logs.LogGroup(
            self,
            "ProcessorLogGroup",
            log_group_name=f"/aws/lambda/textract-processor-{suffix}",
            retention=logs.RetentionDays.TWO_WEEKS,
            removal_policy=RemovalPolicy.DESTROY
        )
        
        return log_group

    def _apply_tags(self) -> None:
        """
        Apply tags to all resources in this stack for resource management
        """
        Tags.of(self).add("Project", "IntelligentDocumentProcessing")
        Tags.of(self).add("Component", "DocumentProcessing")
        Tags.of(self).add("Service", "Textract")
        Tags.of(self).add("Environment", "Demo")

    def _create_outputs(self) -> None:
        """
        Create CloudFormation outputs for important resource information
        """
        CfnOutput(
            self,
            "DocumentBucketName",
            description="Name of the S3 bucket for document storage",
            value=self.document_bucket.bucket_name
        )
        
        CfnOutput(
            self,
            "DocumentBucketArn",
            description="ARN of the S3 bucket for document storage",
            value=self.document_bucket.bucket_arn
        )
        
        CfnOutput(
            self,
            "ProcessorFunctionName",
            description="Name of the Lambda function for document processing",
            value=self.processing_function.function_name
        )
        
        CfnOutput(
            self,
            "ProcessorFunctionArn",
            description="ARN of the Lambda function for document processing",
            value=self.processing_function.function_arn
        )
        
        CfnOutput(
            self,
            "UploadURL",
            description="S3 URL for uploading documents",
            value=f"s3://{self.document_bucket.bucket_name}/documents/"
        )

    def _get_lambda_code(self) -> str:
        """
        Return the Lambda function code for document processing.
        
        This function:
        1. Responds to S3 events for document uploads
        2. Calls Amazon Textract for text extraction
        3. Processes and formats the extracted text
        4. Saves results back to S3 in JSON format
        5. Provides comprehensive error handling and logging
        """
        return '''
import json
import boto3
import urllib.parse
import os
import logging
from datetime import datetime
from typing import Dict, List, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

# Initialize AWS clients
s3_client = boto3.client('s3')
textract_client = boto3.client('textract')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Process documents uploaded to S3 using Amazon Textract.
    
    Args:
        event: S3 event notification
        context: Lambda context object
        
    Returns:
        Response dictionary with processing status
    """
    try:
        # Extract S3 event details
        record = event['Records'][0]
        bucket_name = record['s3']['bucket']['name']
        object_key = urllib.parse.unquote_plus(
            record['s3']['object']['key'], 
            encoding='utf-8'
        )
        
        logger.info(f"Processing document: {object_key} from bucket: {bucket_name}")
        
        # Call Amazon Textract to extract text
        textract_response = textract_client.detect_document_text(
            Document={
                'S3Object': {
                    'Bucket': bucket_name,
                    'Name': object_key
                }
            }
        )
        
        # Process and format extracted text
        processing_results = process_textract_response(textract_response, object_key)
        
        # Save results to S3
        results_key = f"results/{object_key.split('/')[-1]}_results.json"
        save_results_to_s3(bucket_name, results_key, processing_results)
        
        logger.info(f"Document processed successfully. Results saved to: {results_key}")
        logger.info(f"Average confidence: {processing_results.get('average_confidence', 0):.2f}%")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Document processed successfully',
                'document': object_key,
                'results_location': f"s3://{bucket_name}/{results_key}",
                'confidence': processing_results.get('average_confidence', 0)
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing document: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'Document processing failed'
            })
        }

def process_textract_response(response: Dict[str, Any], document_key: str) -> Dict[str, Any]:
    """
    Process Textract response and extract structured information.
    
    Args:
        response: Textract API response
        document_key: S3 object key of processed document
        
    Returns:
        Structured processing results
    """
    extracted_text = ""
    confidence_scores = []
    blocks_by_type = {'LINE': 0, 'WORD': 0, 'PAGE': 0}
    
    for block in response['Blocks']:
        block_type = block['BlockType']
        blocks_by_type[block_type] = blocks_by_type.get(block_type, 0) + 1
        
        if block_type == 'LINE':
            extracted_text += block['Text'] + '\\n'
            confidence_scores.append(block['Confidence'])
    
    # Calculate statistics
    avg_confidence = sum(confidence_scores) / len(confidence_scores) if confidence_scores else 0
    
    results = {
        'document': document_key,
        'processing_timestamp': datetime.utcnow().isoformat(),
        'extracted_text': extracted_text.strip(),
        'statistics': {
            'average_confidence': round(avg_confidence, 2),
            'total_blocks': len(response['Blocks']),
            'blocks_by_type': blocks_by_type,
            'total_lines': len(confidence_scores),
            'confidence_range': {
                'min': round(min(confidence_scores), 2) if confidence_scores else 0,
                'max': round(max(confidence_scores), 2) if confidence_scores else 0
            }
        },
        'processing_status': 'completed'
    }
    
    return results

def save_results_to_s3(bucket_name: str, results_key: str, results: Dict[str, Any]) -> None:
    """
    Save processing results to S3.
    
    Args:
        bucket_name: S3 bucket name
        results_key: S3 object key for results
        results: Processing results dictionary
    """
    s3_client.put_object(
        Bucket=bucket_name,
        Key=results_key,
        Body=json.dumps(results, indent=2),
        ContentType='application/json',
        Metadata={
            'processing-engine': 'amazon-textract',
            'result-version': '1.0'
        }
    )
'''


# CDK Application
app = cdk.App()

# Create the stack with environment configuration
env = cdk.Environment(
    account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
    region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
)

IntelligentDocumentProcessingStack(
    app,
    "IntelligentDocumentProcessingStack",
    description="Serverless document processing pipeline using Amazon Textract",
    env=env
)

# Add application-level tags
Tags.of(app).add("Project", "IntelligentDocumentProcessing")
Tags.of(app).add("Owner", "CDK")
Tags.of(app).add("Environment", "Demo")

app.synth()