#!/usr/bin/env python3
"""
AWS CDK Python application for File Sharing Solutions with S3 Presigned URLs.

This CDK application creates the infrastructure for a secure file sharing system
using Amazon S3 presigned URLs. It provides temporary, time-limited access to
specific objects without requiring AWS credentials.

Author: AWS CDK Generator
Version: 1.0.0
"""

import os
from typing import Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    CfnOutput,
    RemovalPolicy,
    Duration,
    aws_s3 as s3,
    aws_iam as iam,
    aws_cloudtrail as cloudtrail,
    aws_s3_notifications as s3n,
    aws_logs as logs,
)
from constructs import Construct


class FileShareStack(Stack):
    """
    CDK Stack for S3 Presigned URL File Sharing Solution.
    
    This stack creates:
    - Private S3 bucket for file storage
    - IAM policies for presigned URL generation
    - CloudTrail for audit logging
    - Sample bucket structure
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        bucket_name: Optional[str] = None,
        enable_versioning: bool = True,
        enable_encryption: bool = True,
        enable_access_logging: bool = True,
        **kwargs
    ) -> None:
        """
        Initialize the File Sharing Stack.

        Args:
            scope: CDK App or Stage scope
            construct_id: Unique identifier for this stack
            bucket_name: Optional custom bucket name (auto-generated if not provided)
            enable_versioning: Enable S3 bucket versioning
            enable_encryption: Enable S3 bucket encryption
            enable_access_logging: Enable S3 access logging
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique bucket name if not provided
        if not bucket_name:
            account_id = self.account
            region = self.region
            bucket_name = f"file-sharing-{account_id}-{region}"

        # Create the main file sharing bucket
        self.file_sharing_bucket = self._create_file_sharing_bucket(
            bucket_name=bucket_name,
            enable_versioning=enable_versioning,
            enable_encryption=enable_encryption,
        )

        # Create access logging bucket if enabled
        if enable_access_logging:
            self.access_logs_bucket = self._create_access_logs_bucket()
            self.file_sharing_bucket.add_property_override(
                "LoggingConfiguration",
                {
                    "DestinationBucketName": self.access_logs_bucket.bucket_name,
                    "LogFilePrefix": "access-logs/"
                }
            )

        # Create IAM role for presigned URL generation
        self.presigned_url_role = self._create_presigned_url_role()

        # Create CloudTrail for audit logging
        self.audit_trail = self._create_audit_trail()

        # Create sample folder structure
        self._create_sample_structure()

        # Output important values
        self._create_outputs()

    def _create_file_sharing_bucket(
        self,
        bucket_name: str,
        enable_versioning: bool,
        enable_encryption: bool,
    ) -> s3.Bucket:
        """
        Create the main S3 bucket for file sharing.

        Args:
            bucket_name: Name for the S3 bucket
            enable_versioning: Whether to enable versioning
            enable_encryption: Whether to enable encryption

        Returns:
            S3 Bucket construct
        """
        # Configure bucket encryption
        encryption = (
            s3.BucketEncryption.S3_MANAGED
            if enable_encryption
            else s3.BucketEncryption.UNENCRYPTED
        )

        # Configure versioning
        versioned = enable_versioning

        bucket = s3.Bucket(
            self,
            "FileShareBucket",
            bucket_name=bucket_name,
            # Security: Block all public access
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            # Security: Enable encryption at rest
            encryption=encryption,
            # Enable versioning for data protection
            versioned=versioned,
            # Lifecycle: Move to IA after 30 days, archive after 90 days
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="transition-to-ia",
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
                s3.LifecycleRule(
                    id="delete-incomplete-uploads",
                    enabled=True,
                    abort_incomplete_multipart_upload_after=Duration.days(7),
                ),
            ],
            # Security: Enable event notifications for monitoring
            event_bridge_enabled=True,
            # Development: Remove bucket on stack deletion (change for production)
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        # Add bucket notification for monitoring uploads
        bucket.add_event_notification(
            s3.EventType.OBJECT_CREATED,
            s3n.SnsDestination(
                topic=self._create_notification_topic()
            ),
            s3.NotificationKeyFilter(prefix="uploads/")
        )

        return bucket

    def _create_access_logs_bucket(self) -> s3.Bucket:
        """
        Create a separate bucket for S3 access logs.

        Returns:
            S3 Bucket for access logs
        """
        logs_bucket = s3.Bucket(
            self,
            "AccessLogsBucket",
            bucket_name=f"{self.file_sharing_bucket.bucket_name}-access-logs",
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            encryption=s3.BucketEncryption.S3_MANAGED,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="delete-old-logs",
                    enabled=True,
                    expiration=Duration.days(90),
                ),
            ],
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        return logs_bucket

    def _create_notification_topic(self):
        """Create SNS topic for bucket notifications."""
        from aws_cdk import aws_sns as sns
        
        topic = sns.Topic(
            self,
            "FileShareNotifications",
            display_name="File Share Upload Notifications",
        )
        
        return topic

    def _create_presigned_url_role(self) -> iam.Role:
        """
        Create IAM role for generating presigned URLs.

        Returns:
            IAM Role with appropriate permissions
        """
        role = iam.Role(
            self,
            "PresignedUrlRole",
            role_name=f"FileSharePresignedUrlRole-{self.region}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Role for generating S3 presigned URLs for file sharing",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
        )

        # Add custom policy for S3 operations
        presigned_url_policy = iam.Policy(
            self,
            "PresignedUrlPolicy",
            policy_name="S3PresignedUrlPolicy",
            statements=[
                # Allow generating presigned URLs for downloads
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "s3:GetObject",
                        "s3:GetObjectVersion",
                    ],
                    resources=[
                        f"{self.file_sharing_bucket.bucket_arn}/*",
                    ],
                ),
                # Allow generating presigned URLs for uploads
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "s3:PutObject",
                        "s3:PutObjectAcl",
                    ],
                    resources=[
                        f"{self.file_sharing_bucket.bucket_arn}/uploads/*",
                    ],
                ),
                # Allow listing bucket contents (for batch URL generation)
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "s3:ListBucket",
                    ],
                    resources=[
                        self.file_sharing_bucket.bucket_arn,
                    ],
                ),
            ],
        )

        role.attach_inline_policy(presigned_url_policy)
        return role

    def _create_audit_trail(self) -> cloudtrail.Trail:
        """
        Create CloudTrail for auditing S3 operations.

        Returns:
            CloudTrail construct
        """
        # Create CloudWatch log group for CloudTrail
        log_group = logs.LogGroup(
            self,
            "CloudTrailLogGroup",
            log_group_name=f"/aws/cloudtrail/file-sharing-{self.region}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY,
        )

        # Create S3 bucket for CloudTrail logs
        trail_bucket = s3.Bucket(
            self,
            "CloudTrailBucket",
            bucket_name=f"cloudtrail-file-sharing-{self.account}-{self.region}",
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            encryption=s3.BucketEncryption.S3_MANAGED,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="delete-old-trail-logs",
                    enabled=True,
                    expiration=Duration.days(30),
                ),
            ],
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        # Create CloudTrail
        trail = cloudtrail.Trail(
            self,
            "FileShareAuditTrail",
            trail_name=f"file-sharing-audit-{self.region}",
            bucket=trail_bucket,
            cloud_watch_log_group=log_group,
            include_global_service_events=True,
            is_multi_region_trail=True,
            enable_file_validation=True,
        )

        # Add S3 data events for our bucket
        trail.add_s3_event_selector(
            bucket=self.file_sharing_bucket,
            object_prefix="",
            include_management_events=True,
            read_write_type=cloudtrail.ReadWriteType.ALL,
        )

        return trail

    def _create_sample_structure(self) -> None:
        """Create sample folder structure in the S3 bucket."""
        # Note: CDK doesn't directly create S3 objects, but we can use
        # BucketDeployment or custom resources. For simplicity, we'll
        # document the expected structure here.
        
        # Expected folder structure:
        # /documents/     - For files to be shared via download URLs
        # /uploads/       - For files uploaded via upload URLs
        # /templates/     - For document templates
        # /archive/       - For long-term storage
        
        pass

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important values."""
        CfnOutput(
            self,
            "FileShareBucketName",
            value=self.file_sharing_bucket.bucket_name,
            description="Name of the S3 bucket for file sharing",
            export_name=f"{self.stack_name}-FileShareBucketName",
        )

        CfnOutput(
            self,
            "FileShareBucketArn",
            value=self.file_sharing_bucket.bucket_arn,
            description="ARN of the S3 bucket for file sharing",
            export_name=f"{self.stack_name}-FileShareBucketArn",
        )

        CfnOutput(
            self,
            "PresignedUrlRoleArn",
            value=self.presigned_url_role.role_arn,
            description="ARN of the IAM role for generating presigned URLs",
            export_name=f"{self.stack_name}-PresignedUrlRoleArn",
        )

        if hasattr(self, 'access_logs_bucket'):
            CfnOutput(
                self,
                "AccessLogsBucketName",
                value=self.access_logs_bucket.bucket_name,
                description="Name of the S3 access logs bucket",
                export_name=f"{self.stack_name}-AccessLogsBucketName",
            )

        CfnOutput(
            self,
            "CloudTrailArn",
            value=self.audit_trail.trail_arn,
            description="ARN of the CloudTrail for audit logging",
            export_name=f"{self.stack_name}-CloudTrailArn",
        )

        # Output CLI commands for generating presigned URLs
        CfnOutput(
            self,
            "PresignedDownloadCommand",
            value=f"aws s3 presign s3://{self.file_sharing_bucket.bucket_name}/documents/[FILENAME] --expires-in 3600",
            description="CLI command template for generating download presigned URLs",
        )

        CfnOutput(
            self,
            "PresignedUploadCommand",
            value=f"aws s3 presign s3://{self.file_sharing_bucket.bucket_name}/uploads/[FILENAME] --expires-in 1800 --http-method PUT",
            description="CLI command template for generating upload presigned URLs",
        )


class FileShareApp(cdk.App):
    """CDK Application for File Sharing with S3 Presigned URLs."""

    def __init__(self) -> None:
        """Initialize the CDK application."""
        super().__init__()

        # Get configuration from context or environment variables
        bucket_name = self.node.try_get_context("bucketName")
        enable_versioning = self.node.try_get_context("enableVersioning") != "false"
        enable_encryption = self.node.try_get_context("enableEncryption") != "false"
        enable_access_logging = self.node.try_get_context("enableAccessLogging") != "false"

        # Create the stack
        FileShareStack(
            self,
            "FileShareStack",
            bucket_name=bucket_name,
            enable_versioning=enable_versioning,
            enable_encryption=enable_encryption,
            enable_access_logging=enable_access_logging,
            env=cdk.Environment(
                account=os.getenv("CDK_DEFAULT_ACCOUNT"),
                region=os.getenv("CDK_DEFAULT_REGION"),
            ),
            description="Infrastructure for secure file sharing using S3 presigned URLs",
        )


# Main entry point
if __name__ == "__main__":
    app = FileShareApp()
    app.synth()