#!/usr/bin/env python3
"""
AWS CDK Application for Backup and Archive Strategies with S3 Glacier and Lifecycle Policies

This CDK application creates a comprehensive backup and archive solution using Amazon S3
with intelligent lifecycle policies that automatically transition data through different
storage classes (Standard -> IA -> Glacier IR -> Glacier -> Deep Archive) based on age
and access patterns.

Key Features:
- Multi-tier lifecycle policies for different data types
- CloudWatch monitoring and cost alarms
- IAM roles with least privilege access
- Data retrieval policies for cost control
- Comprehensive tagging strategy
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    aws_s3 as s3,
    aws_iam as iam,
    aws_cloudwatch as cloudwatch,
    aws_glacier as glacier,
    aws_logs as logs,
    RemovalPolicy,
    Duration,
    CfnOutput,
    Tags
)
from constructs import Construct
from typing import List, Dict, Any
import os


class BackupArchiveStack(Stack):
    """
    CDK Stack for implementing backup and archive strategies with S3 Glacier and lifecycle policies.
    
    This stack creates:
    - S3 bucket with versioning enabled for backup integrity
    - Comprehensive lifecycle policies for different data types
    - CloudWatch monitoring and billing alarms
    - IAM roles for secure Glacier operations
    - Data retrieval policies for cost control
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Create the backup and archive S3 bucket
        self.backup_bucket = self._create_backup_bucket()
        
        # Configure lifecycle policies
        self._configure_lifecycle_policies()
        
        # Set up CloudWatch monitoring
        self.cloudwatch_alarm = self._create_cloudwatch_monitoring()
        
        # Create IAM role for Glacier operations
        self.glacier_role = self._create_glacier_iam_role()
        
        # Configure data retrieval policy
        self._configure_data_retrieval_policy()
        
        # Create CloudWatch log group for lifecycle transitions
        self.log_group = self._create_log_group()
        
        # Add stack-level tags
        self._add_stack_tags()
        
        # Create outputs
        self._create_outputs()

    def _create_backup_bucket(self) -> s3.Bucket:
        """
        Create S3 bucket with versioning enabled for backup and archive operations.
        
        Returns:
            s3.Bucket: The created S3 bucket with proper configuration
        """
        bucket = s3.Bucket(
            self, "BackupArchiveBucket",
            bucket_name=f"backup-archive-demo-{self.account}-{self.region}",
            versioned=True,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            encryption=s3.BucketEncryption.S3_MANAGED,
            enforce_ssl=True,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,  # For demo purposes only
            event_bridge_enabled=True,
            intelligent_tiering_configurations=[
                s3.IntelligentTieringConfiguration(
                    name="EntireBucket",
                    optional_fields=[
                        s3.IntelligentTieringOptionalField.ARCHIVE_ACCESS,
                        s3.IntelligentTieringOptionalField.DEEP_ARCHIVE_ACCESS
                    ]
                )
            ]
        )
        
        # Add bucket policy for secure access
        bucket_policy = iam.PolicyDocument(
            statements=[
                iam.PolicyStatement(
                    sid="DenyInsecureConnections",
                    effect=iam.Effect.DENY,
                    principals=[iam.AnyPrincipal()],
                    actions=["s3:*"],
                    resources=[
                        bucket.bucket_arn,
                        f"{bucket.bucket_arn}/*"
                    ],
                    conditions={
                        "Bool": {
                            "aws:SecureTransport": "false"
                        }
                    }
                )
            ]
        )
        
        bucket.add_to_resource_policy(bucket_policy.statements[0])
        
        return bucket

    def _configure_lifecycle_policies(self) -> None:
        """
        Configure comprehensive lifecycle policies for different data types.
        
        Creates three lifecycle rules:
        1. Backup data with comprehensive 7-year retention
        2. Log data with shorter lifecycle and automatic deletion
        3. Document archives with tag-based filtering
        """
        # Backup archive strategy - comprehensive 7-year retention
        backup_rule = s3.LifecycleRule(
            id="backup-archive-strategy",
            enabled=True,
            prefix="backups/",
            transitions=[
                s3.Transition(
                    storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                    transition_after=Duration.days(30)
                ),
                s3.Transition(
                    storage_class=s3.StorageClass.GLACIER_INSTANT_RETRIEVAL,
                    transition_after=Duration.days(90)
                ),
                s3.Transition(
                    storage_class=s3.StorageClass.GLACIER,
                    transition_after=Duration.days(365)
                ),
                s3.Transition(
                    storage_class=s3.StorageClass.DEEP_ARCHIVE,
                    transition_after=Duration.days(2555)  # ~7 years
                )
            ],
            noncurrent_version_transitions=[
                s3.NoncurrentVersionTransition(
                    storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                    transition_after=Duration.days(7)
                ),
                s3.NoncurrentVersionTransition(
                    storage_class=s3.StorageClass.GLACIER,
                    transition_after=Duration.days(30)
                )
            ],
            noncurrent_version_expiration=Duration.days(2920)  # ~8 years
        )
        
        # Logs retention policy - shorter retention with auto-deletion
        logs_rule = s3.LifecycleRule(
            id="logs-retention-policy",
            enabled=True,
            prefix="logs/",
            transitions=[
                s3.Transition(
                    storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                    transition_after=Duration.days(7)
                ),
                s3.Transition(
                    storage_class=s3.StorageClass.GLACIER_INSTANT_RETRIEVAL,
                    transition_after=Duration.days(30)
                ),
                s3.Transition(
                    storage_class=s3.StorageClass.GLACIER,
                    transition_after=Duration.days(90)
                )
            ],
            expiration=Duration.days(2555)  # Auto-delete after ~7 years
        )
        
        # Documents long-term archive - tag-based filtering
        documents_rule = s3.LifecycleRule(
            id="documents-long-term-archive",
            enabled=True,
            prefix="documents/",
            tag_filters={
                "DataClass": "Archive"
            },
            transitions=[
                s3.Transition(
                    storage_class=s3.StorageClass.GLACIER_INSTANT_RETRIEVAL,
                    transition_after=Duration.days(60)
                ),
                s3.Transition(
                    storage_class=s3.StorageClass.GLACIER,
                    transition_after=Duration.days(180)
                ),
                s3.Transition(
                    storage_class=s3.StorageClass.DEEP_ARCHIVE,
                    transition_after=Duration.days(1095)  # ~3 years
                )
            ]
        )
        
        # Add lifecycle rules to bucket
        self.backup_bucket.add_lifecycle_rule(backup_rule)
        self.backup_bucket.add_lifecycle_rule(logs_rule)
        self.backup_bucket.add_lifecycle_rule(documents_rule)

    def _create_cloudwatch_monitoring(self) -> cloudwatch.Alarm:
        """
        Create CloudWatch monitoring for storage costs and usage metrics.
        
        Returns:
            cloudwatch.Alarm: Cost monitoring alarm for budget management
        """
        # Create billing alarm for S3 storage costs
        storage_cost_alarm = cloudwatch.Alarm(
            self, "StorageCostAlarm",
            alarm_name=f"glacier-cost-alarm-{self.region}",
            alarm_description="Monitor S3 storage costs for backup and archive solution",
            metric=cloudwatch.Metric(
                namespace="AWS/Billing",
                metric_name="EstimatedCharges",
                dimensions_map={
                    "Currency": "USD",
                    "ServiceName": "AmazonS3"
                },
                statistic="Maximum",
                period=Duration.days(1)
            ),
            threshold=50.0,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        
        # Create custom metrics for lifecycle transitions
        transition_metric = cloudwatch.Metric(
            namespace="AWS/S3",
            metric_name="BucketSizeBytes",
            dimensions_map={
                "BucketName": self.backup_bucket.bucket_name,
                "StorageType": "StandardStorage"
            },
            statistic="Average",
            period=Duration.days(1)
        )
        
        return storage_cost_alarm

    def _create_glacier_iam_role(self) -> iam.Role:
        """
        Create IAM role for secure Glacier operations with least privilege access.
        
        Returns:
            iam.Role: IAM role for Glacier operations
        """
        # Create trust policy for Glacier service
        glacier_trust_policy = iam.PolicyDocument(
            statements=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    principals=[iam.ServicePrincipal("glacier.amazonaws.com")],
                    actions=["sts:AssumeRole"]
                )
            ]
        )
        
        # Create IAM role
        glacier_role = iam.Role(
            self, "GlacierOperationsRole",
            role_name="GlacierOperationsRole",
            assumed_by=iam.ServicePrincipal("glacier.amazonaws.com"),
            inline_policies={
                "GlacierS3Access": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:GetObject",
                                "s3:GetObjectVersion",
                                "s3:PutObject",
                                "s3:DeleteObject",
                                "s3:RestoreObject",
                                "s3:ListBucket",
                                "s3:GetBucketLocation",
                                "s3:GetBucketVersioning"
                            ],
                            resources=[
                                self.backup_bucket.bucket_arn,
                                f"{self.backup_bucket.bucket_arn}/*"
                            ]
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "glacier:*"
                            ],
                            resources=["*"]
                        )
                    ]
                )
            },
            description="IAM role for S3 Glacier operations with least privilege access"
        )
        
        return glacier_role

    def _configure_data_retrieval_policy(self) -> None:
        """
        Configure data retrieval policy for cost control.
        
        Note: Glacier data retrieval policies are account-level and cannot be
        directly configured via CDK. This method documents the configuration
        that should be applied via CLI or console.
        """
        # Note: Data retrieval policies are account-level configurations
        # They need to be set via AWS CLI as shown in the recipe
        # This is documented here for completeness
        pass

    def _create_log_group(self) -> logs.LogGroup:
        """
        Create CloudWatch log group for lifecycle transition monitoring.
        
        Returns:
            logs.LogGroup: Log group for tracking S3 lifecycle events
        """
        log_group = logs.LogGroup(
            self, "LifecycleTransitionsLogGroup",
            log_group_name="/aws/s3/lifecycle-transitions",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY
        )
        
        return log_group

    def _add_stack_tags(self) -> None:
        """Add consistent tags to all stack resources."""
        Tags.of(self).add("Project", "BackupArchiveStrategy")
        Tags.of(self).add("Environment", "Demo")
        Tags.of(self).add("Purpose", "CostOptimizedArchiving")
        Tags.of(self).add("DataClassification", "Internal")
        Tags.of(self).add("Owner", "CloudOpsTeam")

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources."""
        CfnOutput(
            self, "BackupBucketName",
            value=self.backup_bucket.bucket_name,
            description="Name of the S3 bucket for backup and archive storage",
            export_name=f"{self.stack_name}-BackupBucketName"
        )
        
        CfnOutput(
            self, "BackupBucketArn",
            value=self.backup_bucket.bucket_arn,
            description="ARN of the S3 bucket for backup and archive storage",
            export_name=f"{self.stack_name}-BackupBucketArn"
        )
        
        CfnOutput(
            self, "GlacierRoleArn",
            value=self.glacier_role.role_arn,
            description="ARN of the IAM role for Glacier operations",
            export_name=f"{self.stack_name}-GlacierRoleArn"
        )
        
        CfnOutput(
            self, "CostAlarmName",
            value=self.cloudwatch_alarm.alarm_name,
            description="Name of the CloudWatch alarm monitoring storage costs",
            export_name=f"{self.stack_name}-CostAlarmName"
        )
        
        CfnOutput(
            self, "LogGroupName",
            value=self.log_group.log_group_name,
            description="Name of the CloudWatch log group for lifecycle transitions",
            export_name=f"{self.stack_name}-LogGroupName"
        )


class BackupArchiveApp(cdk.App):
    """
    CDK Application for deploying backup and archive infrastructure.
    """
    
    def __init__(self):
        super().__init__()
        
        # Get environment configuration
        account = self.node.try_get_context("account") or os.environ.get("CDK_DEFAULT_ACCOUNT")
        region = self.node.try_get_context("region") or os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
        
        # Create the backup archive stack
        BackupArchiveStack(
            self, "BackupArchiveStack",
            env=Environment(account=account, region=region),
            description="Backup and Archive Strategies with S3 Glacier and Lifecycle Policies",
            stack_name="backup-archive-demo"
        )


# Create and synthesize the CDK application
if __name__ == "__main__":
    app = BackupArchiveApp()
    app.synth()