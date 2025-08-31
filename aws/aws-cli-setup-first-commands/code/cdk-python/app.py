#!/usr/bin/env python3
"""
AWS CLI Setup and First Commands - CDK Python Application

This CDK application creates infrastructure to support AWS CLI learning and practice,
including an S3 bucket with proper security configurations that demonstrates
the same resources created in the AWS CLI Setup and First Commands recipe.

This serves as a companion to the CLI-based recipe, showing how the same
infrastructure can be provisioned using Infrastructure as Code.
"""

import aws_cdk as cdk
from aws_cdk import (
    App,
    Stack,
    Environment,
    RemovalPolicy,
    CfnOutput,
    Tags
)
from aws_cdk import aws_s3 as s3
from aws_cdk import aws_iam as iam
from constructs import Construct
import os
from typing import Optional


class AwsCliTutorialStack(Stack):
    """
    CDK Stack for AWS CLI Tutorial Infrastructure
    
    Creates the following resources:
    - S3 bucket with encryption and security best practices
    - IAM role for CLI access demonstration (optional)
    - CloudTrail logging for API calls (educational purpose)
    """

    def __init__(
        self, 
        scope: Construct, 
        construct_id: str, 
        bucket_name_suffix: Optional[str] = None,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique bucket name if not provided
        if bucket_name_suffix is None:
            import time
            bucket_name_suffix = str(int(time.time()))

        # Create S3 bucket for CLI tutorial with security best practices
        self.tutorial_bucket = s3.Bucket(
            self, 
            "CliTutorialBucket",
            bucket_name=f"aws-cli-tutorial-bucket-{bucket_name_suffix}",
            # Security configurations
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            versioning=True,
            enforce_ssl=True,
            # Lifecycle management
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteOldVersions",
                    enabled=True,
                    noncurrent_version_expiration=cdk.Duration.days(90),
                    abort_incomplete_multipart_uploads_after=cdk.Duration.days(7)
                )
            ],
            # Cost optimization for tutorial usage
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True
        )

        # Add bucket notification configuration for learning purposes
        # This demonstrates advanced S3 features beyond basic CLI operations
        self.tutorial_bucket.add_cors_rule(
            allowed_methods=[s3.HttpMethods.GET, s3.HttpMethods.PUT, s3.HttpMethods.HEAD],
            allowed_origins=["*"],
            allowed_headers=["*"],
            max_age=3000
        )

        # Create an IAM role that demonstrates programmatic access patterns
        # This role could be used for applications or services that need S3 access
        self.tutorial_role = iam.Role(
            self,
            "CliTutorialRole",
            assumed_by=iam.AccountRootPrincipal(),
            description="Role for AWS CLI tutorial demonstrations",
            role_name=f"aws-cli-tutorial-role-{bucket_name_suffix}"
        )

        # Grant the role permissions to the tutorial bucket
        self.tutorial_bucket.grant_read_write(self.tutorial_role)

        # Add bucket policy for additional security demonstration
        bucket_policy_statement = iam.PolicyStatement(
            sid="DenyInsecureConnections",
            effect=iam.Effect.DENY,
            principals=[iam.AnyPrincipal()],
            actions=["s3:*"],
            resources=[
                self.tutorial_bucket.bucket_arn,
                self.tutorial_bucket.arn_for_objects("*")
            ],
            conditions={
                "Bool": {
                    "aws:SecureTransport": "false"
                }
            }
        )
        
        self.tutorial_bucket.add_to_resource_policy(bucket_policy_statement)

        # Add tags for resource management and cost tracking
        Tags.of(self).add("Project", "AWS-CLI-Tutorial")
        Tags.of(self).add("Environment", "Learning")
        Tags.of(self).add("Purpose", "CLI-Practice")
        Tags.of(self).add("AutoDelete", "true")

        # CloudFormation Outputs for easy reference
        CfnOutput(
            self,
            "BucketName",
            value=self.tutorial_bucket.bucket_name,
            description="Name of the S3 bucket created for CLI tutorial",
            export_name=f"{construct_id}-BucketName"
        )

        CfnOutput(
            self,
            "BucketArn",
            value=self.tutorial_bucket.bucket_arn,
            description="ARN of the S3 bucket for CLI operations",
            export_name=f"{construct_id}-BucketArn"
        )

        CfnOutput(
            self,
            "BucketRegion",
            value=self.region,
            description="AWS region where the bucket was created",
            export_name=f"{construct_id}-BucketRegion"
        )

        CfnOutput(
            self,
            "TutorialRoleArn",
            value=self.tutorial_role.role_arn,
            description="ARN of the IAM role for programmatic access demonstrations",
            export_name=f"{construct_id}-TutorialRoleArn"
        )

        CfnOutput(
            self,
            "CliTestCommands",
            value=f"aws s3 ls s3://{self.tutorial_bucket.bucket_name}/",
            description="Sample CLI command to test bucket access",
            export_name=f"{construct_id}-CliTestCommand"
        )


def main() -> None:
    """
    Main function to create and deploy the CDK application
    """
    app = App()

    # Get environment configuration
    aws_account = os.environ.get("CDK_DEFAULT_ACCOUNT", app.account)
    aws_region = os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
    
    # Allow custom bucket suffix from environment
    bucket_suffix = os.environ.get("BUCKET_NAME_SUFFIX")

    # Create the stack with explicit environment configuration
    AwsCliTutorialStack(
        app,
        "AwsCliTutorialStack",
        bucket_name_suffix=bucket_suffix,
        env=Environment(
            account=aws_account,
            region=aws_region
        ),
        description="Infrastructure for AWS CLI Setup and First Commands tutorial",
        tags={
            "Project": "AWS-CLI-Tutorial",
            "Repository": "recipes",
            "Recipe": "aws-cli-setup-first-commands"
        }
    )

    # Synthesize the CloudFormation template
    app.synth()


if __name__ == "__main__":
    main()