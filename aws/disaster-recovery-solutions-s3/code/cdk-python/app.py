#!/usr/bin/env python3
"""
CDK Python Application for S3 Cross-Region Replication Disaster Recovery

This application creates a comprehensive disaster recovery solution using S3 Cross-Region Replication.
It includes source and replica buckets, IAM roles, monitoring, and lifecycle policies.
"""

import os
from typing import Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    StackProps,
    Environment,
    Duration,
    RemovalPolicy,
    aws_s3 as s3,
    aws_iam as iam,
    aws_cloudwatch as cloudwatch,
    aws_cloudwatch_actions as cw_actions,
    aws_sns as sns,
    aws_sns_subscriptions as sns_subscriptions,
    aws_logs as logs,
    aws_cloudtrail as cloudtrail,
)
from constructs import Construct


class S3DisasterRecoveryStack(Stack):
    """
    Stack for S3 Cross-Region Replication Disaster Recovery Solution
    
    This stack creates:
    - Source S3 bucket with versioning and lifecycle policies
    - Replica S3 bucket in secondary region
    - IAM role for cross-region replication
    - CloudWatch monitoring and alarms
    - SNS topic for alerts
    - CloudTrail for audit logging
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        primary_region: str = "us-east-1",
        secondary_region: str = "us-west-2",
        notification_email: Optional[str] = None,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        self.primary_region = primary_region
        self.secondary_region = secondary_region
        self.notification_email = notification_email

        # Generate unique suffix for resource names
        random_suffix = self.node.try_get_context("random_suffix") or "dr"
        self.resource_suffix = f"{random_suffix}-{self.account}"[:8]

        # Create SNS topic for alerts
        self.alert_topic = self._create_alert_topic()

        # Create source bucket in primary region
        self.source_bucket = self._create_source_bucket()

        # Create replica bucket in secondary region
        self.replica_bucket = self._create_replica_bucket()

        # Create IAM role for replication
        self.replication_role = self._create_replication_role()

        # Configure cross-region replication
        self._configure_replication()

        # Create CloudWatch monitoring
        self._create_monitoring()

        # Create CloudTrail for audit logging
        self._create_cloudtrail()

        # Create outputs
        self._create_outputs()

    def _create_alert_topic(self) -> sns.Topic:
        """Create SNS topic for disaster recovery alerts"""
        topic = sns.Topic(
            self,
            "DrAlertTopic",
            topic_name=f"s3-dr-alerts-{self.resource_suffix}",
            display_name="S3 Disaster Recovery Alerts",
            description="SNS topic for S3 cross-region replication alerts",
        )

        # Add email subscription if provided
        if self.notification_email:
            topic.add_subscription(
                sns_subscriptions.EmailSubscription(self.notification_email)
            )

        cdk.Tags.of(topic).add("Purpose", "DisasterRecovery")
        cdk.Tags.of(topic).add("Environment", "Production")
        cdk.Tags.of(topic).add("CostCenter", "IT-DR")

        return topic

    def _create_source_bucket(self) -> s3.Bucket:
        """Create source S3 bucket with versioning and lifecycle policies"""
        bucket = s3.Bucket(
            self,
            "SourceBucket",
            bucket_name=f"dr-source-bucket-{self.resource_suffix}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                # Transition standard data to IA after 30 days
                s3.LifecycleRule(
                    id="TransitionToIA",
                    enabled=True,
                    prefix="standard/",
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
                # Delete incomplete multipart uploads after 7 days
                s3.LifecycleRule(
                    id="CleanupIncompleteUploads",
                    enabled=True,
                    abort_incomplete_multipart_upload_after=Duration.days(7),
                ),
            ],
        )

        # Add bucket notification for monitoring
        bucket.add_object_created_notification(
            cw_actions.SnsAction(self.alert_topic),
            s3.NotificationKeyFilter(prefix="critical/"),
        )

        cdk.Tags.of(bucket).add("Purpose", "DisasterRecovery")
        cdk.Tags.of(bucket).add("Environment", "Production")
        cdk.Tags.of(bucket).add("CostCenter", "IT-DR")
        cdk.Tags.of(bucket).add("BackupType", "Source")

        return bucket

    def _create_replica_bucket(self) -> s3.Bucket:
        """Create replica S3 bucket in secondary region"""
        # Note: This creates a bucket in the same region as the stack
        # In a real deployment, you'd need a separate stack in the secondary region
        bucket = s3.Bucket(
            self,
            "ReplicaBucket",
            bucket_name=f"dr-replica-bucket-{self.resource_suffix}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        cdk.Tags.of(bucket).add("Purpose", "DisasterRecovery")
        cdk.Tags.of(bucket).add("Environment", "Production")
        cdk.Tags.of(bucket).add("CostCenter", "IT-DR")
        cdk.Tags.of(bucket).add("BackupType", "Replica")

        return bucket

    def _create_replication_role(self) -> iam.Role:
        """Create IAM role for S3 cross-region replication"""
        role = iam.Role(
            self,
            "ReplicationRole",
            role_name=f"s3-replication-role-{self.resource_suffix}",
            assumed_by=iam.ServicePrincipal("s3.amazonaws.com"),
            description="IAM role for S3 cross-region replication",
        )

        # Add permissions for source bucket
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetReplicationConfiguration",
                    "s3:ListBucket",
                ],
                resources=[self.source_bucket.bucket_arn],
            )
        )

        # Add permissions for source bucket objects
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObjectVersionForReplication",
                    "s3:GetObjectVersionAcl",
                    "s3:GetObjectVersionTagging",
                ],
                resources=[f"{self.source_bucket.bucket_arn}/*"],
            )
        )

        # Add permissions for replica bucket objects
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:ReplicateObject",
                    "s3:ReplicateDelete",
                    "s3:ReplicateTags",
                ],
                resources=[f"{self.replica_bucket.bucket_arn}/*"],
            )
        )

        cdk.Tags.of(role).add("Purpose", "DisasterRecovery")
        cdk.Tags.of(role).add("Environment", "Production")
        cdk.Tags.of(role).add("CostCenter", "IT-DR")

        return role

    def _configure_replication(self) -> None:
        """Configure S3 cross-region replication rules"""
        # Add replication configuration to source bucket
        cfn_bucket = self.source_bucket.node.default_child
        cfn_bucket.replication_configuration = s3.CfnBucket.ReplicationConfigurationProperty(
            role=self.replication_role.role_arn,
            rules=[
                # Rule for all objects
                s3.CfnBucket.ReplicationRuleProperty(
                    id="ReplicateEverything",
                    status="Enabled",
                    priority=1,
                    prefix="",
                    destination=s3.CfnBucket.ReplicationDestinationProperty(
                        bucket=self.replica_bucket.bucket_arn,
                        storage_class="STANDARD_IA",
                    ),
                    delete_marker_replication=s3.CfnBucket.DeleteMarkerReplicationProperty(
                        status="Enabled"
                    ),
                ),
                # Rule for critical data
                s3.CfnBucket.ReplicationRuleProperty(
                    id="ReplicateCriticalData",
                    status="Enabled",
                    priority=2,
                    filter=s3.CfnBucket.ReplicationRuleFilterProperty(
                        and_=s3.CfnBucket.ReplicationRuleAndOperatorProperty(
                            prefix="critical/",
                            tag_filters=[
                                s3.CfnBucket.TagFilterProperty(
                                    key="Classification",
                                    value="Critical",
                                ),
                            ],
                        )
                    ),
                    destination=s3.CfnBucket.ReplicationDestinationProperty(
                        bucket=self.replica_bucket.bucket_arn,
                        storage_class="STANDARD",
                    ),
                    delete_marker_replication=s3.CfnBucket.DeleteMarkerReplicationProperty(
                        status="Enabled"
                    ),
                ),
            ],
        )

    def _create_monitoring(self) -> None:
        """Create CloudWatch monitoring and alarms"""
        # Create custom metric for replication monitoring
        replication_latency_metric = cloudwatch.Metric(
            namespace="AWS/S3",
            metric_name="ReplicationLatency",
            dimensions_map={
                "SourceBucket": self.source_bucket.bucket_name,
                "DestinationBucket": self.replica_bucket.bucket_name,
            },
            statistic="Average",
            period=Duration.minutes(5),
        )

        # Create alarm for replication latency
        replication_alarm = cloudwatch.Alarm(
            self,
            "ReplicationLatencyAlarm",
            alarm_name=f"S3-Replication-Latency-{self.source_bucket.bucket_name}",
            alarm_description="S3 replication latency exceeds threshold",
            metric=replication_latency_metric,
            threshold=900,  # 15 minutes in seconds
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=2,
            datapoints_to_alarm=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

        # Add SNS action to alarm
        replication_alarm.add_alarm_action(cw_actions.SnsAction(self.alert_topic))

        # Create failure count metric
        replication_failure_metric = cloudwatch.Metric(
            namespace="AWS/S3",
            metric_name="ReplicationFailureCount",
            dimensions_map={
                "SourceBucket": self.source_bucket.bucket_name,
                "DestinationBucket": self.replica_bucket.bucket_name,
            },
            statistic="Sum",
            period=Duration.minutes(5),
        )

        # Create alarm for replication failures
        failure_alarm = cloudwatch.Alarm(
            self,
            "ReplicationFailureAlarm",
            alarm_name=f"S3-Replication-Failures-{self.source_bucket.bucket_name}",
            alarm_description="S3 replication failures detected",
            metric=replication_failure_metric,
            threshold=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
            evaluation_periods=1,
            datapoints_to_alarm=1,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

        # Add SNS action to failure alarm
        failure_alarm.add_alarm_action(cw_actions.SnsAction(self.alert_topic))

        # Create CloudWatch dashboard
        dashboard = cloudwatch.Dashboard(
            self,
            "DrDashboard",
            dashboard_name=f"S3-DR-Dashboard-{self.resource_suffix}",
            widgets=[
                [
                    cloudwatch.GraphWidget(
                        title="S3 Replication Latency",
                        left=[replication_latency_metric],
                        width=12,
                        height=6,
                    )
                ],
                [
                    cloudwatch.GraphWidget(
                        title="S3 Replication Failures",
                        left=[replication_failure_metric],
                        width=12,
                        height=6,
                    )
                ],
            ],
        )

    def _create_cloudtrail(self) -> None:
        """Create CloudTrail for audit logging"""
        # Create CloudWatch log group for CloudTrail
        log_group = logs.LogGroup(
            self,
            "CloudTrailLogGroup",
            log_group_name=f"/aws/cloudtrail/s3-dr-{self.resource_suffix}",
            retention=logs.RetentionDays.ONE_YEAR,
            removal_policy=RemovalPolicy.DESTROY,
        )

        # Create CloudTrail
        trail = cloudtrail.Trail(
            self,
            "DrAuditTrail",
            trail_name=f"s3-dr-audit-trail-{self.resource_suffix}",
            bucket=self.source_bucket,
            s3_key_prefix="audit-logs/",
            include_global_service_events=True,
            is_multi_region_trail=True,
            enable_file_validation=True,
            cloud_watch_logs_group=log_group,
            management_events=cloudtrail.ReadWriteType.ALL,
        )

        # Add event selectors for S3 data events
        trail.add_s3_event_selector(
            [
                cloudtrail.S3EventSelector(
                    bucket=self.source_bucket,
                    object_prefix="",
                    include_management_events=True,
                    read_write_type=cloudtrail.ReadWriteType.ALL,
                )
            ]
        )

        cdk.Tags.of(trail).add("Purpose", "DisasterRecovery")
        cdk.Tags.of(trail).add("Environment", "Production")
        cdk.Tags.of(trail).add("CostCenter", "IT-DR")

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs"""
        cdk.CfnOutput(
            self,
            "SourceBucketName",
            value=self.source_bucket.bucket_name,
            description="Name of the source S3 bucket",
            export_name=f"S3DrSourceBucket-{self.resource_suffix}",
        )

        cdk.CfnOutput(
            self,
            "ReplicaBucketName",
            value=self.replica_bucket.bucket_name,
            description="Name of the replica S3 bucket",
            export_name=f"S3DrReplicaBucket-{self.resource_suffix}",
        )

        cdk.CfnOutput(
            self,
            "ReplicationRoleArn",
            value=self.replication_role.role_arn,
            description="ARN of the replication IAM role",
            export_name=f"S3DrReplicationRole-{self.resource_suffix}",
        )

        cdk.CfnOutput(
            self,
            "AlertTopicArn",
            value=self.alert_topic.topic_arn,
            description="ARN of the SNS alert topic",
            export_name=f"S3DrAlertTopic-{self.resource_suffix}",
        )

        cdk.CfnOutput(
            self,
            "DashboardUrl",
            value=f"https://console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name=S3-DR-Dashboard-{self.resource_suffix}",
            description="URL to the CloudWatch dashboard",
        )


class S3DisasterRecoveryApp(cdk.App):
    """
    CDK Application for S3 Disaster Recovery Solution
    """

    def __init__(self):
        super().__init__()

        # Get configuration from context or environment
        primary_region = self.node.try_get_context("primary_region") or "us-east-1"
        secondary_region = self.node.try_get_context("secondary_region") or "us-west-2"
        notification_email = self.node.try_get_context("notification_email")

        # Create the main stack
        S3DisasterRecoveryStack(
            self,
            "S3DisasterRecoveryStack",
            primary_region=primary_region,
            secondary_region=secondary_region,
            notification_email=notification_email,
            env=Environment(
                account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
                region=os.environ.get("CDK_DEFAULT_REGION", primary_region),
            ),
            description="S3 Cross-Region Replication Disaster Recovery Solution",
        )


if __name__ == "__main__":
    app = S3DisasterRecoveryApp()
    app.synth()