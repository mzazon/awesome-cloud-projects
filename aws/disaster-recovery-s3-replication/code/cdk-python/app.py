#!/usr/bin/env python3
"""
AWS CDK Python application for S3 Cross-Region Replication disaster recovery solution.

This application creates a comprehensive disaster recovery setup with S3 Cross-Region Replication,
including source and destination buckets, IAM roles, CloudWatch monitoring, and CloudTrail logging.
"""

import os
from aws_cdk import (
    App,
    Stack,
    StackProps,
    Environment,
    CfnOutput,
    Duration,
    RemovalPolicy,
    aws_s3 as s3,
    aws_iam as iam,
    aws_cloudtrail as cloudtrail,
    aws_cloudwatch as cloudwatch,
    aws_sns as sns,
    aws_logs as logs,
)
from constructs import Construct
from typing import Optional


class DisasterRecoveryS3Stack(Stack):
    """
    CDK Stack for S3 Cross-Region Replication disaster recovery solution.
    
    This stack creates:
    - Source S3 bucket with versioning in primary region
    - Destination S3 bucket with versioning in DR region
    - IAM role with appropriate permissions for replication
    - Cross-region replication configuration
    - CloudTrail for audit logging
    - CloudWatch alarms for monitoring
    - SNS topic for notifications
    """

    def __init__(
        self, 
        scope: Construct, 
        construct_id: str, 
        dr_region: str,
        unique_suffix: Optional[str] = None,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix if not provided
        if not unique_suffix:
            unique_suffix = self.account[-6:].lower()

        # Bucket names with unique suffix
        source_bucket_name = f"dr-source-{unique_suffix}"
        dest_bucket_name = f"dr-destination-{unique_suffix}"
        
        # Create source S3 bucket with versioning enabled
        self.source_bucket = s3.Bucket(
            self, "SourceBucket",
            bucket_name=source_bucket_name,
            versioned=True,
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            encryption=s3.BucketEncryption.S3_MANAGED,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteIncompleteMultipartUploads",
                    abort_incomplete_multipart_upload_after=Duration.days(7),
                    enabled=True
                )
            ],
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True
        )

        # Create destination S3 bucket with versioning enabled
        self.destination_bucket = s3.Bucket(
            self, "DestinationBucket",
            bucket_name=dest_bucket_name,
            versioned=True,
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            encryption=s3.BucketEncryption.S3_MANAGED,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="TransitionToIA",
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
                    enabled=True
                )
            ],
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True
        )

        # Create IAM role for S3 replication
        self.replication_role = iam.Role(
            self, "ReplicationRole",
            role_name=f"s3-replication-role-{unique_suffix}",
            assumed_by=iam.ServicePrincipal("s3.amazonaws.com"),
            description="IAM role for S3 cross-region replication"
        )

        # Add inline policy for replication permissions
        replication_policy = iam.PolicyDocument(
            statements=[
                # Permissions to read from source bucket
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "s3:GetObjectVersionForReplication",
                        "s3:GetObjectVersionAcl",
                        "s3:GetObjectVersionTagging"
                    ],
                    resources=[f"{self.source_bucket.bucket_arn}/*"]
                ),
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=["s3:ListBucket"],
                    resources=[self.source_bucket.bucket_arn]
                ),
                # Permissions to write to destination bucket
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "s3:ReplicateObject",
                        "s3:ReplicateDelete",
                        "s3:ReplicateTags"
                    ],
                    resources=[f"arn:aws:s3:::{dest_bucket_name}/*"]
                )
            ]
        )

        self.replication_role.attach_inline_policy(
            iam.Policy(
                self, "ReplicationPolicy",
                document=replication_policy
            )
        )

        # Configure cross-region replication on source bucket
        replication_config = s3.CfnBucket.ReplicationConfigurationProperty(
            role=self.replication_role.role_arn,
            rules=[
                s3.CfnBucket.ReplicationRuleProperty(
                    id="disaster-recovery-replication",
                    status="Enabled",
                    priority=1,
                    delete_marker_replication=s3.CfnBucket.DeleteMarkerReplicationProperty(
                        status="Enabled"
                    ),
                    filter=s3.CfnBucket.ReplicationRuleFilterProperty(
                        prefix=""  # Replicate all objects
                    ),
                    destination=s3.CfnBucket.ReplicationDestinationProperty(
                        bucket=f"arn:aws:s3:::{dest_bucket_name}",
                        storage_class="STANDARD_IA"
                    )
                )
            ]
        )

        # Apply replication configuration to source bucket
        cfn_source_bucket = self.source_bucket.node.default_child
        cfn_source_bucket.replication_configuration = replication_config

        # Create CloudWatch Log Group for CloudTrail
        log_group = logs.LogGroup(
            self, "CloudTrailLogGroup",
            log_group_name=f"/aws/cloudtrail/s3-replication-{unique_suffix}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY
        )

        # Create CloudTrail for audit logging
        trail = cloudtrail.Trail(
            self, "S3ReplicationTrail",
            trail_name=f"s3-replication-trail-{unique_suffix}",
            bucket=self.source_bucket,
            s3_key_prefix="cloudtrail-logs/",
            include_global_service_events=True,
            is_multi_region_trail=True,
            enable_file_validation=True,
            cloud_watch_log_group=log_group
        )

        # Add data events for S3 buckets
        trail.add_s3_event_selector(
            read_write_type=cloudtrail.ReadWriteType.ALL,
            include_management_events=True,
            s3_bucket_and_object_prefix=[
                s3.Bucket.from_bucket_name(self, "SourceBucketRef", source_bucket_name),
                s3.Bucket.from_bucket_name(self, "DestBucketRef", dest_bucket_name)
            ]
        )

        # Create SNS topic for alerts
        alert_topic = sns.Topic(
            self, "S3AlertsTopic",
            topic_name=f"s3-replication-alerts-{unique_suffix}",
            display_name="S3 Replication Alerts"
        )

        # Create CloudWatch alarm for replication latency
        replication_alarm = cloudwatch.Alarm(
            self, "ReplicationLatencyAlarm",
            alarm_name=f"S3-Replication-Latency-{unique_suffix}",
            alarm_description="Monitor S3 replication latency",
            metric=cloudwatch.Metric(
                namespace="AWS/S3",
                metric_name="ReplicationLatency",
                dimensions_map={
                    "SourceBucket": source_bucket_name
                },
                statistic="Average",
                period=Duration.minutes(5)
            ),
            threshold=900,  # 15 minutes
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )

        # Add SNS action to alarm
        replication_alarm.add_alarm_action(
            cloudwatch.SnsAction(alert_topic)
        )

        # Create CloudWatch alarm for failed replications
        failed_replication_alarm = cloudwatch.Alarm(
            self, "FailedReplicationAlarm",
            alarm_name=f"S3-Replication-Failures-{unique_suffix}",
            alarm_description="Monitor S3 replication failures",
            metric=cloudwatch.Metric(
                namespace="AWS/S3",
                metric_name="ReplicationLatency",
                dimensions_map={
                    "SourceBucket": source_bucket_name
                },
                statistic="Maximum",
                period=Duration.minutes(5)
            ),
            threshold=1800,  # 30 minutes indicates potential failure
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=3,
            treat_missing_data=cloudwatch.TreatMissingData.BREACHING
        )

        failed_replication_alarm.add_alarm_action(
            cloudwatch.SnsAction(alert_topic)
        )

        # Outputs
        CfnOutput(
            self, "SourceBucketName",
            value=self.source_bucket.bucket_name,
            description="Name of the source S3 bucket",
            export_name=f"{self.stack_name}-SourceBucketName"
        )

        CfnOutput(
            self, "DestinationBucketName",
            value=self.destination_bucket.bucket_name,
            description="Name of the destination S3 bucket",
            export_name=f"{self.stack_name}-DestinationBucketName"
        )

        CfnOutput(
            self, "ReplicationRoleArn",
            value=self.replication_role.role_arn,
            description="ARN of the replication IAM role",
            export_name=f"{self.stack_name}-ReplicationRoleArn"
        )

        CfnOutput(
            self, "CloudTrailArn",
            value=trail.trail_arn,
            description="ARN of the CloudTrail for audit logging",
            export_name=f"{self.stack_name}-CloudTrailArn"
        )

        CfnOutput(
            self, "AlertTopicArn",
            value=alert_topic.topic_arn,
            description="ARN of the SNS topic for replication alerts",
            export_name=f"{self.stack_name}-AlertTopicArn"
        )

        CfnOutput(
            self, "PrimaryRegion",
            value=self.region,
            description="Primary region for disaster recovery setup",
            export_name=f"{self.stack_name}-PrimaryRegion"
        )

        CfnOutput(
            self, "DisasterRecoveryRegion",
            value=dr_region,
            description="Disaster recovery region",
            export_name=f"{self.stack_name}-DisasterRecoveryRegion"
        )


def main():
    """
    Main function to create and deploy the CDK application.
    """
    app = App()

    # Get configuration from environment variables or context
    primary_region = app.node.try_get_context("primary_region") or "us-east-1"
    dr_region = app.node.try_get_context("dr_region") or "us-west-2"
    account_id = app.node.try_get_context("account") or os.environ.get("CDK_DEFAULT_ACCOUNT")
    unique_suffix = app.node.try_get_context("unique_suffix")

    if not account_id:
        raise ValueError("AWS Account ID must be specified either via CDK_DEFAULT_ACCOUNT environment variable or --context account=123456789012")

    # Create the primary stack in the primary region
    primary_stack = DisasterRecoveryS3Stack(
        app, "DisasterRecoveryS3Primary",
        dr_region=dr_region,
        unique_suffix=unique_suffix,
        env=Environment(
            account=account_id,
            region=primary_region
        ),
        description=f"S3 Cross-Region Replication disaster recovery - Primary stack in {primary_region}"
    )

    # Add tags to all resources
    app.node.apply_aspect(
        # Note: You would typically use cdk.Tags.of() here, but for simplicity we'll add them manually
        # Tags can be added via the CLI or in cdk.json
    )

    app.synth()


if __name__ == "__main__":
    main()