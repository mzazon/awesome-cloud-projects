#!/usr/bin/env python3
"""
CDK Python application for Automated Data Archiving with S3 Glacier

This application creates the infrastructure for implementing automated data archiving
using Amazon S3 Lifecycle policies and S3 Glacier storage classes.

Author: AWS CDK Team
Version: 1.0.0
"""

import os
from typing import Dict, Any, Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    CfnOutput,
    Duration,
    RemovalPolicy,
    aws_s3 as s3,
    aws_sns as sns,
    aws_sns_subscriptions as subscriptions,
    aws_iam as iam,
)
from constructs import Construct


class AutomatedDataArchivingStack(Stack):
    """
    CDK Stack for Automated Data Archiving with S3 Glacier.
    
    This stack creates:
    - S3 bucket with lifecycle policies for automated archiving
    - SNS topic for notifications
    - Proper IAM permissions for S3 event notifications
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique bucket name using account ID
        account_id = self.account
        bucket_name = f"awscookbook-archive-{account_id[:8]}"

        # Create S3 bucket for data archiving
        self.archive_bucket = s3.Bucket(
            self, "ArchiveBucket",
            bucket_name=bucket_name,
            versioning=s3.BucketVersioning.ENABLED,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,  # For demo purposes only
            lifecycle_rules=[
                # Lifecycle rule for automated archiving
                s3.LifecycleRule(
                    id="ArchiveRule",
                    enabled=True,
                    prefix="data/",
                    transitions=[
                        # Transition to S3 Glacier Flexible Retrieval after 90 days
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(90)
                        ),
                        # Transition to S3 Glacier Deep Archive after 365 days
                        s3.Transition(
                            storage_class=s3.StorageClass.DEEP_ARCHIVE,
                            transition_after=Duration.days(365)
                        )
                    ]
                )
            ]
        )

        # Create SNS topic for archive notifications
        self.notification_topic = sns.Topic(
            self, "ArchiveNotificationTopic",
            topic_name="archive-notification",
            display_name="S3 Archive Notifications"
        )

        # Create IAM service principal for S3 to publish to SNS
        s3_service_principal = iam.ServicePrincipal("s3.amazonaws.com")
        
        # Grant S3 permission to publish to SNS topic
        self.notification_topic.add_to_resource_policy(
            iam.PolicyStatement(
                sid="AllowS3Publish",
                effect=iam.Effect.ALLOW,
                principals=[s3_service_principal],
                actions=["SNS:Publish"],
                resources=[self.notification_topic.topic_arn],
                conditions={
                    "StringEquals": {
                        "aws:SourceAccount": self.account
                    },
                    "ArnEquals": {
                        "aws:SourceArn": self.archive_bucket.bucket_arn
                    }
                }
            )
        )

        # Configure S3 event notifications
        self.archive_bucket.add_event_notification(
            s3.EventType.OBJECT_RESTORE_COMPLETED,
            s3.SnsDestination(self.notification_topic),
            s3.NotificationKeyFilter(prefix="data/")
        )

        # Create sample data for demonstration (optional)
        self._create_sample_data()

        # Create outputs
        self._create_outputs()

    def _create_sample_data(self) -> None:
        """Create sample data deployment (for demonstration purposes)."""
        # Note: In a real-world scenario, you might use a Lambda function
        # or other mechanism to upload sample data after bucket creation
        pass

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information."""
        CfnOutput(
            self, "BucketName",
            value=self.archive_bucket.bucket_name,
            description="Name of the S3 bucket for data archiving"
        )

        CfnOutput(
            self, "BucketArn",
            value=self.archive_bucket.bucket_arn,
            description="ARN of the S3 bucket for data archiving"
        )

        CfnOutput(
            self, "NotificationTopicArn",
            value=self.notification_topic.topic_arn,
            description="ARN of the SNS topic for archive notifications"
        )

        CfnOutput(
            self, "BucketDomainName",
            value=self.archive_bucket.bucket_domain_name,
            description="Domain name of the S3 bucket"
        )

        CfnOutput(
            self, "SampleUploadCommand",
            value=f"aws s3 cp sample-file.txt s3://{self.archive_bucket.bucket_name}/data/",
            description="Sample command to upload data to the archiving bucket"
        )

    def add_email_subscription(self, email: str) -> None:
        """
        Add an email subscription to the SNS topic.
        
        Args:
            email: Email address to subscribe to notifications
        """
        self.notification_topic.add_subscription(
            subscriptions.EmailSubscription(email)
        )


class AutomatedDataArchivingApp(cdk.App):
    """Main CDK Application for Automated Data Archiving."""

    def __init__(self, **kwargs) -> None:
        super().__init__(**kwargs)

        # Get environment configuration
        env = self._get_environment()

        # Create the main stack
        stack = AutomatedDataArchivingStack(
            self, "AutomatedDataArchivingStack",
            env=env,
            description="CDK Stack for Automated Data Archiving with S3 Glacier"
        )

        # Add email subscription if provided
        email = self.node.try_get_context("notification_email")
        if email:
            stack.add_email_subscription(email)

        # Add tags to all resources
        self._add_tags()

    def _get_environment(self) -> Environment:
        """Get the deployment environment configuration."""
        return Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
        )

    def _add_tags(self) -> None:
        """Add common tags to all resources in the application."""
        cdk.Tags.of(self).add("Project", "AutomatedDataArchiving")
        cdk.Tags.of(self).add("Environment", "Development")
        cdk.Tags.of(self).add("Owner", "CloudOps")
        cdk.Tags.of(self).add("Recipe", "automated-data-archiving-with-s3-glacier")
        cdk.Tags.of(self).add("CostCenter", "IT")


def main() -> None:
    """Main entry point for the CDK application."""
    app = AutomatedDataArchivingApp()
    app.synth()


if __name__ == "__main__":
    main()