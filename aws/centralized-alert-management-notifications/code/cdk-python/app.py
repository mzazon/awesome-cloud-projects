#!/usr/bin/env python3
"""
Centralized Alert Management with User Notifications and CloudWatch
AWS CDK Python implementation

This CDK application creates:
- S3 bucket with CloudWatch metrics enabled
- CloudWatch alarm for bucket size monitoring
- User Notifications hub and configuration
- Email contact for notification delivery
"""

import os
from typing import Optional

from aws_cdk import (
    App,
    Stack,
    StackProps,
    Environment,
    CfnOutput,
    Duration,
    RemovalPolicy,
)
from aws_cdk import aws_s3 as s3
from aws_cdk import aws_cloudwatch as cloudwatch
from aws_cdk import aws_notifications as notifications
from aws_cdk import aws_notificationscontacts as notificationscontacts
from constructs import Construct

class CentralizedAlertManagementStack(Stack):
    """
    CDK Stack for Centralized Alert Management with User Notifications
    
    Creates a complete monitoring and notification solution using:
    - S3 bucket with metrics enabled
    - CloudWatch alarms for storage monitoring
    - User Notifications for centralized alert management
    - Email contacts for notification delivery
    """
    
    def __init__(
        self, 
        scope: Construct, 
        construct_id: str, 
        email_address: str,
        **kwargs
    ) -> None:
        """
        Initialize the Centralized Alert Management Stack
        
        Args:
            scope: The CDK scope for this stack
            construct_id: Unique identifier for this stack
            email_address: Email address for notifications
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)
        
        # Generate unique suffix for resource names
        import random
        import string
        random_suffix = ''.join(random.choices(string.ascii_lowercase + string.digits, k=6))
        
        # Create S3 bucket with CloudWatch metrics enabled
        self.monitoring_bucket = s3.Bucket(
            self,
            "MonitoringBucket",
            bucket_name=f"monitoring-demo-{random_suffix}",
            versioned=True,
            # Enable server access logging for better observability
            server_access_logs_prefix="access-logs/",
            # Configure intelligent tiering for cost optimization
            intelligent_tiering_configurations=[
                s3.IntelligentTieringConfiguration(
                    name="EntireBucket",
                    prefix="",
                    archive_access_tier_time=Duration.days(90),
                    deep_archive_access_tier_time=Duration.days(180)
                )
            ],
            # Enable metrics configuration for CloudWatch integration
            metrics_configurations=[
                s3.BucketMetrics(
                    id="EntireBucket",
                    prefix=""
                )
            ],
            # Configure lifecycle rules for demonstration
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DemoLifecycleRule",
                    enabled=True,
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30)
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(90)
                        )
                    ]
                )
            ],
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True
        )
        
        # Create CloudWatch alarm for bucket size monitoring
        self.bucket_size_alarm = cloudwatch.Alarm(
            self,
            "S3BucketSizeAlarm",
            alarm_name=f"s3-bucket-size-alarm-{random_suffix}",
            alarm_description="Monitor S3 bucket size growth for capacity planning",
            metric=cloudwatch.Metric(
                namespace="AWS/S3",
                metric_name="BucketSizeBytes",
                dimensions_map={
                    "BucketName": self.monitoring_bucket.bucket_name,
                    "StorageType": "StandardStorage"
                },
                statistic="Average",
                period=Duration.days(1)
            ),
            threshold=5000000,  # 5MB threshold for demonstration
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=1,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        
        # Create User Notifications hub
        # Note: CDK L2 constructs for User Notifications may not be available yet
        # Using L1 constructs (CfnXxx) for lower-level access
        self.notification_hub = notifications.CfnNotificationHub(
            self,
            "NotificationHub",
            notification_hub_region=self.region
        )
        
        # Create email contact for notifications
        self.email_contact = notificationscontacts.CfnEmailContact(
            self,
            "EmailContact",
            name="monitoring-alerts-contact",
            email_address=email_address
        )
        
        # Create event rule for CloudWatch alarm state changes
        self.event_rule = notifications.CfnEventRule(
            self,
            "AlarmEventRule",
            name=f"s3-monitoring-event-rule-{random_suffix}",
            description="Filter CloudWatch alarm state changes for S3 monitoring",
            event_pattern={
                "source": ["aws.cloudwatch"],
                "detail-type": ["CloudWatch Alarm State Change"],
                "detail": {
                    "alarmName": [self.bucket_size_alarm.alarm_name],
                    "state": {
                        "value": ["ALARM", "OK"]
                    }
                }
            }
        )
        
        # Create notification configuration
        self.notification_configuration = notifications.CfnNotificationConfiguration(
            self,
            "NotificationConfiguration",
            name=f"s3-monitoring-config-{random_suffix}",
            description="S3 monitoring notification configuration with centralized management",
            aggregation_duration="PT5M"  # 5-minute aggregation window
        )
        
        # Associate email contact with notification configuration
        # This creates the connection between the configuration and delivery channel
        notifications.CfnAssociatedChannel(
            self,
            "EmailChannelAssociation",
            arn=self.email_contact.attr_arn,
            notification_configuration_arn=self.notification_configuration.attr_arn
        )
        
        # Create CloudWatch dashboard for monitoring
        self.monitoring_dashboard = cloudwatch.Dashboard(
            self,
            "MonitoringDashboard",
            dashboard_name=f"S3-Monitoring-Dashboard-{random_suffix}",
            widgets=[
                [
                    cloudwatch.GraphWidget(
                        title="S3 Bucket Size Over Time",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/S3",
                                metric_name="BucketSizeBytes",
                                dimensions_map={
                                    "BucketName": self.monitoring_bucket.bucket_name,
                                    "StorageType": "StandardStorage"
                                },
                                statistic="Average",
                                period=Duration.days(1)
                            )
                        ],
                        width=12,
                        height=6
                    )
                ],
                [
                    cloudwatch.SingleValueWidget(
                        title="Current Bucket Size",
                        metrics=[
                            cloudwatch.Metric(
                                namespace="AWS/S3",
                                metric_name="BucketSizeBytes",
                                dimensions_map={
                                    "BucketName": self.monitoring_bucket.bucket_name,
                                    "StorageType": "StandardStorage"
                                },
                                statistic="Average",
                                period=Duration.days(1)
                            )
                        ],
                        width=6,
                        height=4
                    ),
                    cloudwatch.SingleValueWidget(
                        title="Object Count",
                        metrics=[
                            cloudwatch.Metric(
                                namespace="AWS/S3",
                                metric_name="NumberOfObjects",
                                dimensions_map={
                                    "BucketName": self.monitoring_bucket.bucket_name,
                                    "StorageType": "AllStorageTypes"
                                },
                                statistic="Average",
                                period=Duration.days(1)
                            )
                        ],
                        width=6,
                        height=4
                    )
                ]
            ]
        )
        
        # Stack outputs for reference and testing
        CfnOutput(
            self,
            "BucketName",
            value=self.monitoring_bucket.bucket_name,
            description="Name of the S3 bucket being monitored",
            export_name=f"{self.stack_name}-BucketName"
        )
        
        CfnOutput(
            self,
            "AlarmName",
            value=self.bucket_size_alarm.alarm_name,
            description="Name of the CloudWatch alarm monitoring bucket size",
            export_name=f"{self.stack_name}-AlarmName"
        )
        
        CfnOutput(
            self,
            "EmailContactArn",
            value=self.email_contact.attr_arn,
            description="ARN of the email contact for notifications",
            export_name=f"{self.stack_name}-EmailContactArn"
        )
        
        CfnOutput(
            self,
            "NotificationConfigurationArn",
            value=self.notification_configuration.attr_arn,
            description="ARN of the notification configuration",
            export_name=f"{self.stack_name}-NotificationConfigurationArn"
        )
        
        CfnOutput(
            self,
            "DashboardUrl",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.monitoring_dashboard.dashboard_name}",
            description="URL to the CloudWatch monitoring dashboard",
            export_name=f"{self.stack_name}-DashboardUrl"
        )
        
        CfnOutput(
            self,
            "NotificationsCenterUrl",
            value=f"https://{self.region}.console.aws.amazon.com/notifications/home?region={self.region}",
            description="URL to the AWS User Notifications Console",
            export_name=f"{self.stack_name}-NotificationsCenterUrl"
        )


def main() -> None:
    """
    Main entry point for the CDK application
    
    Creates the CDK app and deploys the centralized alert management stack
    """
    app = App()
    
    # Get email address from context or environment variable
    email_address = app.node.try_get_context("email_address") or os.environ.get("NOTIFICATION_EMAIL")
    
    if not email_address:
        raise ValueError(
            "Email address is required. Set via context (-c email_address=your@email.com) "
            "or environment variable NOTIFICATION_EMAIL"
        )
    
    # Get AWS account and region from environment or use defaults
    account = os.environ.get("CDK_DEFAULT_ACCOUNT")
    region = os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
    
    # Create the stack with proper environment configuration
    CentralizedAlertManagementStack(
        app,
        "CentralizedAlertManagementStack",
        email_address=email_address,
        env=Environment(
            account=account,
            region=region
        ),
        description="Centralized Alert Management with User Notifications and CloudWatch monitoring"
    )
    
    # Synthesize the CloudFormation template
    app.synth()


if __name__ == "__main__":
    main()