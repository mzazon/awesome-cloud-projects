#!/usr/bin/env python3
"""
CDK Python application for Simple Infrastructure Templates with CloudFormation and S3

This CDK application creates an S3 bucket with security best practices including:
- Server-side encryption with AES-256
- Versioning enabled for data protection
- Public access blocked to prevent data exposure
- Proper tagging for resource management

Author: AWS CDK Recipe Generator
Version: 1.0
"""

import os
from typing import Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    CfnOutput,
    RemovalPolicy,
    aws_s3 as s3,
)
from constructs import Construct


class SimpleS3InfrastructureStack(Stack):
    """
    CloudFormation stack that creates an S3 bucket with enterprise security settings.
    
    This stack demonstrates Infrastructure as Code best practices by creating
    a secure S3 bucket with encryption, versioning, and access controls.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        bucket_name: Optional[str] = None,
        **kwargs
    ) -> None:
        """
        Initialize the Simple S3 Infrastructure Stack.
        
        Args:
            scope: The parent construct
            construct_id: Unique identifier for this stack
            bucket_name: Optional custom bucket name
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique bucket name if not provided
        if not bucket_name:
            # Use account ID and region to ensure uniqueness
            account_id = self.account
            region = self.region
            bucket_name = f"infrastructure-bucket-{account_id}-{region}"

        # Create S3 bucket with security best practices
        self.s3_bucket = s3.Bucket(
            self,
            "MyS3Bucket",
            bucket_name=bucket_name,
            # Enable versioning for data protection and recovery
            versioned=True,
            # Enable server-side encryption with AES-256
            encryption=s3.BucketEncryption.S3_MANAGED,
            # Enable bucket key for cost optimization
            bucket_key_enabled=True,
            # Block all public access to prevent data exposure
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            # Configure removal policy for cleanup
            removal_policy=RemovalPolicy.DESTROY,
            # Enable auto-deletion of objects when stack is deleted
            auto_delete_objects=True,
        )

        # Add tags for resource management and cost allocation
        cdk.Tags.of(self.s3_bucket).add("Environment", "Development")
        cdk.Tags.of(self.s3_bucket).add("Purpose", "Infrastructure-Template-Demo")
        cdk.Tags.of(self.s3_bucket).add("CreatedBy", "CDK-Python")
        cdk.Tags.of(self.s3_bucket).add("Recipe", "simple-infrastructure-templates")

        # CloudFormation outputs for integration with other resources
        CfnOutput(
            self,
            "BucketName",
            value=self.s3_bucket.bucket_name,
            description="Name of the created S3 bucket",
            export_name=f"{self.stack_name}-BucketName",
        )

        CfnOutput(
            self,
            "BucketArn",
            value=self.s3_bucket.bucket_arn,
            description="ARN of the created S3 bucket",
            export_name=f"{self.stack_name}-BucketArn",
        )

        CfnOutput(
            self,
            "BucketDomainName",
            value=self.s3_bucket.bucket_domain_name,
            description="Domain name of the S3 bucket",
            export_name=f"{self.stack_name}-BucketDomainName",
        )

        CfnOutput(
            self,
            "BucketWebsiteUrl",
            value=self.s3_bucket.bucket_website_url,
            description="Website URL of the S3 bucket",
            export_name=f"{self.stack_name}-BucketWebsiteUrl",
        )


def main() -> None:
    """
    Main application entry point.
    
    Creates and deploys the CDK application with the S3 infrastructure stack.
    """
    # Initialize CDK application
    app = cdk.App()

    # Get configuration from CDK context or environment variables
    account_id = os.environ.get("CDK_DEFAULT_ACCOUNT") or app.node.try_get_context("account")
    region = os.environ.get("CDK_DEFAULT_REGION") or app.node.try_get_context("region")
    bucket_name = app.node.try_get_context("bucketName")

    # Create environment configuration
    env = Environment(account=account_id, region=region) if account_id and region else None

    # Create the infrastructure stack
    SimpleS3InfrastructureStack(
        app,
        "SimpleS3InfrastructureStack",
        bucket_name=bucket_name,
        env=env,
        description="Simple S3 bucket infrastructure with security best practices",
    )

    # Synthesize CloudFormation template
    app.synth()


if __name__ == "__main__":
    main()