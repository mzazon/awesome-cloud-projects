#!/usr/bin/env python3
"""
CDK Python Application for S3 Intelligent Tiering and Lifecycle Management

This application creates a complete S3 storage optimization solution with:
- S3 bucket with intelligent tiering configuration
- Lifecycle policies for cost optimization
- CloudWatch monitoring and dashboards
- IAM roles and policies for secure access

Author: AWS CDK Generator
Version: 1.0
"""

import os
from typing import Dict, Any, List

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_s3 as s3,
    aws_iam as iam,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
)
from constructs import Construct


class S3IntelligentTieringStack(Stack):
    """
    CDK Stack for S3 Intelligent Tiering and Lifecycle Management
    
    This stack creates:
    - S3 bucket with intelligent tiering
    - Lifecycle policies for cost optimization
    - CloudWatch dashboard for monitoring
    - IAM roles for secure access
    """

    def __init__(
        self, 
        scope: Construct, 
        construct_id: str, 
        bucket_name_prefix: str = "intelligent-tiering-demo",
        enable_versioning: bool = True,
        enable_access_logging: bool = True,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique bucket name
        self.bucket_name = f"{bucket_name_prefix}-{cdk.Aws.ACCOUNT_ID}-{cdk.Aws.REGION}"

        # Create the main S3 bucket with intelligent tiering
        self.bucket = self._create_main_bucket(enable_versioning)
        
        # Create access logging bucket if enabled
        if enable_access_logging:
            self.access_log_bucket = self._create_access_log_bucket()
            self._configure_access_logging()
        
        # Configure intelligent tiering
        self._configure_intelligent_tiering()
        
        # Configure lifecycle policies
        self._configure_lifecycle_policies()
        
        # Create CloudWatch dashboard
        self._create_cloudwatch_dashboard()
        
        # Create IAM roles and policies
        self._create_iam_resources()
        
        # Create stack outputs
        self._create_outputs()

    def _create_main_bucket(self, enable_versioning: bool) -> s3.Bucket:
        """
        Create the main S3 bucket with intelligent tiering and optimization settings.
        
        Args:
            enable_versioning: Whether to enable versioning on the bucket
            
        Returns:
            s3.Bucket: The created S3 bucket
        """
        bucket = s3.Bucket(
            self,
            "IntelligentTieringBucket",
            bucket_name=self.bucket_name,
            versioned=enable_versioning,
            # Security configurations
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            encryption=s3.BucketEncryption.S3_MANAGED,
            enforce_ssl=True,
            # Lifecycle configurations
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            # Notification configurations for monitoring
            event_bridge_enabled=True,
            # Intelligent tiering is configured separately via CfnBucket properties
        )

        # Add tags for cost allocation and management
        cdk.Tags.of(bucket).add("Purpose", "IntelligentTieringDemo")
        cdk.Tags.of(bucket).add("CostCenter", "Storage")
        cdk.Tags.of(bucket).add("Environment", "Demo")

        return bucket

    def _create_access_log_bucket(self) -> s3.Bucket:
        """
        Create a separate bucket for storing access logs.
        
        Returns:
            s3.Bucket: The access log bucket
        """
        access_log_bucket = s3.Bucket(
            self,
            "AccessLogBucket",
            bucket_name=f"{self.bucket_name}-access-logs",
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            encryption=s3.BucketEncryption.S3_MANAGED,
            enforce_ssl=True,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            # Lifecycle policy for access logs
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="AccessLogLifecycle",
                    enabled=True,
                    prefix="access-logs/",
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.STANDARD_INFREQUENT_ACCESS,
                            transition_after=Duration.days(30)
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(90)
                        )
                    ],
                    expiration=Duration.days(365)
                )
            ]
        )

        cdk.Tags.of(access_log_bucket).add("Purpose", "AccessLogging")
        cdk.Tags.of(access_log_bucket).add("CostCenter", "Storage")

        return access_log_bucket

    def _configure_access_logging(self) -> None:
        """Configure S3 access logging for the main bucket."""
        # Note: Access logging is configured through the bucket's server_access_logs_bucket property
        # This is handled in the bucket creation, but we can add additional configuration here
        cfn_bucket = self.bucket.node.default_child
        cfn_bucket.logging_configuration = s3.CfnBucket.LoggingConfigurationProperty(
            destination_bucket_name=self.access_log_bucket.bucket_name,
            log_file_prefix="access-logs/"
        )

    def _configure_intelligent_tiering(self) -> None:
        """
        Configure S3 Intelligent Tiering for automatic cost optimization.
        
        This creates intelligent tiering configurations that automatically
        move objects between access tiers based on access patterns.
        """
        # Intelligent tiering configuration for the entire bucket
        s3.CfnBucket.IntelligentTieringConfigurationProperty(
            id="EntireBucketConfig",
            status="Enabled",
            prefix="",
            tierings=[
                s3.CfnBucket.TieringProperty(
                    access_tier="ARCHIVE_ACCESS",
                    days=90
                ),
                s3.CfnBucket.TieringProperty(
                    access_tier="DEEP_ARCHIVE_ACCESS",
                    days=180
                )
            ]
        )

        # Apply intelligent tiering configuration to the bucket
        cfn_bucket = self.bucket.node.default_child
        cfn_bucket.intelligent_tiering_configurations = [
            s3.CfnBucket.IntelligentTieringConfigurationProperty(
                id="EntireBucketConfig",
                status="Enabled",
                prefix="",
                tierings=[
                    s3.CfnBucket.TieringProperty(
                        access_tier="ARCHIVE_ACCESS",
                        days=90
                    ),
                    s3.CfnBucket.TieringProperty(
                        access_tier="DEEP_ARCHIVE_ACCESS",
                        days=180
                    )
                ]
            )
        ]

    def _configure_lifecycle_policies(self) -> None:
        """
        Configure lifecycle policies for comprehensive cost optimization.
        
        These policies complement intelligent tiering by handling:
        - Transition to intelligent tiering
        - Incomplete multipart upload cleanup
        - Non-current version management
        """
        # Add lifecycle rules to the bucket
        cfn_bucket = self.bucket.node.default_child
        cfn_bucket.lifecycle_configuration = s3.CfnBucket.LifecycleConfigurationProperty(
            rules=[
                s3.CfnBucket.LifecycleRuleProperty(
                    id="OptimizeStorage",
                    status="Enabled",
                    prefix="",
                    transitions=[
                        s3.CfnBucket.TransitionProperty(
                            storage_class="INTELLIGENT_TIERING",
                            transition_in_days=30
                        )
                    ],
                    abort_incomplete_multipart_upload=s3.CfnBucket.AbortIncompleteMultipartUploadProperty(
                        days_after_initiation=7
                    ),
                    noncurrent_version_transitions=[
                        s3.CfnBucket.NoncurrentVersionTransitionProperty(
                            storage_class="STANDARD_IA",
                            transition_in_days=30
                        ),
                        s3.CfnBucket.NoncurrentVersionTransitionProperty(
                            storage_class="GLACIER",
                            transition_in_days=90
                        )
                    ],
                    noncurrent_version_expiration=s3.CfnBucket.NoncurrentVersionExpirationProperty(
                        noncurrent_days=365
                    )
                )
            ]
        )

    def _create_cloudwatch_dashboard(self) -> None:
        """
        Create CloudWatch dashboard for monitoring storage optimization.
        
        The dashboard provides visibility into:
        - Storage usage by class
        - Cost optimization metrics
        - Access patterns
        """
        dashboard = cloudwatch.Dashboard(
            self,
            "S3StorageOptimizationDashboard",
            dashboard_name=f"S3-Storage-Optimization-{cdk.Aws.ACCOUNT_ID}",
            period_override=cloudwatch.PeriodOverride.AUTO
        )

        # Storage metrics widget
        storage_widget = cloudwatch.GraphWidget(
            title="S3 Storage by Class",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/S3",
                    metric_name="BucketSizeBytes",
                    dimensions_map={
                        "BucketName": self.bucket.bucket_name,
                        "StorageType": "StandardStorage"
                    },
                    statistic="Average",
                    period=Duration.days(1)
                ),
                cloudwatch.Metric(
                    namespace="AWS/S3",
                    metric_name="BucketSizeBytes",
                    dimensions_map={
                        "BucketName": self.bucket.bucket_name,
                        "StorageType": "IntelligentTieringIAStorage"
                    },
                    statistic="Average",
                    period=Duration.days(1)
                ),
                cloudwatch.Metric(
                    namespace="AWS/S3",
                    metric_name="BucketSizeBytes",
                    dimensions_map={
                        "BucketName": self.bucket.bucket_name,
                        "StorageType": "IntelligentTieringAAStorage"
                    },
                    statistic="Average",
                    period=Duration.days(1)
                )
            ],
            width=12,
            height=6
        )

        # Object count widget
        object_count_widget = cloudwatch.GraphWidget(
            title="Number of Objects",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/S3",
                    metric_name="NumberOfObjects",
                    dimensions_map={
                        "BucketName": self.bucket.bucket_name,
                        "StorageType": "AllStorageTypes"
                    },
                    statistic="Average",
                    period=Duration.days(1)
                )
            ],
            width=12,
            height=6
        )

        # Request metrics widget
        request_widget = cloudwatch.GraphWidget(
            title="S3 Request Metrics",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/S3",
                    metric_name="AllRequests",
                    dimensions_map={
                        "BucketName": self.bucket.bucket_name
                    },
                    statistic="Sum",
                    period=Duration.hours(1)
                )
            ],
            width=12,
            height=6
        )

        # Add widgets to dashboard
        dashboard.add_widgets(storage_widget)
        dashboard.add_widgets(object_count_widget)
        dashboard.add_widgets(request_widget)

    def _create_iam_resources(self) -> None:
        """
        Create IAM roles and policies for secure S3 access.
        
        Creates roles for:
        - Application access with least privilege
        - Monitoring and metrics collection
        - Administrative access
        """
        # Role for applications to access the bucket
        self.app_role = iam.Role(
            self,
            "S3AppAccessRole",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            description="Role for applications to access S3 intelligent tiering bucket",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("CloudWatchAgentServerPolicy")
            ]
        )

        # Custom policy for S3 access
        s3_access_policy = iam.Policy(
            self,
            "S3AccessPolicy",
            statements=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "s3:GetObject",
                        "s3:PutObject",
                        "s3:DeleteObject",
                        "s3:ListBucket",
                        "s3:GetBucketLocation",
                        "s3:GetObjectVersion"
                    ],
                    resources=[
                        self.bucket.bucket_arn,
                        f"{self.bucket.bucket_arn}/*"
                    ]
                ),
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "s3:GetBucketIntelligentTieringConfiguration",
                        "s3:GetLifecycleConfiguration"
                    ],
                    resources=[self.bucket.bucket_arn]
                )
            ]
        )

        s3_access_policy.attach_to_role(self.app_role)

        # Role for monitoring and metrics
        self.monitoring_role = iam.Role(
            self,
            "S3MonitoringRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Role for monitoring S3 intelligent tiering metrics",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole")
            ]
        )

        # Policy for CloudWatch metrics
        monitoring_policy = iam.Policy(
            self,
            "S3MonitoringPolicy",
            statements=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "cloudwatch:GetMetricStatistics",
                        "cloudwatch:ListMetrics",
                        "s3:GetBucketMetricsConfiguration",
                        "s3:ListBucketMetricsConfigurations"
                    ],
                    resources=["*"]
                )
            ]
        )

        monitoring_policy.attach_to_role(self.monitoring_role)

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource identifiers."""
        CfnOutput(
            self,
            "BucketName",
            value=self.bucket.bucket_name,
            description="Name of the S3 bucket with intelligent tiering"
        )

        CfnOutput(
            self,
            "BucketArn",
            value=self.bucket.bucket_arn,
            description="ARN of the S3 bucket"
        )

        CfnOutput(
            self,
            "AppRoleArn",
            value=self.app_role.role_arn,
            description="ARN of the IAM role for application access"
        )

        CfnOutput(
            self,
            "MonitoringRoleArn",
            value=self.monitoring_role.role_arn,
            description="ARN of the IAM role for monitoring"
        )

        if hasattr(self, 'access_log_bucket'):
            CfnOutput(
                self,
                "AccessLogBucketName",
                value=self.access_log_bucket.bucket_name,
                description="Name of the access log bucket"
            )

        CfnOutput(
            self,
            "DashboardURL",
            value=f"https://{cdk.Aws.REGION}.console.aws.amazon.com/cloudwatch/home?region={cdk.Aws.REGION}#dashboards:name=S3-Storage-Optimization-{cdk.Aws.ACCOUNT_ID}",
            description="URL to the CloudWatch dashboard"
        )


def main() -> None:
    """
    Main function to create and deploy the CDK application.
    """
    app = cdk.App()

    # Get configuration from context or environment variables
    bucket_name_prefix = app.node.try_get_context("bucketNamePrefix") or os.environ.get("BUCKET_NAME_PREFIX", "intelligent-tiering-demo")
    enable_versioning = app.node.try_get_context("enableVersioning") != "false"
    enable_access_logging = app.node.try_get_context("enableAccessLogging") != "false"

    # Create the stack
    S3IntelligentTieringStack(
        app,
        "S3IntelligentTieringStack",
        bucket_name_prefix=bucket_name_prefix,
        enable_versioning=enable_versioning,
        enable_access_logging=enable_access_logging,
        description="S3 Intelligent Tiering and Lifecycle Management Stack",
        env=cdk.Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION")
        )
    )

    app.synth()


if __name__ == "__main__":
    main()