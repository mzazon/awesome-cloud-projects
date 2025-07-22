#!/usr/bin/env python3
"""
AWS CDK Python application for S3 data archiving solutions with lifecycle policies.

This application creates a comprehensive data archiving solution using S3 lifecycle policies,
intelligent tiering, monitoring, and cost optimization features.
"""

import os
from typing import Optional, Dict, Any, List

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    CfnOutput,
    Duration,
    RemovalPolicy,
    aws_s3 as s3,
    aws_iam as iam,
    aws_cloudwatch as cloudwatch,
    aws_cloudwatch_actions as cloudwatch_actions,
    aws_sns as sns,
    aws_sns_subscriptions as sns_subscriptions,
)
from constructs import Construct


class DataArchivingStack(Stack):
    """
    AWS CDK Stack for S3 data archiving solutions with lifecycle policies.
    
    This stack creates:
    - S3 bucket with versioning enabled
    - Comprehensive lifecycle policies for different data types
    - Intelligent tiering configuration
    - CloudWatch monitoring and alarms
    - S3 Analytics and Inventory configurations
    - IAM roles for automated lifecycle management
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        bucket_name: Optional[str] = None,
        notification_email: Optional[str] = None,
        **kwargs
    ) -> None:
        """
        Initialize the Data Archiving Stack.
        
        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            bucket_name: Optional custom bucket name (will be auto-generated if not provided)
            notification_email: Email address for CloudWatch alarm notifications
            **kwargs: Additional keyword arguments passed to Stack
        """
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique bucket name if not provided
        if bucket_name is None:
            bucket_name = f"data-archiving-demo-{self.account}-{self.region}"

        self.bucket_name = bucket_name
        self.notification_email = notification_email

        # Create the main S3 bucket
        self.bucket = self._create_s3_bucket()
        
        # Configure lifecycle policies
        self._configure_lifecycle_policies()
        
        # Configure intelligent tiering
        self._configure_intelligent_tiering()
        
        # Set up monitoring and analytics
        self._setup_monitoring()
        
        # Create IAM role for lifecycle management
        self.lifecycle_role = self._create_lifecycle_role()
        
        # Create outputs
        self._create_outputs()

    def _create_s3_bucket(self) -> s3.Bucket:
        """
        Create the main S3 bucket with versioning and security features enabled.
        
        Returns:
            The created S3 bucket
        """
        bucket = s3.Bucket(
            self,
            "DataArchivingBucket",
            bucket_name=self.bucket_name,
            versioned=True,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            encryption=s3.BucketEncryption.S3_MANAGED,
            enforce_ssl=True,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,  # For demo purposes only
            lifecycle_rules=[],  # Will be configured separately for better control
        )

        # Add bucket notification for object creation events
        # This can be used for triggering additional workflows
        bucket.add_event_notification(
            s3.EventType.OBJECT_CREATED,
            # Add notification destinations as needed
        )

        return bucket

    def _configure_lifecycle_policies(self) -> None:
        """
        Configure comprehensive lifecycle policies for different data types.
        
        This method sets up different lifecycle rules for:
        - Documents: 30 days to IA, 90 days to Glacier, 365 days to Deep Archive
        - Logs: 7 days to IA, 30 days to Glacier, 90 days to Deep Archive, 7 years expiration
        - Backups: 1 day to IA, 30 days to Glacier
        - Media: Immediate intelligent tiering
        """
        # Document archiving lifecycle rule
        document_rule = s3.LifecycleRule(
            id="DocumentArchiving",
            enabled=True,
            prefix="documents/",
            transitions=[
                s3.Transition(
                    storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                    transition_after=Duration.days(30),
                ),
                s3.Transition(
                    storage_class=s3.StorageClass.GLACIER,
                    transition_after=Duration.days(90),
                ),
                s3.Transition(
                    storage_class=s3.StorageClass.DEEP_ARCHIVE,
                    transition_after=Duration.days(365),
                ),
            ],
        )

        # Log archiving lifecycle rule with expiration
        log_rule = s3.LifecycleRule(
            id="LogArchiving",
            enabled=True,
            prefix="logs/",
            transitions=[
                s3.Transition(
                    storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                    transition_after=Duration.days(7),
                ),
                s3.Transition(
                    storage_class=s3.StorageClass.GLACIER,
                    transition_after=Duration.days(30),
                ),
                s3.Transition(
                    storage_class=s3.StorageClass.DEEP_ARCHIVE,
                    transition_after=Duration.days(90),
                ),
            ],
            expiration=Duration.days(2555),  # 7 years
        )

        # Backup archiving lifecycle rule
        backup_rule = s3.LifecycleRule(
            id="BackupArchiving",
            enabled=True,
            prefix="backups/",
            transitions=[
                s3.Transition(
                    storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                    transition_after=Duration.days(1),
                ),
                s3.Transition(
                    storage_class=s3.StorageClass.GLACIER,
                    transition_after=Duration.days(30),
                ),
            ],
        )

        # Media intelligent tiering lifecycle rule
        media_rule = s3.LifecycleRule(
            id="MediaIntelligentTiering",
            enabled=True,
            prefix="media/",
            transitions=[
                s3.Transition(
                    storage_class=s3.StorageClass.INTELLIGENT_TIERING,
                    transition_after=Duration.days(0),
                ),
            ],
        )

        # Add lifecycle rules to bucket
        for rule in [document_rule, log_rule, backup_rule, media_rule]:
            self.bucket.add_lifecycle_rule(**rule.__dict__)

    def _configure_intelligent_tiering(self) -> None:
        """
        Configure S3 Intelligent Tiering for automatic cost optimization.
        
        This configuration enables Archive Access and Deep Archive Access tiers
        for media files that are rarely accessed.
        """
        # Create intelligent tiering configuration
        intelligent_tiering_config = s3.CfnBucket.IntelligentTieringConfigurationProperty(
            id="MediaIntelligentTieringConfig",
            status="Enabled",
            prefix="media/",
            tierings=[
                s3.CfnBucket.TieringProperty(
                    access_tier="ARCHIVE_ACCESS",
                    days=90,
                ),
                s3.CfnBucket.TieringProperty(
                    access_tier="DEEP_ARCHIVE_ACCESS",
                    days=180,
                ),
            ],
        )

        # Access the underlying CfnBucket to add intelligent tiering
        cfn_bucket = self.bucket.node.default_child
        if hasattr(cfn_bucket, 'intelligent_tiering_configurations'):
            if cfn_bucket.intelligent_tiering_configurations is None:
                cfn_bucket.intelligent_tiering_configurations = []
            cfn_bucket.intelligent_tiering_configurations.append(intelligent_tiering_config)
        else:
            cfn_bucket.add_property_override(
                "IntelligentTieringConfigurations",
                [intelligent_tiering_config]
            )

    def _setup_monitoring(self) -> None:
        """
        Set up CloudWatch monitoring, S3 Analytics, and S3 Inventory for cost tracking.
        """
        # Create SNS topic for notifications if email is provided
        if self.notification_email:
            self.notification_topic = sns.Topic(
                self,
                "StorageNotificationTopic",
                display_name="S3 Storage Monitoring Alerts",
            )
            
            self.notification_topic.add_subscription(
                sns_subscriptions.EmailSubscription(self.notification_email)
            )
        else:
            self.notification_topic = None

        # Create CloudWatch alarm for bucket size
        bucket_size_alarm = cloudwatch.Alarm(
            self,
            "BucketSizeAlarm",
            alarm_name=f"S3-BucketSize-{self.bucket_name}",
            alarm_description="Monitor S3 bucket size in bytes",
            metric=cloudwatch.Metric(
                namespace="AWS/S3",
                metric_name="BucketSizeBytes",
                dimensions_map={
                    "BucketName": self.bucket_name,
                    "StorageType": "StandardStorage",
                },
                statistic="Average",
                period=Duration.days(1),
            ),
            threshold=1000000000,  # 1GB threshold
            evaluation_periods=1,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

        # Create CloudWatch alarm for object count
        object_count_alarm = cloudwatch.Alarm(
            self,
            "ObjectCountAlarm",
            alarm_name=f"S3-ObjectCount-{self.bucket_name}",
            alarm_description="Monitor S3 object count",
            metric=cloudwatch.Metric(
                namespace="AWS/S3",
                metric_name="NumberOfObjects",
                dimensions_map={
                    "BucketName": self.bucket_name,
                    "StorageType": "AllStorageTypes",
                },
                statistic="Average",
                period=Duration.days(1),
            ),
            threshold=1000,
            evaluation_periods=1,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

        # Add SNS actions to alarms if topic exists
        if self.notification_topic:
            bucket_size_alarm.add_alarm_action(
                cloudwatch_actions.SnsAction(self.notification_topic)
            )
            object_count_alarm.add_alarm_action(
                cloudwatch_actions.SnsAction(self.notification_topic)
            )

        # Configure S3 Analytics for documents
        analytics_config = s3.CfnBucket.AnalyticsConfigurationProperty(
            id="DocumentAnalytics",
            prefix="documents/",
            storage_class_analysis=s3.CfnBucket.StorageClassAnalysisProperty(
                data_export=s3.CfnBucket.DataExportProperty(
                    output_schema_version="V_1",
                    destination=s3.CfnBucket.DestinationProperty(
                        bucket_arn=self.bucket.bucket_arn,
                        prefix="analytics-reports/documents/",
                        format="CSV",
                    ),
                ),
            ),
        )

        # Configure S3 Inventory for storage tracking
        inventory_config = s3.CfnBucket.InventoryConfigurationProperty(
            id="StorageInventoryConfig",
            enabled=True,
            destination=s3.CfnBucket.DestinationProperty(
                bucket_arn=self.bucket.bucket_arn,
                prefix="inventory-reports/",
                format="CSV",
            ),
            schedule=s3.CfnBucket.ScheduleProperty(frequency="Daily"),
            included_object_versions="Current",
            optional_fields=[
                "Size",
                "LastModifiedDate",
                "StorageClass",
                "IntelligentTieringAccessTier",
            ],
        )

        # Add configurations to bucket
        cfn_bucket = self.bucket.node.default_child
        
        # Add analytics configuration
        if hasattr(cfn_bucket, 'analytics_configurations'):
            if cfn_bucket.analytics_configurations is None:
                cfn_bucket.analytics_configurations = []
            cfn_bucket.analytics_configurations.append(analytics_config)
        else:
            cfn_bucket.add_property_override(
                "AnalyticsConfigurations",
                [analytics_config]
            )

        # Add inventory configuration
        if hasattr(cfn_bucket, 'inventory_configurations'):
            if cfn_bucket.inventory_configurations is None:
                cfn_bucket.inventory_configurations = []
            cfn_bucket.inventory_configurations.append(inventory_config)
        else:
            cfn_bucket.add_property_override(
                "InventoryConfigurations",
                [inventory_config]
            )

    def _create_lifecycle_role(self) -> iam.Role:
        """
        Create IAM role for automated lifecycle management operations.
        
        Returns:
            The created IAM role with appropriate permissions
        """
        # Create trust policy for S3 service
        trust_policy = iam.PolicyDocument(
            statements=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    principals=[iam.ServicePrincipal("s3.amazonaws.com")],
                    actions=["sts:AssumeRole"],
                ),
            ]
        )

        # Create the IAM role
        role = iam.Role(
            self,
            "LifecycleManagementRole",
            role_name=f"S3LifecycleRole-{self.region}",
            assumed_by=iam.ServicePrincipal("s3.amazonaws.com"),
            description="Role for S3 lifecycle management operations",
            inline_policies={
                "LifecycleManagementPolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:GetBucketLocation",
                                "s3:GetBucketLifecycleConfiguration",
                                "s3:PutBucketLifecycleConfiguration",
                                "s3:GetBucketVersioning",
                                "s3:GetBucketIntelligentTieringConfiguration",
                                "s3:PutBucketIntelligentTieringConfiguration",
                            ],
                            resources=["*"],
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:GetObject",
                                "s3:GetObjectVersion",
                                "s3:ListBucket",
                            ],
                            resources=[
                                "arn:aws:s3:::*",
                                "arn:aws:s3:::*/*",
                            ],
                        ),
                    ]
                )
            },
        )

        return role

    def _create_outputs(self) -> None:
        """
        Create CloudFormation outputs for important resource information.
        """
        CfnOutput(
            self,
            "BucketName",
            value=self.bucket.bucket_name,
            description="Name of the S3 bucket for data archiving",
            export_name=f"{self.stack_name}-BucketName",
        )

        CfnOutput(
            self,
            "BucketArn",
            value=self.bucket.bucket_arn,
            description="ARN of the S3 bucket for data archiving",
            export_name=f"{self.stack_name}-BucketArn",
        )

        CfnOutput(
            self,
            "BucketDomainName",
            value=self.bucket.bucket_domain_name,
            description="Domain name of the S3 bucket",
            export_name=f"{self.stack_name}-BucketDomainName",
        )

        CfnOutput(
            self,
            "LifecycleRoleArn",
            value=self.lifecycle_role.role_arn,
            description="ARN of the IAM role for lifecycle management",
            export_name=f"{self.stack_name}-LifecycleRoleArn",
        )

        if self.notification_topic:
            CfnOutput(
                self,
                "NotificationTopicArn",
                value=self.notification_topic.topic_arn,
                description="ARN of the SNS topic for storage monitoring alerts",
                export_name=f"{self.stack_name}-NotificationTopicArn",
            )


class DataArchivingApp(cdk.App):
    """
    CDK Application for S3 Data Archiving Solutions.
    """

    def __init__(self) -> None:
        """
        Initialize the CDK application with environment configuration.
        """
        super().__init__()

        # Get configuration from environment variables or context
        bucket_name = self.node.try_get_context("bucketName")
        notification_email = self.node.try_get_context("notificationEmail")
        
        # Override with environment variables if set
        bucket_name = os.environ.get("BUCKET_NAME", bucket_name)
        notification_email = os.environ.get("NOTIFICATION_EMAIL", notification_email)

        # Create the main stack
        DataArchivingStack(
            self,
            "DataArchivingStack",
            bucket_name=bucket_name,
            notification_email=notification_email,
            description="S3 data archiving solution with lifecycle policies, intelligent tiering, and monitoring",
            env=cdk.Environment(
                account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
                region=os.environ.get("CDK_DEFAULT_REGION"),
            ),
        )


# Create and run the application
app = DataArchivingApp()
app.synth()