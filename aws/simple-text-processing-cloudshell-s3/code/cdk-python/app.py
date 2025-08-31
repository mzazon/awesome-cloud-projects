#!/usr/bin/env python3
"""
AWS CDK Python application for Simple Text Processing with CloudShell and S3.

This CDK application creates the infrastructure needed for text processing workflows
using AWS CloudShell and S3 storage. The infrastructure includes an S3 bucket with
organized folder structure for input and output files.

Author: AWS CDK Generator
Version: 1.0
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    CfnOutput,
    RemovalPolicy,
    aws_s3 as s3,
    aws_iam as iam,
)
from constructs import Construct
from typing import Optional


class SimpleTextProcessingStack(Stack):
    """
    CDK Stack for Simple Text Processing with CloudShell and S3.
    
    This stack creates:
    - S3 bucket for storing input and output text files
    - Proper IAM permissions for CloudShell access
    - Bucket policies for secure access
    - Cost-optimized storage settings
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        bucket_name_prefix: Optional[str] = None,
        **kwargs
    ) -> None:
        """
        Initialize the Simple Text Processing Stack.
        
        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            bucket_name_prefix: Optional prefix for the S3 bucket name
            **kwargs: Additional keyword arguments
        """
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique bucket name with prefix if provided
        if bucket_name_prefix:
            bucket_name = f"{bucket_name_prefix}-{self.account}-{self.region}"
        else:
            bucket_name = f"text-processing-demo-{self.account}-{self.region}"

        # Create S3 bucket for text processing data
        self.text_processing_bucket = s3.Bucket(
            self,
            "TextProcessingBucket",
            bucket_name=bucket_name,
            # Security configurations
            versioning=False,  # Not needed for this simple use case
            public_read_access=False,
            public_write_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            
            # Encryption configuration
            encryption=s3.BucketEncryption.S3_MANAGED,
            enforce_ssl=True,
            
            # Cost optimization settings
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="TextProcessingLifecycle",
                    enabled=True,
                    # Transition files to IA after 30 days for cost optimization
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=cdk.Duration.days(30)
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=cdk.Duration.days(90)
                        )
                    ],
                    # Auto-delete incomplete multipart uploads to reduce costs
                    abort_incomplete_multipart_upload_after=cdk.Duration.days(1)
                )
            ],
            
            # For development/testing - change to RETAIN for production
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        # Create a bucket policy for CloudShell access
        self._create_cloudshell_bucket_policy()
        
        # Create folder structure using S3 deployment (optional)
        self._create_folder_structure()

        # Output the bucket information
        self._create_outputs()

    def _create_cloudshell_bucket_policy(self) -> None:
        """
        Create IAM policy statements for CloudShell access to the S3 bucket.
        
        This policy allows CloudShell users to read and write to the bucket
        while maintaining security best practices.
        """
        # Allow CloudShell service to access the bucket
        cloudshell_policy_statement = iam.PolicyStatement(
            sid="AllowCloudShellAccess",
            effect=iam.Effect.ALLOW,
            principals=[
                iam.ServicePrincipal("cloudshell.amazonaws.com"),
                # Also allow current account users (for CloudShell sessions)
                iam.AccountRootPrincipal()
            ],
            actions=[
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:ListBucket",
                "s3:GetObjectVersion"
            ],
            resources=[
                self.text_processing_bucket.bucket_arn,
                f"{self.text_processing_bucket.bucket_arn}/*"
            ],
            conditions={
                "StringEquals": {
                    "aws:RequestedRegion": self.region
                }
            }
        )

        # Add the policy statement to the bucket
        self.text_processing_bucket.add_to_resource_policy(cloudshell_policy_statement)

    def _create_folder_structure(self) -> None:
        """
        Create logical folder structure in S3 for organized data management.
        
        This creates placeholder objects to establish the input/ and output/
        folder structure that will be used in the text processing workflow.
        """
        # Note: S3 doesn't have real folders, but we can create placeholder objects
        # The actual folders will be created when files are uploaded with prefixes
        pass  # Folders will be created naturally when objects are uploaded

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for easy reference."""
        
        CfnOutput(
            self,
            "TextProcessingBucketName",
            value=self.text_processing_bucket.bucket_name,
            description="Name of the S3 bucket for text processing data",
            export_name=f"{self.stack_name}-BucketName"
        )

        CfnOutput(
            self,
            "TextProcessingBucketArn",
            value=self.text_processing_bucket.bucket_arn,
            description="ARN of the S3 bucket for text processing data",
            export_name=f"{self.stack_name}-BucketArn"
        )

        CfnOutput(
            self,
            "InputFolderPath",
            value=f"s3://{self.text_processing_bucket.bucket_name}/input/",
            description="S3 path for input text files",
            export_name=f"{self.stack_name}-InputPath"
        )

        CfnOutput(
            self,
            "OutputFolderPath",
            value=f"s3://{self.text_processing_bucket.bucket_name}/output/",
            description="S3 path for processed output files",
            export_name=f"{self.stack_name}-OutputPath"
        )

        CfnOutput(
            self,
            "CloudShellAccessCommand",
            value=f"aws s3 ls s3://{self.text_processing_bucket.bucket_name}/",
            description="AWS CLI command to list bucket contents from CloudShell",
            export_name=f"{self.stack_name}-AccessCommand"
        )


def main() -> None:
    """
    Main function to create and deploy the CDK application.
    
    This function initializes the CDK app, creates the stack with proper
    configuration, and adds necessary tags for resource management.
    """
    app = cdk.App()

    # Get configuration from CDK context or environment variables
    bucket_prefix = app.node.try_get_context("bucketPrefix")
    
    # Create the stack with proper environment configuration
    stack = SimpleTextProcessingStack(
        app,
        "SimpleTextProcessingStack",
        bucket_name_prefix=bucket_prefix,
        env=Environment(
            account=app.node.try_get_context("account"),
            region=app.node.try_get_context("region")
        ),
        description="Infrastructure for simple text processing with CloudShell and S3"
    )

    # Add tags to all resources in the stack
    cdk.Tags.of(stack).add("Project", "SimpleTextProcessing")
    cdk.Tags.of(stack).add("Environment", app.node.try_get_context("environment") or "development")
    cdk.Tags.of(stack).add("ManagedBy", "AWS-CDK")
    cdk.Tags.of(stack).add("CostCenter", "DataAnalytics")

    # Synthesize the CloudFormation template
    app.synth()


if __name__ == "__main__":
    main()