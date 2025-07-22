#!/usr/bin/env python3
"""
AWS DataSync Data Transfer Automation - CDK Python Application

This CDK application creates a complete DataSync infrastructure for automated data transfer
between S3 buckets with monitoring, logging, and scheduled execution capabilities.

Author: AWS Recipe Generator
Version: 1.0
"""

import os
from typing import Dict, Any, Optional
import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    Tags,
    Duration,
    RemovalPolicy,
    CfnOutput,
)
from aws_cdk import aws_s3 as s3
from aws_cdk import aws_iam as iam
from aws_cdk import aws_datasync as datasync
from aws_cdk import aws_logs as logs
from aws_cdk import aws_events as events
from aws_cdk import aws_events_targets as targets
from aws_cdk import aws_cloudwatch as cloudwatch
from constructs import Construct


class DataSyncDataTransferStack(Stack):
    """
    CDK Stack for AWS DataSync Data Transfer Automation
    
    This stack creates:
    - Source and destination S3 buckets
    - DataSync task with locations and configuration
    - IAM roles with least privilege permissions
    - CloudWatch logging and monitoring
    - EventBridge scheduled execution
    - CloudWatch dashboard for monitoring
    """

    def __init__(
        self, 
        scope: Construct, 
        construct_id: str, 
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Environment variables for customization
        self.environment_suffix = self.node.try_get_context("environment_suffix") or "dev"
        self.bucket_prefix = self.node.try_get_context("bucket_prefix") or "datasync"
        self.schedule_expression = self.node.try_get_context("schedule_expression") or "rate(1 day)"
        self.log_retention_days = int(self.node.try_get_context("log_retention_days") or "30")
        
        # Create S3 buckets
        self.source_bucket, self.destination_bucket = self._create_s3_buckets()
        
        # Create IAM roles
        self.datasync_role, self.eventbridge_role = self._create_iam_roles()
        
        # Create CloudWatch log group
        self.log_group = self._create_log_group()
        
        # Create DataSync components
        self.source_location, self.destination_location, self.datasync_task = self._create_datasync_components()
        
        # Create EventBridge scheduled execution
        self.event_rule = self._create_scheduled_execution()
        
        # Create CloudWatch dashboard
        self.dashboard = self._create_monitoring_dashboard()
        
        # Create outputs
        self._create_outputs()
        
        # Add tags to all resources
        self._add_tags()

    def _create_s3_buckets(self) -> tuple[s3.Bucket, s3.Bucket]:
        """Create source and destination S3 buckets with security best practices."""
        
        # Source bucket
        source_bucket = s3.Bucket(
            self,
            "SourceBucket",
            bucket_name=f"{self.bucket_prefix}-source-{self.environment_suffix}-{self.account}",
            encryption=s3.BucketEncryption.S3_MANAGED,
            versioning=True,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteIncompleteMultipartUploads",
                    abort_incomplete_multipart_upload_after=Duration.days(7)
                )
            ],
            removal_policy=RemovalPolicy.DESTROY,  # For demo purposes
            auto_delete_objects=True,  # For demo purposes
        )
        
        # Destination bucket
        destination_bucket = s3.Bucket(
            self,
            "DestinationBucket",
            bucket_name=f"{self.bucket_prefix}-dest-{self.environment_suffix}-{self.account}",
            encryption=s3.BucketEncryption.S3_MANAGED,
            versioning=True,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteIncompleteMultipartUploads",
                    abort_incomplete_multipart_upload_after=Duration.days(7)
                ),
                s3.LifecycleRule(
                    id="TransitionToIA",
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30)
                        )
                    ]
                )
            ],
            removal_policy=RemovalPolicy.DESTROY,  # For demo purposes
            auto_delete_objects=True,  # For demo purposes
        )
        
        return source_bucket, destination_bucket

    def _create_iam_roles(self) -> tuple[iam.Role, iam.Role]:
        """Create IAM roles for DataSync and EventBridge with least privilege permissions."""
        
        # DataSync service role
        datasync_role = iam.Role(
            self,
            "DataSyncServiceRole",
            role_name=f"DataSyncServiceRole-{self.environment_suffix}",
            assumed_by=iam.ServicePrincipal("datasync.amazonaws.com"),
            description="IAM role for DataSync service to access S3 buckets",
            inline_policies={
                "S3AccessPolicy": iam.PolicyDocument(
                    statements=[
                        # Bucket-level permissions
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:GetBucketLocation",
                                "s3:ListBucket",
                                "s3:ListBucketMultipartUploads",
                            ],
                            resources=[
                                self.source_bucket.bucket_arn,
                                self.destination_bucket.bucket_arn,
                            ]
                        ),
                        # Object-level permissions
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:GetObject",
                                "s3:GetObjectTagging",
                                "s3:GetObjectVersion",
                                "s3:GetObjectVersionTagging",
                                "s3:PutObject",
                                "s3:PutObjectTagging",
                                "s3:DeleteObject",
                                "s3:AbortMultipartUpload",
                                "s3:ListMultipartUploadParts",
                            ],
                            resources=[
                                f"{self.source_bucket.bucket_arn}/*",
                                f"{self.destination_bucket.bucket_arn}/*",
                            ]
                        ),
                        # CloudWatch Logs permissions
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "logs:CreateLogGroup",
                                "logs:CreateLogStream",
                                "logs:PutLogEvents",
                            ],
                            resources=[
                                f"arn:aws:logs:{self.region}:{self.account}:log-group:/aws/datasync/*"
                            ]
                        )
                    ]
                )
            }
        )
        
        # EventBridge role for triggering DataSync
        eventbridge_role = iam.Role(
            self,
            "EventBridgeDataSyncRole",
            role_name=f"EventBridgeDataSyncRole-{self.environment_suffix}",
            assumed_by=iam.ServicePrincipal("events.amazonaws.com"),
            description="IAM role for EventBridge to invoke DataSync tasks",
        )
        
        return datasync_role, eventbridge_role

    def _create_log_group(self) -> logs.LogGroup:
        """Create CloudWatch log group for DataSync logging."""
        
        log_group = logs.LogGroup(
            self,
            "DataSyncLogGroup",
            log_group_name=f"/aws/datasync/task-{self.environment_suffix}",
            retention=logs.RetentionDays(self.log_retention_days),
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        return log_group

    def _create_datasync_components(self) -> tuple[datasync.CfnLocationS3, datasync.CfnLocationS3, datasync.CfnTask]:
        """Create DataSync locations and task with optimized configuration."""
        
        # Source location (S3)
        source_location = datasync.CfnLocationS3(
            self,
            "DataSyncSourceLocation",
            s3_bucket_arn=self.source_bucket.bucket_arn,
            s3_config=datasync.CfnLocationS3.S3ConfigProperty(
                bucket_access_role_arn=self.datasync_role.role_arn
            ),
        )
        
        # Destination location (S3)
        destination_location = datasync.CfnLocationS3(
            self,
            "DataSyncDestinationLocation",
            s3_bucket_arn=self.destination_bucket.bucket_arn,
            s3_config=datasync.CfnLocationS3.S3ConfigProperty(
                bucket_access_role_arn=self.datasync_role.role_arn
            ),
        )
        
        # DataSync task with optimized options
        datasync_task = datasync.CfnTask(
            self,
            "DataSyncTask",
            name=f"DataSyncTask-{self.environment_suffix}",
            source_location_arn=source_location.attr_location_arn,
            destination_location_arn=destination_location.attr_location_arn,
            cloud_watch_log_group_arn=self.log_group.log_group_arn,
            options=datasync.CfnTask.OptionsProperty(
                verify_mode="POINT_IN_TIME_CONSISTENT",
                overwrite_mode="ALWAYS",
                preserve_deleted_files="PRESERVE",
                preserve_devices="NONE",
                posix_permissions="NONE",
                bytes_per_second=-1,  # No bandwidth limit
                task_queueing="ENABLED",
                log_level="TRANSFER",
                transfer_mode="CHANGED",
            ),
            # Task reporting configuration
            includes=[
                datasync.CfnTask.FilterRuleProperty(
                    filter_type="SIMPLE_PATTERN",
                    value="*"
                )
            ],
        )
        
        # Add dependency to ensure role is created first
        datasync_task.add_dependency(source_location)
        datasync_task.add_dependency(destination_location)
        
        return source_location, destination_location, datasync_task

    def _create_scheduled_execution(self) -> events.Rule:
        """Create EventBridge rule for scheduled DataSync execution."""
        
        # Grant EventBridge permission to start DataSync task
        self.eventbridge_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["datasync:StartTaskExecution"],
                resources=[self.datasync_task.attr_task_arn]
            )
        )
        
        # Create EventBridge rule
        event_rule = events.Rule(
            self,
            "DataSyncScheduledExecution",
            rule_name=f"DataSyncScheduledExecution-{self.environment_suffix}",
            description="Scheduled execution of DataSync task for automated data transfer",
            schedule=events.Schedule.expression(self.schedule_expression),
            enabled=True,
        )
        
        # Add DataSync task as target
        event_rule.add_target(
            targets.AwsApi(
                service="datasync",
                action="startTaskExecution",
                parameters={
                    "TaskArn": self.datasync_task.attr_task_arn
                },
                role=self.eventbridge_role,
            )
        )
        
        return event_rule

    def _create_monitoring_dashboard(self) -> cloudwatch.Dashboard:
        """Create CloudWatch dashboard for DataSync monitoring."""
        
        dashboard = cloudwatch.Dashboard(
            self,
            "DataSyncMonitoringDashboard",
            dashboard_name=f"DataSync-Monitoring-{self.environment_suffix}",
            period_override=cloudwatch.PeriodOverride.AUTO,
        )
        
        # DataSync metrics widgets
        bytes_transferred_widget = cloudwatch.GraphWidget(
            title="Bytes Transferred",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/DataSync",
                    metric_name="BytesTransferred",
                    dimensions_map={
                        "TaskArn": self.datasync_task.attr_task_arn
                    },
                    statistic="Sum",
                    period=Duration.minutes(5),
                )
            ],
            width=12,
            height=6,
        )
        
        files_transferred_widget = cloudwatch.GraphWidget(
            title="Files Transferred",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/DataSync",
                    metric_name="FilesTransferred",
                    dimensions_map={
                        "TaskArn": self.datasync_task.attr_task_arn
                    },
                    statistic="Sum",
                    period=Duration.minutes(5),
                )
            ],
            width=12,
            height=6,
        )
        
        # S3 bucket metrics
        source_bucket_size_widget = cloudwatch.GraphWidget(
            title="Source Bucket Size",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/S3",
                    metric_name="BucketSizeBytes",
                    dimensions_map={
                        "BucketName": self.source_bucket.bucket_name,
                        "StorageType": "StandardStorage"
                    },
                    statistic="Average",
                    period=Duration.hours(24),
                )
            ],
            width=12,
            height=6,
        )
        
        destination_bucket_size_widget = cloudwatch.GraphWidget(
            title="Destination Bucket Size",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/S3",
                    metric_name="BucketSizeBytes",
                    dimensions_map={
                        "BucketName": self.destination_bucket.bucket_name,
                        "StorageType": "StandardStorage"
                    },
                    statistic="Average",
                    period=Duration.hours(24),
                )
            ],
            width=12,
            height=6,
        )
        
        # Add widgets to dashboard
        dashboard.add_widgets(
            bytes_transferred_widget,
            files_transferred_widget,
        )
        dashboard.add_widgets(
            source_bucket_size_widget,
            destination_bucket_size_widget,
        )
        
        return dashboard

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource identifiers."""
        
        CfnOutput(
            self,
            "SourceBucketName",
            value=self.source_bucket.bucket_name,
            description="Name of the source S3 bucket",
            export_name=f"DataSync-SourceBucket-{self.environment_suffix}",
        )
        
        CfnOutput(
            self,
            "DestinationBucketName",
            value=self.destination_bucket.bucket_name,
            description="Name of the destination S3 bucket",
            export_name=f"DataSync-DestinationBucket-{self.environment_suffix}",
        )
        
        CfnOutput(
            self,
            "DataSyncTaskArn",
            value=self.datasync_task.attr_task_arn,
            description="ARN of the DataSync task",
            export_name=f"DataSync-TaskArn-{self.environment_suffix}",
        )
        
        CfnOutput(
            self,
            "DataSyncRoleArn",
            value=self.datasync_role.role_arn,
            description="ARN of the DataSync service role",
            export_name=f"DataSync-RoleArn-{self.environment_suffix}",
        )
        
        CfnOutput(
            self,
            "LogGroupName",
            value=self.log_group.log_group_name,
            description="Name of the CloudWatch log group",
            export_name=f"DataSync-LogGroup-{self.environment_suffix}",
        )
        
        CfnOutput(
            self,
            "DashboardUrl",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.dashboard.dashboard_name}",
            description="URL to the CloudWatch dashboard",
        )

    def _add_tags(self) -> None:
        """Add consistent tags to all resources in the stack."""
        
        Tags.of(self).add("Project", "DataSync-Automation")
        Tags.of(self).add("Environment", self.environment_suffix)
        Tags.of(self).add("ManagedBy", "CDK")
        Tags.of(self).add("Recipe", "datasync-data-transfer-automation")
        Tags.of(self).add("CostCenter", "DataManagement")


def main() -> None:
    """Main function to create and deploy the CDK application."""
    
    app = cdk.App()
    
    # Get environment configuration
    account = app.node.try_get_context("account") or os.environ.get("CDK_DEFAULT_ACCOUNT")
    region = app.node.try_get_context("region") or os.environ.get("CDK_DEFAULT_REGION")
    
    if not account or not region:
        raise ValueError("AWS account and region must be specified via CDK context or environment variables")
    
    env = Environment(account=account, region=region)
    
    # Create the stack
    DataSyncDataTransferStack(
        app,
        "DataSyncDataTransferStack",
        env=env,
        description="AWS DataSync Data Transfer Automation infrastructure",
        stack_name="datasync-data-transfer-automation",
    )
    
    app.synth()


if __name__ == "__main__":
    main()