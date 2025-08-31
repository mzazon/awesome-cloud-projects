#!/usr/bin/env python3
"""
CDK Application for Simple File Validation with S3 and Lambda

This application deploys a serverless file validation system that automatically
validates files uploaded to S3 using Lambda functions. The system moves valid
files to an approved bucket and quarantines invalid files.

Architecture:
- S3 Upload Bucket: Initial file upload destination
- S3 Valid Files Bucket: Storage for validated files  
- S3 Quarantine Bucket: Storage for invalid files
- Lambda Function: Validates file type and size
- IAM Role: Secure permissions for Lambda execution
- CloudWatch Logs: Function execution logging
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Duration,
    Stack,
    CfnOutput,
    RemovalPolicy,
    aws_s3 as s3,
    aws_lambda as _lambda,
    aws_iam as iam,
    aws_s3_notifications as s3n,
    aws_logs as logs,
)
from constructs import Construct


class FileValidationStack(Stack):
    """
    CDK Stack for File Validation System
    
    Creates a complete serverless file validation system using S3 event
    notifications and Lambda functions with proper IAM permissions and
    CloudWatch logging.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        unique_suffix = self.node.try_get_context("unique_suffix") or "demo"
        
        # Create S3 buckets for file management
        self._create_s3_buckets(unique_suffix)
        
        # Create IAM role for Lambda function
        self._create_lambda_role()
        
        # Create Lambda function for file validation
        self._create_lambda_function(unique_suffix)
        
        # Configure S3 event notifications
        self._configure_s3_events()
        
        # Create stack outputs
        self._create_outputs()

    def _create_s3_buckets(self, unique_suffix: str) -> None:
        """
        Create S3 buckets for file upload, valid files, and quarantine.
        
        Implements S3 best practices including:
        - Versioning for data protection
        - Block public access for security
        - Lifecycle policies for cost optimization
        - Server-side encryption
        """
        # Upload bucket - initial file destination
        self.upload_bucket = s3.Bucket(
            self, "UploadBucket",
            bucket_name=f"file-upload-{unique_suffix}",
            versioned=True,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            encryption=s3.BucketEncryption.S3_MANAGED,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="delete-old-versions",
                    noncurrent_version_expiration=Duration.days(7),
                    enabled=True
                )
            ]
        )

        # Valid files bucket - approved file storage
        self.valid_bucket = s3.Bucket(
            self, "ValidFilesBucket",
            bucket_name=f"valid-files-{unique_suffix}",
            versioned=True,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            encryption=s3.BucketEncryption.S3_MANAGED,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="transition-to-ia",
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30)
                        )
                    ],
                    enabled=True
                )
            ]
        )

        # Quarantine bucket - invalid file storage
        self.quarantine_bucket = s3.Bucket(
            self, "QuarantineBucket",
            bucket_name=f"quarantine-files-{unique_suffix}",
            versioned=True,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            encryption=s3.BucketEncryption.S3_MANAGED,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="delete-quarantined-files",
                    expiration=Duration.days(90),
                    enabled=True
                )
            ]
        )

    def _create_lambda_role(self) -> None:
        """
        Create IAM role for Lambda function with least privilege permissions.
        
        Follows AWS security best practices by granting only the minimum
        permissions required for file validation operations.
        """
        # Create IAM role for Lambda
        self.lambda_role = iam.Role(
            self, "FileValidationLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="IAM role for file validation Lambda function",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ]
        )

        # Add custom policy for S3 operations
        s3_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "s3:GetObject",
                "s3:DeleteObject"
            ],
            resources=[f"{self.upload_bucket.bucket_arn}/*"]
        )

        s3_put_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=["s3:PutObject"],
            resources=[
                f"{self.valid_bucket.bucket_arn}/*",
                f"{self.quarantine_bucket.bucket_arn}/*"
            ]
        )

        self.lambda_role.add_to_policy(s3_policy)
        self.lambda_role.add_to_policy(s3_put_policy)

    def _create_lambda_function(self, unique_suffix: str) -> None:
        """
        Create Lambda function for file validation.
        
        Implements serverless file validation with:
        - Python 3.12 runtime for performance
        - Optimized memory and timeout settings
        - Environment variables for configuration
        - CloudWatch logging for monitoring
        """
        # Create CloudWatch log group for Lambda
        log_group = logs.LogGroup(
            self, "FileValidationLogGroup",
            log_group_name=f"/aws/lambda/file-validator-{unique_suffix}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY
        )

        # Create Lambda function
        self.lambda_function = _lambda.Function(
            self, "FileValidationFunction",
            function_name=f"file-validator-{unique_suffix}",
            runtime=_lambda.Runtime.PYTHON_3_12,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline(self._get_lambda_code()),
            role=self.lambda_role,
            timeout=Duration.seconds(60),
            memory_size=256,
            description="Validates uploaded files and moves them to appropriate buckets",
            environment={
                "VALID_BUCKET_NAME": self.valid_bucket.bucket_name,
                "QUARANTINE_BUCKET_NAME": self.quarantine_bucket.bucket_name,
                "LOG_LEVEL": "INFO"
            },
            log_group=log_group,
            retry_attempts=2
        )

    def _configure_s3_events(self) -> None:
        """
        Configure S3 event notifications to trigger Lambda function.
        
        Sets up event-driven architecture where S3 object creation
        events automatically trigger file validation processing.
        """
        # Add S3 event notification for Lambda trigger
        self.upload_bucket.add_event_notification(
            s3.EventType.OBJECT_CREATED,
            s3n.LambdaDestination(self.lambda_function)
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources."""
        CfnOutput(
            self, "UploadBucketName",
            value=self.upload_bucket.bucket_name,
            description="Name of the S3 bucket for file uploads",
            export_name=f"{self.stack_name}-UploadBucket"
        )

        CfnOutput(
            self, "ValidFilesBucketName",
            value=self.valid_bucket.bucket_name,
            description="Name of the S3 bucket for valid files",
            export_name=f"{self.stack_name}-ValidFilesBucket"
        )

        CfnOutput(
            self, "QuarantineBucketName",
            value=self.quarantine_bucket.bucket_name,
            description="Name of the S3 bucket for quarantined files",
            export_name=f"{self.stack_name}-QuarantineBucket"
        )

        CfnOutput(
            self, "LambdaFunctionArn",
            value=self.lambda_function.function_arn,
            description="ARN of the file validation Lambda function",
            export_name=f"{self.stack_name}-LambdaFunction"
        )

        CfnOutput(
            self, "LambdaFunctionName",
            value=self.lambda_function.function_name,
            description="Name of the file validation Lambda function"
        )

    def _get_lambda_code(self) -> str:
        """
        Return the Lambda function code for file validation.
        
        Returns:
            str: Complete Lambda function code with validation logic
        """
        return '''
import json
import boto3
import urllib.parse
import os
import logging
from datetime import datetime
from typing import Dict, Any, List

# Configure logging
log_level = os.environ.get('LOG_LEVEL', 'INFO')
logger = logging.getLogger()
logger.setLevel(getattr(logging, log_level))

# Initialize S3 client
s3_client = boto3.client('s3')

# File validation configuration
MAX_FILE_SIZE = 10 * 1024 * 1024  # 10 MB
ALLOWED_EXTENSIONS = ['.txt', '.pdf', '.jpg', '.jpeg', '.png', '.doc', '.docx', '.csv', '.json']

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for S3 file validation.
    
    Processes S3 event notifications, validates uploaded files,
    and moves them to appropriate destination buckets.
    
    Args:
        event: S3 event notification
        context: Lambda context object
        
    Returns:
        Dict containing status code and processing results
    """
    logger.info(f"Received S3 event: {json.dumps(event, default=str)}")
    
    # Get environment variables
    valid_bucket = os.environ['VALID_BUCKET_NAME']
    quarantine_bucket = os.environ['QUARANTINE_BUCKET_NAME']
    
    processing_results = []
    
    try:
        for record in event['Records']:
            result = process_s3_record(record, valid_bucket, quarantine_bucket)
            processing_results.append(result)
            
    except Exception as e:
        logger.error(f"Error processing S3 event: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error processing files: {str(e)}')
        }
    
    logger.info(f"File validation completed. Processed {len(processing_results)} files")
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'File validation completed successfully',
            'processed_files': len(processing_results),
            'results': processing_results
        })
    }

