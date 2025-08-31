#!/usr/bin/env python3
"""
CDK Python application for Simple Image Metadata Extractor with Lambda and S3

This CDK application creates a serverless image metadata extraction system using:
- S3 bucket for image storage with encryption and versioning
- Lambda function for metadata extraction with PIL/Pillow layer
- IAM roles with least privilege access
- CloudWatch Logs for monitoring
- S3 event notifications to trigger processing

The system automatically extracts metadata from uploaded images including
dimensions, format, file size, and EXIF data when available.
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    CfnOutput,
    RemovalPolicy,
    Duration,
    aws_s3 as s3,
    aws_lambda as _lambda,
    aws_iam as iam,
    aws_s3_notifications as s3n,
    aws_logs as logs,
)
from constructs import Construct
import os


class ImageMetadataExtractorStack(Stack):
    """
    CDK Stack for Image Metadata Extractor solution
    
    Creates all necessary AWS resources for automated image metadata extraction
    including S3 bucket, Lambda function with PIL layer, and proper IAM permissions.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names to avoid conflicts
        unique_suffix = self.node.try_get_context("unique_suffix") or "demo"
        
        # Create S3 bucket for image storage
        self.image_bucket = self._create_image_bucket(unique_suffix)
        
        # Create Lambda layer with PIL/Pillow library
        self.pillow_layer = self._create_pillow_layer()
        
        # Create Lambda function for metadata extraction
        self.metadata_function = self._create_metadata_function(unique_suffix)
        
        # Configure S3 event notifications to trigger Lambda
        self._configure_s3_notifications()
        
        # Create CloudFormation outputs
        self._create_outputs()

    def _create_image_bucket(self, unique_suffix: str) -> s3.Bucket:
        """
        Create S3 bucket with enterprise-grade security features
        
        Args:
            unique_suffix: Unique identifier for bucket naming
            
        Returns:
            S3 Bucket construct with encryption and versioning enabled
        """
        bucket = s3.Bucket(
            self,
            "ImageBucket",
            bucket_name=f"image-metadata-bucket-{unique_suffix}",
            # Enable versioning for data protection
            versioned=True,
            # Enable server-side encryption with S3-managed keys
            encryption=s3.BucketEncryption.S3_MANAGED,
            # Enable secure transport policy
            enforce_ssl=True,
            # Block all public access by default
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            # Configure lifecycle rules for cost optimization
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="delete-incomplete-multipart-uploads",
                    abort_incomplete_multipart_upload_after=Duration.days(7),
                    enabled=True,
                ),
                s3.LifecycleRule(
                    id="transition-old-versions",
                    noncurrent_version_transitions=[
                        s3.NoncurrentVersionTransition(
                            storage_class=s3.StorageClass.STANDARD_IA,
                            transition_after=Duration.days(30),
                        ),
                        s3.NoncurrentVersionTransition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(90),
                        ),
                    ],
                    enabled=True,
                ),
            ],
            # Allow CDK to destroy bucket for demo purposes
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )
        
        return bucket

    def _create_pillow_layer(self) -> _lambda.LayerVersion:
        """
        Create Lambda layer with PIL/Pillow library for image processing
        
        Returns:
            Lambda Layer construct with Pillow library
        """
        # Create Lambda layer with PIL/Pillow
        # Note: In a real deployment, you would need to create the layer zip file
        # with the Pillow library installed for the appropriate architecture
        layer = _lambda.LayerVersion(
            self,
            "PillowLayer",
            layer_version_name="pillow-image-processing",
            description="PIL/Pillow library for image processing in Lambda",
            # In production, you would reference an actual layer zip file
            # For this demo, we'll use a public layer ARN or create instructions
            code=_lambda.Code.from_inline("""
# This is a placeholder for the PIL/Pillow layer
# In production, you would:
# 1. Create a directory: mkdir -p layer/python
# 2. Install Pillow: pip install Pillow -t layer/python/
# 3. Create zip: cd layer && zip -r pillow-layer.zip python/
# 4. Use: _lambda.Code.from_asset("pillow-layer.zip")

# For AWS public layers, you can also use:
# _lambda.LayerVersion.from_layer_version_arn(
#     self, "PillowLayer",
#     layer_version_arn="arn:aws:lambda:us-east-1:770693421928:layer:Klayers-p312-Pillow:1"
# )
"""),
            compatible_runtimes=[
                _lambda.Runtime.PYTHON_3_12,
                _lambda.Runtime.PYTHON_3_11,
                _lambda.Runtime.PYTHON_3_10,
            ],
            compatible_architectures=[_lambda.Architecture.X86_64],
        )
        
        return layer

    def _create_metadata_function(self, unique_suffix: str) -> _lambda.Function:
        """
        Create Lambda function for image metadata extraction
        
        Args:
            unique_suffix: Unique identifier for function naming
            
        Returns:
            Lambda Function construct configured for image processing
        """
        # Create IAM role for Lambda function with least privilege
        lambda_role = iam.Role(
            self,
            "MetadataFunctionRole",
            role_name=f"lambda-s3-metadata-role-{unique_suffix}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="IAM role for image metadata extraction Lambda function",
            managed_policies=[
                # Basic execution role for CloudWatch Logs
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                ),
            ],
            inline_policies={
                "S3ReadPolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=["s3:GetObject"],
                            resources=[f"{self.image_bucket.bucket_arn}/*"],
                        ),
                    ],
                ),
            },
        )

        # Create Lambda function
        function = _lambda.Function(
            self,
            "MetadataFunction",
            function_name=f"image-metadata-extractor-{unique_suffix}",
            description="Extract metadata from uploaded images using PIL/Pillow",
            runtime=_lambda.Runtime.PYTHON_3_12,
            handler="lambda_function.lambda_handler",
            # Inline code for the Lambda function
            code=_lambda.Code.from_inline(self._get_lambda_function_code()),
            role=lambda_role,
            timeout=Duration.seconds(30),
            memory_size=256,
            # Attach PIL/Pillow layer
            layers=[self.pillow_layer],
            # Configure environment variables
            environment={
                "BUCKET_NAME": self.image_bucket.bucket_name,
                "LOG_LEVEL": "INFO",
            },
            # Configure CloudWatch Logs retention
            log_retention=logs.RetentionDays.ONE_WEEK,
            # Enable tracing for better monitoring
            tracing=_lambda.Tracing.ACTIVE,
            # Configure reserved concurrency to prevent cost overruns
            reserved_concurrent_executions=10,
        )

        return function

    def _get_lambda_function_code(self) -> str:
        """
        Return the Lambda function code as a string
        
        Returns:
            Python code for the Lambda function
        """
        return '''import json
import boto3
import logging
from PIL import Image
from urllib.parse import unquote_plus
import io
import os

# Initialize S3 client outside handler for reuse
s3_client = boto3.client('s3')

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

def lambda_handler(event, context):
    """
    Main Lambda handler for S3 image upload events
    Extracts metadata from uploaded images
    """
    try:
        # Process each S3 event record
        for record in event['Records']:
            # Get bucket and object key from S3 event
            bucket = record['s3']['bucket']['name']
            key = unquote_plus(record['s3']['object']['key'])
            
            logger.info(f"Processing image: {key} from bucket: {bucket}")
            
            # Download image from S3
            response = s3_client.get_object(Bucket=bucket, Key=key)
            image_content = response['Body'].read()
            
            # Extract metadata
            metadata = extract_image_metadata(image_content, key)
            
            # Log extracted metadata
            logger.info(f"Extracted metadata for {key}: {json.dumps(metadata, indent=2)}")
            
        return {
            'statusCode': 200,
            'body': json.dumps('Successfully processed images')
        }
        
    except Exception as e:
        logger.error(f"Error processing image: {str(e)}")
        raise

def extract_image_metadata(image_content, filename):
    """
    Extract comprehensive metadata from image content
    """
    try:
        # Open image with PIL
        with Image.open(io.BytesIO(image_content)) as img:
            metadata = {
                'filename': filename,
                'format': img.format,
                'mode': img.mode,
                'size': img.size,
                'width': img.width,
                'height': img.height,
                'file_size_bytes': len(image_content),
                'file_size_kb': round(len(image_content) / 1024, 2),
                'aspect_ratio': round(img.width / img.height, 2) if img.height > 0 else 0
            }
            
            # Extract EXIF data if available using getexif()
            try:
                exif_dict = img.getexif()
                if exif_dict:
                    metadata['has_exif'] = True
                    metadata['exif_tags_count'] = len(exif_dict)
                else:
                    metadata['has_exif'] = False
            except Exception:
                metadata['has_exif'] = False
                
            return metadata
            
    except Exception as e:
        logger.error(f"Error extracting metadata: {str(e)}")
        return {
            'filename': filename,
            'error': str(e),
            'file_size_bytes': len(image_content)
        }
'''

    def _configure_s3_notifications(self) -> None:
        """
        Configure S3 event notifications to trigger Lambda function
        
        Sets up notifications for JPG, JPEG, and PNG file uploads
        """
        # Add S3 event notifications for different image formats
        image_formats = [".jpg", ".jpeg", ".png"]
        
        for format_ext in image_formats:
            self.image_bucket.add_event_notification(
                s3.EventType.OBJECT_CREATED,
                s3n.LambdaDestination(self.metadata_function),
                s3.NotificationKeyFilter(suffix=format_ext),
            )

    def _create_outputs(self) -> None:
        """
        Create CloudFormation outputs for important resource information
        """
        CfnOutput(
            self,
            "BucketName",
            value=self.image_bucket.bucket_name,
            description="S3 bucket name for image uploads",
            export_name=f"{self.stack_name}-BucketName",
        )

        CfnOutput(
            self,
            "BucketArn",
            value=self.image_bucket.bucket_arn,
            description="S3 bucket ARN",
            export_name=f"{self.stack_name}-BucketArn",
        )

        CfnOutput(
            self,
            "FunctionName",
            value=self.metadata_function.function_name,
            description="Lambda function name for metadata extraction",
            export_name=f"{self.stack_name}-FunctionName",
        )

        CfnOutput(
            self,
            "FunctionArn",
            value=self.metadata_function.function_arn,
            description="Lambda function ARN",
            export_name=f"{self.stack_name}-FunctionArn",
        )

        CfnOutput(
            self,
            "LayerArn",
            value=self.pillow_layer.layer_version_arn,
            description="Pillow layer ARN for reuse in other functions",
            export_name=f"{self.stack_name}-PillowLayerArn",
        )


def main() -> None:
    """
    Main entry point for the CDK application
    
    Creates the CDK app and stack, then synthesizes the CloudFormation template
    """
    app = cdk.App()
    
    # Get stack name from context or use default
    stack_name = app.node.try_get_context("stack_name") or "ImageMetadataExtractorStack"
    
    # Create the stack
    ImageMetadataExtractorStack(
        app,
        stack_name,
        description="Simple Image Metadata Extractor with Lambda and S3 - CDK Python Implementation",
        # Add tags for resource management
        tags={
            "Project": "ImageMetadataExtractor",
            "Environment": app.node.try_get_context("environment") or "demo",
            "Owner": app.node.try_get_context("owner") or "cdk-user",
            "CostCenter": app.node.try_get_context("cost_center") or "development",
        },
    )
    
    app.synth()


if __name__ == "__main__":
    main()