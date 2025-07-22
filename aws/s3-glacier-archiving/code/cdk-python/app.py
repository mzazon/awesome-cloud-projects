#!/usr/bin/env python3
"""
CDK Application for Long-term Data Archiving with S3 Glacier Deep Archive

This application creates a comprehensive long-term data archiving solution using
Amazon S3 and S3 Glacier Deep Archive with automated lifecycle policies,
event notifications, and inventory reporting.
"""

import aws_cdk as cdk
from aws_cdk import (
    aws_s3 as s3,
    aws_sns as sns,
    aws_iam as iam,
    aws_s3_notifications as s3n,
    Stack,
    App,
    CfnOutput,
    Duration,
    RemovalPolicy,
)
from constructs import Construct
from typing import Dict, List, Optional


class LongTermArchivingStack(Stack):
    """
    Stack for S3 Glacier Deep Archive for Long-term Storage.
    
    This stack creates:
    - S3 bucket with versioning and encryption
    - Lifecycle policies for automatic archiving
    - SNS topic for archive notifications
    - S3 inventory configuration for tracking
    - Proper IAM permissions and security settings
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        bucket_name_suffix: Optional[str] = None,
        notification_email: Optional[str] = None,
        **kwargs
    ) -> None:
        """
        Initialize the Long Term Archiving Stack.
        
        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            bucket_name_suffix: Optional suffix for bucket name uniqueness
            notification_email: Email address for archive notifications
            **kwargs: Additional keyword arguments
        """
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix if not provided
        if not bucket_name_suffix:
            bucket_name_suffix = self.node.addr[-8:].lower()

        # Create the main archival S3 bucket
        self.archive_bucket = self._create_archive_bucket(bucket_name_suffix)
        
        # Create SNS topic for notifications
        self.notification_topic = self._create_notification_topic()
        
        # Configure lifecycle policies
        self._configure_lifecycle_policies()
        
        # Set up event notifications
        self._configure_event_notifications()
        
        # Enable S3 inventory reporting
        self._configure_inventory_reporting()
        
        # Create outputs
        self._create_outputs(notification_email)

    def _create_archive_bucket(self, suffix: str) -> s3.Bucket:
        """
        Create the main S3 bucket for long-term archiving.
        
        Args:
            suffix: Unique suffix for bucket name
            
        Returns:
            The created S3 bucket
        """
        bucket = s3.Bucket(
            self,
            "ArchiveBucket",
            bucket_name=f"long-term-archive-{suffix}",
            # Enable versioning for data protection
            versioned=True,
            # Enable default encryption
            encryption=s3.BucketEncryption.S3_MANAGED,
            # Block all public access for security
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            # Enable event bridge notifications
            event_bridge_enabled=True,
            # Enforce SSL requests only
            enforce_ssl=True,
            # Lifecycle configuration will be added separately
            lifecycle_rules=[],
            # Remove bucket on stack deletion (for development)
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        # Add bucket policy to enforce encryption in transit
        bucket.add_to_resource_policy(
            iam.PolicyStatement(
                sid="DenyInsecureConnections",
                effect=iam.Effect.DENY,
                principals=[iam.AnyPrincipal()],
                actions=["s3:*"],
                resources=[bucket.bucket_arn, bucket.arn_for_objects("*")],
                conditions={
                    "Bool": {
                        "aws:SecureTransport": "false"
                    }
                }
            )
        )

        return bucket

    def _create_notification_topic(self) -> sns.Topic:
        """
        Create SNS topic for archive event notifications.
        
        Returns:
            The created SNS topic
        """
        topic = sns.Topic(
            self,
            "ArchiveNotificationTopic",
            topic_name="s3-archive-notifications",
            display_name="S3 Archive Notifications",
            # Enable encryption for sensitive notifications
            master_key=None,  # Use default AWS managed key
        )

        return topic

    def _configure_lifecycle_policies(self) -> None:
        """Configure S3 lifecycle policies for automated archiving."""
        
        # Policy 1: Move archive folder contents to Deep Archive after 90 days
        self.archive_bucket.add_lifecycle_rule(
            id="ArchiveFolderToDeepArchive90Days",
            enabled=True,
            prefix="archives/",
            transitions=[
                s3.Transition(
                    storage_class=s3.StorageClass.DEEP_ARCHIVE,
                    transition_after=Duration.days(90)
                )
            ]
        )

        # Policy 2: Move all other files to Deep Archive after 180 days
        self.archive_bucket.add_lifecycle_rule(
            id="AllFilesToDeepArchive180Days",
            enabled=True,
            # No prefix means applies to all objects
            transitions=[
                s3.Transition(
                    storage_class=s3.StorageClass.DEEP_ARCHIVE,
                    transition_after=Duration.days(180)
                )
            ]
        )

        # Policy 3: Clean up incomplete multipart uploads after 7 days
        self.archive_bucket.add_lifecycle_rule(
            id="CleanupIncompleteMultipartUploads",
            enabled=True,
            abort_incomplete_multipart_upload_after=Duration.days(7)
        )

        # Policy 4: Delete non-current versions after 1 year (cost optimization)
        self.archive_bucket.add_lifecycle_rule(
            id="DeleteOldVersions",
            enabled=True,
            noncurrent_version_expiration=Duration.days(365)
        )

    def _configure_event_notifications(self) -> None:
        """Configure S3 event notifications for archive monitoring."""
        
        # Add notification for lifecycle transitions to the SNS topic
        # Filter for PDF files as an example of document-centric archiving
        self.archive_bucket.add_event_notification(
            s3.EventType.OBJECT_TRANSITION_TO_DEEP_ARCHIVE,
            s3n.SnsDestination(self.notification_topic),
            s3.NotificationKeyFilter(suffix=".pdf")
        )

        # Also notify on restore operations for monitoring
        self.archive_bucket.add_event_notification(
            s3.EventType.OBJECT_RESTORE_INITIATED,
            s3n.SnsDestination(self.notification_topic)
        )

        self.archive_bucket.add_event_notification(
            s3.EventType.OBJECT_RESTORE_COMPLETED,
            s3n.SnsDestination(self.notification_topic)
        )

    def _configure_inventory_reporting(self) -> None:
        """Configure S3 inventory for comprehensive archive tracking."""
        
        # Create inventory configuration for weekly reports
        inventory_config = s3.CfnBucket.InventoryConfigurationProperty(
            destination=s3.CfnBucket.DestinationProperty(
                bucket_arn=self.archive_bucket.bucket_arn,
                format="CSV",
                prefix="inventory-reports"
            ),
            enabled=True,
            id="WeeklyInventory",
            included_object_versions="Current",
            schedule_frequency="Weekly",
            optional_fields=[
                "Size",
                "LastModifiedDate",
                "StorageClass",
                "ETag",
                "ReplicationStatus",
                "EncryptionStatus"
            ]
        )

        # Add inventory configuration to the bucket
        cfn_bucket = self.archive_bucket.node.default_child
        cfn_bucket.add_property_override(
            "InventoryConfigurations",
            [inventory_config]
        )

    def _create_outputs(self, notification_email: Optional[str]) -> None:
        """
        Create CloudFormation outputs for key resources.
        
        Args:
            notification_email: Email address for notifications
        """
        CfnOutput(
            self,
            "ArchiveBucketName",
            value=self.archive_bucket.bucket_name,
            description="Name of the S3 bucket for long-term archiving",
            export_name=f"{self.stack_name}-ArchiveBucketName"
        )

        CfnOutput(
            self,
            "ArchiveBucketArn",
            value=self.archive_bucket.bucket_arn,
            description="ARN of the S3 bucket for long-term archiving",
            export_name=f"{self.stack_name}-ArchiveBucketArn"
        )

        CfnOutput(
            self,
            "NotificationTopicArn",
            value=self.notification_topic.topic_arn,
            description="ARN of the SNS topic for archive notifications",
            export_name=f"{self.stack_name}-NotificationTopicArn"
        )

        if notification_email:
            CfnOutput(
                self,
                "SubscriptionCommand",
                value=f"aws sns subscribe --topic-arn {self.notification_topic.topic_arn} --protocol email --notification-endpoint {notification_email}",
                description="Command to subscribe email to notifications"
            )

        # Output for testing the archive system
        CfnOutput(
            self,
            "TestCommands",
            value=f"""
# Upload test file to archives folder (90-day transition):
aws s3 cp test-file.pdf s3://{self.archive_bucket.bucket_name}/archives/

# Upload test file to root (180-day transition):
aws s3 cp test-file.pdf s3://{self.archive_bucket.bucket_name}/

# Check lifecycle configuration:
aws s3api get-bucket-lifecycle-configuration --bucket {self.archive_bucket.bucket_name}
            """.strip(),
            description="Commands to test the archiving system"
        )


def main() -> None:
    """Main application entry point."""
    app = App()

    # Get context parameters
    bucket_suffix = app.node.try_get_context("bucketSuffix")
    notification_email = app.node.try_get_context("notificationEmail")
    environment = app.node.try_get_context("environment") or "dev"

    # Create the stack
    LongTermArchivingStack(
        app,
        f"LongTermArchivingStack-{environment}",
        bucket_name_suffix=bucket_suffix,
        notification_email=notification_email,
        env=cdk.Environment(
            account=app.node.try_get_context("account"),
            region=app.node.try_get_context("region")
        ),
        description="Long-term data archiving solution using S3 Glacier Deep Archive"
    )

    app.synth()


if __name__ == "__main__":
    main()