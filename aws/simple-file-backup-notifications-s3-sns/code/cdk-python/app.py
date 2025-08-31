#!/usr/bin/env python3
"""
CDK Application for Simple File Backup Notifications with S3 and SNS

This CDK application creates an automated notification system that sends
email alerts whenever files are uploaded to an S3 backup bucket using
SNS (Simple Notification Service).

Architecture:
- S3 bucket with event notifications enabled
- SNS topic for email notifications
- IAM policy for S3 -> SNS integration
- Encryption and versioning enabled for security
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    CfnOutput,
    RemovalPolicy,
    aws_s3 as s3,
    aws_sns as sns,
    aws_sns_subscriptions as sns_subscriptions,
    aws_s3_notifications as s3n,
    aws_iam as iam,
)
from constructs import Construct


class SimpleFileBackupNotificationsStack(Stack):
    """
    CDK Stack for Simple File Backup Notifications
    
    Creates S3 bucket with SNS notifications for backup monitoring.
    Follows AWS Well-Architected Framework principles for security,
    reliability, and cost optimization.
    """

    def __init__(
        self, 
        scope: Construct, 
        construct_id: str, 
        email_address: str,
        bucket_name_suffix: str = None,
        **kwargs: Dict[str, Any]
    ) -> None:
        """
        Initialize the SimpleFileBackupNotificationsStack.

        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            email_address: Email address for backup notifications
            bucket_name_suffix: Optional suffix for bucket name uniqueness
            **kwargs: Additional keyword arguments passed to Stack
        """
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix if not provided
        if bucket_name_suffix is None:
            bucket_name_suffix = self.node.addr.lower()[:8]

        # Create SNS topic for backup notifications
        self.notification_topic = self._create_sns_topic(email_address)
        
        # Create S3 bucket with security features
        self.backup_bucket = self._create_backup_bucket(bucket_name_suffix)
        
        # Configure S3 event notifications to SNS
        self._configure_s3_notifications()
        
        # Create CloudFormation outputs
        self._create_outputs()

    def _create_sns_topic(self, email_address: str) -> sns.Topic:
        """
        Create SNS topic with email subscription for backup notifications.

        Args:
            email_address: Email address to subscribe to notifications

        Returns:
            sns.Topic: The created SNS topic
        """
        # Create SNS topic for backup alerts
        topic = sns.Topic(
            self,
            "BackupNotificationTopic",
            topic_name=f"backup-alerts-{self.stack_name.lower()}",
            display_name="File Backup Notifications",
            description="SNS topic for S3 backup file upload notifications"
        )

        # Add email subscription to the topic
        topic.add_subscription(
            sns_subscriptions.EmailSubscription(
                email_address=email_address,
                json=False  # Send plain text emails for better readability
            )
        )

        # Add tags for resource management
        cdk.Tags.of(topic).add("Purpose", "BackupNotifications")
        cdk.Tags.of(topic).add("Component", "Messaging")

        return topic

    def _create_backup_bucket(self, suffix: str) -> s3.Bucket:
        """
        Create S3 bucket with security and backup best practices.

        Args:
            suffix: Unique suffix for bucket name

        Returns:
            s3.Bucket: The created S3 bucket
        """
        # Create S3 bucket with security features enabled
        bucket = s3.Bucket(
            self,
            "BackupBucket",
            bucket_name=f"backup-notifications-{suffix}",
            # Security configurations
            encryption=s3.BucketEncryption.S3_MANAGED,
            versioned=True,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            # Lifecycle management for cost optimization
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="backup-lifecycle",
                    enabled=True,
                    # Transition to IA after 30 days
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
                    # Clean up incomplete multipart uploads
                    abort_incomplete_multipart_upload_after=cdk.Duration.days(7)
                )
            ],
            # Enable intelligent tiering for automatic cost optimization
            intelligent_tiering_configurations=[
                s3.IntelligentTieringConfiguration(
                    id="backup-intelligent-tiering",
                    status=s3.IntelligentTieringStatus.ENABLED,
                    optional_fields=[
                        s3.IntelligentTieringOptionalFields.BUCKET_KEY_STATUS,
                        s3.IntelligentTieringOptionalFields.STORAGE_CLASS_ANALYSIS
                    ]
                )
            ],
            # Set removal policy for development (change for production)
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True  # Required for RemovalPolicy.DESTROY
        )

        # Add tags for resource management and cost tracking
        cdk.Tags.of(bucket).add("Purpose", "BackupStorage")
        cdk.Tags.of(bucket).add("Component", "Storage")
        cdk.Tags.of(bucket).add("DataClassification", "Backup")

        return bucket

    def _configure_s3_notifications(self) -> None:
        """
        Configure S3 event notifications to send messages to SNS topic.
        
        Sets up notifications for all object creation events with proper
        IAM permissions for cross-service communication.
        """
        # Add S3 event notification for object creation
        self.backup_bucket.add_event_notification(
            s3.EventType.OBJECT_CREATED,
            s3n.SnsDestination(self.notification_topic)
        )

        # The CDK automatically creates the necessary IAM policy for S3 -> SNS
        # but we can add additional security constraints if needed
        self.notification_topic.add_to_resource_policy(
            iam.PolicyStatement(
                sid="AllowS3ToPublishFromBackupBucket",
                effect=iam.Effect.ALLOW,
                principals=[iam.ServicePrincipal("s3.amazonaws.com")],
                actions=["SNS:Publish"],
                resources=[self.notification_topic.topic_arn],
                conditions={
                    "StringEquals": {
                        "aws:SourceAccount": self.account
                    },
                    "StringLike": {
                        "aws:SourceArn": self.backup_bucket.bucket_arn
                    }
                }
            )
        )

    def _create_outputs(self) -> None:
        """
        Create CloudFormation outputs for important resource information.
        
        These outputs provide essential information for users to interact
        with the deployed resources and verify the deployment.
        """
        # S3 Bucket outputs
        CfnOutput(
            self,
            "BackupBucketName",
            value=self.backup_bucket.bucket_name,
            description="Name of the S3 bucket for backup files",
            export_name=f"{self.stack_name}-BackupBucketName"
        )

        CfnOutput(
            self,
            "BackupBucketArn",
            value=self.backup_bucket.bucket_arn,
            description="ARN of the S3 backup bucket",
            export_name=f"{self.stack_name}-BackupBucketArn"
        )

        # SNS Topic outputs
        CfnOutput(
            self,
            "NotificationTopicArn",
            value=self.notification_topic.topic_arn,
            description="ARN of the SNS topic for backup notifications",
            export_name=f"{self.stack_name}-NotificationTopicArn"
        )

        CfnOutput(
            self,
            "NotificationTopicName",
            value=self.notification_topic.topic_name,
            description="Name of the SNS topic for backup notifications",
            export_name=f"{self.stack_name}-NotificationTopicName"
        )

        # Usage instructions
        CfnOutput(
            self,
            "UploadCommand",
            value=f"aws s3 cp <file> s3://{self.backup_bucket.bucket_name}/",
            description="AWS CLI command to upload files and trigger notifications"
        )


def create_app() -> cdk.App:
    """
    Create and configure the CDK application.

    Returns:
        cdk.App: The configured CDK application
    """
    app = cdk.App()

    # Get configuration from context or environment variables
    email_address = app.node.try_get_context("email_address") or \
                   os.environ.get("EMAIL_ADDRESS", "your-email@example.com")
    
    bucket_suffix = app.node.try_get_context("bucket_suffix") or \
                   os.environ.get("BUCKET_SUFFIX")

    # Validate required parameters
    if email_address == "your-email@example.com":
        print("⚠️  Warning: Using default email address. Set EMAIL_ADDRESS environment variable or use --context email_address=your-email@example.com")

    # Create the stack
    SimpleFileBackupNotificationsStack(
        app,
        "SimpleFileBackupNotificationsStack",
        email_address=email_address,
        bucket_name_suffix=bucket_suffix,
        description="Simple File Backup Notifications with S3 and SNS",
        env=cdk.Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
        ),
        tags={
            "Project": "SimpleFileBackupNotifications",
            "Environment": "Development",
            "ManagedBy": "CDK",
            "CostCenter": "IT-Operations"
        }
    )

    return app


# Application entry point
if __name__ == "__main__":
    app = create_app()
    app.synth()