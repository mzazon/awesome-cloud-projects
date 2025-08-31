#!/usr/bin/env python3
"""
CDK Python application for Visual Infrastructure Design with Application Composer and CloudFormation.

This application creates a static website hosting solution using S3 bucket with proper
website configuration and public access policy. The infrastructure demonstrates how
visual design patterns from Application Composer translate to CDK code.
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_s3 as s3,
    aws_iam as iam,
)
from constructs import Construct


class VisualInfrastructureComposerStack(Stack):
    """
    CDK Stack for Visual Infrastructure Design with S3 Static Website Hosting.
    
    This stack creates:
    - S3 bucket configured for static website hosting
    - Bucket policy for public read access
    - Website configuration with index and error documents
    """

    def __init__(
        self, 
        scope: Construct, 
        construct_id: str, 
        bucket_name: str = None,
        **kwargs
    ) -> None:
        """
        Initialize the Visual Infrastructure Composer stack.

        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            bucket_name: Custom bucket name (optional, auto-generated if not provided)
            **kwargs: Additional keyword arguments
        """
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique bucket name if not provided
        if not bucket_name:
            # Use stack name and account ID for uniqueness
            account_id = self.account[:8]  # First 8 chars of account ID
            bucket_name = f"visual-website-{construct_id.lower()}-{account_id}"
        
        # Store bucket name for use in outputs
        self.bucket_name = bucket_name

        # Create S3 bucket for static website hosting
        self.website_bucket = self._create_website_bucket()
        
        # Configure bucket policy for public access
        self._configure_bucket_policy()
        
        # Create CloudFormation outputs
        self._create_outputs()

    def _create_website_bucket(self) -> s3.Bucket:
        """
        Create S3 bucket configured for static website hosting.
        
        Returns:
            s3.Bucket: The created S3 bucket
        """
        bucket = s3.Bucket(
            self,
            "WebsiteBucket",
            bucket_name=self.bucket_name,
            # Website configuration
            website_index_document="index.html",
            website_error_document="error.html",
            # Public access configuration
            public_read_access=True,
            block_public_access=s3.BlockPublicAccess(
                block_public_acls=False,
                block_public_policy=False,
                ignore_public_acls=False,
                restrict_public_buckets=False
            ),
            # Lifecycle configuration
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            # Versioning (optional, disabled for cost optimization)
            versioned=False,
            # Server access logging (disabled for simplicity)
            server_access_logs_bucket=None,
            # Encryption (server-side encryption with S3 managed keys)
            encryption=s3.BucketEncryption.S3_MANAGED,
            # CORS configuration for web applications
            cors=[
                s3.CorsRule(
                    allowed_methods=[
                        s3.HttpMethods.GET,
                        s3.HttpMethods.HEAD
                    ],
                    allowed_origins=["*"],
                    allowed_headers=["*"],
                    max_age=Duration.hours(1).to_seconds()
                )
            ]
        )

        # Add tags for resource management
        cdk.Tags.of(bucket).add("Project", "VisualInfrastructureComposer")
        cdk.Tags.of(bucket).add("Environment", "Development")
        cdk.Tags.of(bucket).add("CreatedBy", "CDK")
        cdk.Tags.of(bucket).add("Purpose", "StaticWebsiteHosting")

        return bucket

    def _configure_bucket_policy(self) -> None:
        """
        Configure bucket policy to allow public read access for website hosting.
        
        This method creates a bucket policy that allows anonymous users to read
        objects from the S3 bucket, which is required for static website hosting.
        """
        # Create policy document for public read access
        policy_document = iam.PolicyDocument(
            statements=[
                iam.PolicyStatement(
                    sid="PublicReadGetObject",
                    effect=iam.Effect.ALLOW,
                    principals=[iam.AnyPrincipal()],
                    actions=["s3:GetObject"],
                    resources=[f"{self.website_bucket.bucket_arn}/*"],
                    conditions={
                        "StringEquals": {
                            "s3:ExistingObjectTag/PublicRead": "true"
                        }
                    }
                ),
                # Allow public access to all objects (simplified for demo)
                iam.PolicyStatement(
                    sid="PublicReadGetObjectSimplified",
                    effect=iam.Effect.ALLOW,
                    principals=[iam.AnyPrincipal()],
                    actions=["s3:GetObject"],
                    resources=[f"{self.website_bucket.bucket_arn}/*"]
                )
            ]
        )

        # Apply bucket policy
        bucket_policy = s3.BucketPolicy(
            self,
            "WebsiteBucketPolicy",
            bucket=self.website_bucket,
            policy_document=policy_document
        )

        # Add dependency to ensure bucket is created before policy
        bucket_policy.node.add_dependency(self.website_bucket)

    def _create_outputs(self) -> None:
        """
        Create CloudFormation outputs for important resource identifiers.
        
        These outputs provide key information about the deployed infrastructure
        that can be used by other stacks or for manual verification.
        """
        # S3 bucket name
        CfnOutput(
            self,
            "BucketName",
            value=self.website_bucket.bucket_name,
            description="Name of the S3 bucket hosting the static website",
            export_name=f"{self.stack_name}-BucketName"
        )

        # Website URL
        website_url = f"http://{self.website_bucket.bucket_name}.s3-website-{self.region}.amazonaws.com"
        CfnOutput(
            self,
            "WebsiteURL",
            value=website_url,
            description="URL of the static website hosted on S3",
            export_name=f"{self.stack_name}-WebsiteURL"
        )

        # Bucket ARN
        CfnOutput(
            self,
            "BucketArn",
            value=self.website_bucket.bucket_arn,
            description="ARN of the S3 bucket",
            export_name=f"{self.stack_name}-BucketArn"
        )

        # Website domain endpoint
        CfnOutput(
            self,
            "WebsiteDomainName",
            value=self.website_bucket.bucket_website_domain_name,
            description="Domain name of the website endpoint",
            export_name=f"{self.stack_name}-WebsiteDomainName"
        )


class VisualInfrastructureComposerApp:
    """
    CDK Application for Visual Infrastructure Composer demonstration.
    
    This class encapsulates the CDK app configuration and stack deployment
    logic, providing a clean interface for infrastructure deployment.
    """

    def __init__(self) -> None:
        """Initialize the CDK application."""
        self.app = cdk.App()
        self._create_stacks()

    def _create_stacks(self) -> None:
        """Create and configure CDK stacks."""
        # Get configuration from context or environment variables
        config = self._get_configuration()
        
        # Create the main infrastructure stack
        stack = VisualInfrastructureComposerStack(
            self.app,
            "VisualInfrastructureComposerStack",
            bucket_name=config.get("bucket_name"),
            env=Environment(
                account=config.get("account"),
                region=config.get("region")
            ),
            description="Visual Infrastructure Design with Application Composer and CloudFormation - CDK Python implementation"
        )

        # Add stack-level tags
        cdk.Tags.of(stack).add("Application", "VisualInfrastructureComposer")
        cdk.Tags.of(stack).add("Repository", "recipes")
        cdk.Tags.of(stack).add("IaCTool", "CDK-Python")

    def _get_configuration(self) -> Dict[str, Any]:
        """
        Get configuration from CDK context or environment variables.
        
        Returns:
            Dict[str, Any]: Configuration dictionary
        """
        return {
            "account": (
                self.app.node.try_get_context("account") 
                or os.environ.get("CDK_DEFAULT_ACCOUNT")
            ),
            "region": (
                self.app.node.try_get_context("region") 
                or os.environ.get("CDK_DEFAULT_REGION") 
                or "us-east-1"
            ),
            "bucket_name": (
                self.app.node.try_get_context("bucket_name")
                or os.environ.get("BUCKET_NAME")
            )
        }

    def synthesize(self) -> None:
        """Synthesize the CDK application."""
        self.app.synth()


def main() -> None:
    """
    Main entry point for the CDK application.
    
    This function creates and synthesizes the CDK application,
    generating CloudFormation templates for deployment.
    """
    try:
        # Create and synthesize the CDK application
        app = VisualInfrastructureComposerApp()
        app.synthesize()
        
        print("✅ CDK application synthesized successfully")
        print("📄 CloudFormation templates generated in cdk.out/")
        print("🚀 Ready for deployment with 'cdk deploy'")
        
    except Exception as e:
        print(f"❌ Error synthesizing CDK application: {str(e)}")
        raise


if __name__ == "__main__":
    main()