def process_s3_record(record: Dict[str, Any], valid_bucket: str, quarantine_bucket: str) -> Dict[str, Any]:
    """
    Process individual S3 record from event notification.
    
    Args:
        record: Individual S3 event record
        valid_bucket: Name of bucket for valid files
        quarantine_bucket: Name of bucket for quarantined files
        
    Returns:
        Dict containing processing results for this file
    """
    # Extract S3 information from event record
    bucket_name = record['s3']['bucket']['name']
    object_key = urllib.parse.unquote_plus(record['s3']['object']['key'])
    object_size = record['s3']['object']['size']
    
    logger.info(f"Processing file: {object_key} (Size: {object_size} bytes)")
    
    # Validate the file
    validation_result = validate_file(object_key, object_size)
    
    # Determine destination bucket based on validation
    if validation_result['valid']:
        destination_bucket = valid_bucket
        logger.info(f"✅ File {object_key} passed validation")
    else:
        destination_bucket = quarantine_bucket
        logger.warning(f"❌ File {object_key} failed validation: {validation_result['reason']}")
    
    # Move file to appropriate destination
    move_result = move_file(bucket_name, object_key, destination_bucket)
    
    return {
        'file': object_key,
        'size': object_size,
        'validation': validation_result,
        'destination': destination_bucket,
        'moved': move_result['success'],
        'error': move_result.get('error')
    }

def validate_file(filename: str, file_size: int) -> Dict[str, Any]:
    """
    Validate file based on size and extension.
    
    Args:
        filename: Name of the file to validate
        file_size: Size of the file in bytes
        
    Returns:
        Dict containing validation result and reason
    """
    # Check file size limit
    if file_size > MAX_FILE_SIZE:
        return {
            'valid': False,
            'reason': f'File size {file_size:,} bytes exceeds maximum {MAX_FILE_SIZE:,} bytes'
        }
    
    # Check for empty files
    if file_size == 0:
        return {
            'valid': False,
            'reason': 'File is empty (0 bytes)'
        }
    
    # Extract and validate file extension
    if '.' not in filename:
        return {
            'valid': False,
            'reason': 'File has no extension'
        }
    
    file_extension = '.' + filename.lower().split('.')[-1]
    if file_extension not in ALLOWED_EXTENSIONS:
        return {
            'valid': False,
            'reason': f'File extension {file_extension} not in allowed list: {ALLOWED_EXTENSIONS}'
        }
    
    # Additional filename validation
    if len(filename) > 255:
        return {
            'valid': False,
            'reason': 'Filename exceeds 255 character limit'
        }
    
    logger.info(f"File {filename} passed all validation checks")
    return {
        'valid': True,
        'reason': 'File passed all validation checks'
    }

def move_file(source_bucket: str, object_key: str, destination_bucket: str) -> Dict[str, Any]:
    """
    Move file from source bucket to destination bucket with date organization.
    
    Args:
        source_bucket: Source S3 bucket name
        object_key: S3 object key
        destination_bucket: Destination S3 bucket name
        
    Returns:
        Dict containing move operation results
    """
    try:
        # Create destination key with date-based organization
        current_date = datetime.now().strftime('%Y/%m/%d')
        destination_key = f"{current_date}/{object_key}"
        
        # Copy file to destination bucket
        copy_source = {'Bucket': source_bucket, 'Key': object_key}
        s3_client.copy_object(
            CopySource=copy_source,
            Bucket=destination_bucket,
            Key=destination_key,
            MetadataDirective='COPY',
            TaggingDirective='COPY'
        )
        
        logger.info(f"Successfully copied {object_key} to {destination_bucket}/{destination_key}")
        
        # Delete original file from source bucket
        s3_client.delete_object(
            Bucket=source_bucket,
            Key=object_key
        )
        
        logger.info(f"Successfully deleted original file {object_key} from {source_bucket}")
        
        return {
            'success': True,
            'destination_key': destination_key
        }
        
    except Exception as e:
        error_msg = f"Failed to move file {object_key}: {str(e)}"
        logger.error(error_msg, exc_info=True)
        return {
            'success': False,
            'error': error_msg
        }
'''


class FileValidationApp(cdk.App):
    """CDK Application for File Validation System."""

    def __init__(self):
        super().__init__()

        # Get environment configuration
        account = self.node.try_get_context("account") or os.environ.get("CDK_DEFAULT_ACCOUNT")
        region = self.node.try_get_context("region") or os.environ.get("CDK_DEFAULT_REGION")

        # Create the main stack
        FileValidationStack(
            self, "FileValidationStack",
            env=cdk.Environment(account=account, region=region),
            description="Simple File Validation with S3 and Lambda (CDK Python)",
            tags={
                "Project": "FileValidation",
                "Environment": "Demo",
                "ManagedBy": "CDK"
            }
        )


# Create and run the CDK application
if __name__ == "__main__":
    app = FileValidationApp()
    app.synth()