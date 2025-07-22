#!/usr/bin/env python3
"""
CDK Python Application for GuardDuty Threat Detection

This application creates a comprehensive threat detection system using Amazon GuardDuty,
CloudWatch, SNS, and EventBridge for automated threat detection and alerting.

Author: AWS Recipes Team
Version: 1.0
"""

import os
from typing import Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    CfnOutput,
    RemovalPolicy,
    Duration,
    aws_guardduty as guardduty,
    aws_sns as sns,
    aws_sns_subscriptions as subscriptions,
    aws_events as events,
    aws_events_targets as targets,
    aws_cloudwatch as cloudwatch,
    aws_s3 as s3,
    aws_iam as iam,
)
from constructs import Construct


class GuardDutyThreatDetectionStack(Stack):
    """
    CDK Stack for GuardDuty Threat Detection System
    
    This stack creates:
    - Amazon GuardDuty detector with threat detection enabled
    - SNS topic for alert notifications with email subscription
    - EventBridge rule to route GuardDuty findings to SNS
    - CloudWatch dashboard for security monitoring
    - S3 bucket for findings export (optional)
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        notification_email: str,
        enable_s3_export: bool = True,
        finding_publishing_frequency: str = "FIFTEEN_MINUTES",
        **kwargs
    ) -> None:
        """
        Initialize the GuardDuty Threat Detection Stack
        
        Args:
            scope: CDK scope
            construct_id: Unique identifier for this construct
            notification_email: Email address for GuardDuty alerts
            enable_s3_export: Whether to enable S3 export for findings
            finding_publishing_frequency: How often to publish findings
            **kwargs: Additional arguments passed to Stack
        """
        super().__init__(scope, construct_id, **kwargs)

        # Store configuration
        self.notification_email = notification_email
        self.enable_s3_export = enable_s3_export
        self.finding_publishing_frequency = finding_publishing_frequency

        # Create GuardDuty detector
        self.guardduty_detector = self._create_guardduty_detector()

        # Create SNS topic and subscription for notifications
        self.sns_topic = self._create_sns_topic()
        self._create_email_subscription()

        # Create EventBridge rule to route GuardDuty findings
        self.eventbridge_rule = self._create_eventbridge_rule()

        # Create CloudWatch dashboard for monitoring
        self.dashboard = self._create_cloudwatch_dashboard()

        # Create S3 bucket for findings export (optional)
        if self.enable_s3_export:
            self.findings_bucket = self._create_s3_bucket()
            self._configure_findings_export()

        # Create stack outputs
        self._create_outputs()

    def _create_guardduty_detector(self) -> guardduty.CfnDetector:
        """
        Create and configure Amazon GuardDuty detector
        
        Returns:
            GuardDuty detector construct
        """
        detector = guardduty.CfnDetector(
            self,
            "GuardDutyDetector",
            enable=True,
            finding_publishing_frequency=self.finding_publishing_frequency,
            # Enable all data sources for comprehensive monitoring
            data_sources=guardduty.CfnDetector.CFNDataSourceConfigurationsProperty(
                s3_logs=guardduty.CfnDetector.CFNS3LogsConfigurationProperty(
                    enable=True
                ),
                kubernetes=guardduty.CfnDetector.CFNKubernetesConfigurationProperty(
                    audit_logs=guardduty.CfnDetector.CFNKubernetesAuditLogsConfigurationProperty(
                        enable=True
                    )
                ),
                malware_protection=guardduty.CfnDetector.CFNMalwareProtectionConfigurationProperty(
                    scan_ec2_instance_with_findings=guardduty.CfnDetector.CFNScanEc2InstanceWithFindingsConfigurationProperty(
                        ebs_volumes=True
                    )
                )
            )
        )

        # Add tags for resource management
        cdk.Tags.of(detector).add("Purpose", "ThreatDetection")
        cdk.Tags.of(detector).add("Service", "GuardDuty")

        return detector

    def _create_sns_topic(self) -> sns.Topic:
        """
        Create SNS topic for GuardDuty alert notifications
        
        Returns:
            SNS topic construct
        """
        topic = sns.Topic(
            self,
            "GuardDutyAlertsTopic",
            topic_name="guardduty-threat-alerts",
            display_name="GuardDuty Threat Detection Alerts",
            # Enable server-side encryption
            master_key=None,  # Use AWS managed key
        )

        # Add tags for resource management
        cdk.Tags.of(topic).add("Purpose", "ThreatDetection")
        cdk.Tags.of(topic).add("Service", "SNS")

        return topic

    def _create_email_subscription(self) -> None:
        """Create email subscription for SNS topic"""
        self.sns_topic.add_subscription(
            subscriptions.EmailSubscription(self.notification_email)
        )

    def _create_eventbridge_rule(self) -> events.Rule:
        """
        Create EventBridge rule to capture GuardDuty findings
        
        Returns:
            EventBridge rule construct
        """
        rule = events.Rule(
            self,
            "GuardDutyFindingsRule",
            rule_name="guardduty-findings-router",
            description="Route GuardDuty findings to SNS for notifications",
            event_pattern=events.EventPattern(
                source=["aws.guardduty"],
                detail_type=["GuardDuty Finding"]
            )
        )

        # Add SNS topic as target
        rule.add_target(
            targets.SnsTopic(
                self.sns_topic,
                message=events.RuleTargetInput.from_object({
                    "severity": events.EventField.from_path("$.detail.severity"),
                    "type": events.EventField.from_path("$.detail.type"),
                    "title": events.EventField.from_path("$.detail.title"),
                    "description": events.EventField.from_path("$.detail.description"),
                    "accountId": events.EventField.from_path("$.detail.accountId"),
                    "region": events.EventField.from_path("$.detail.region"),
                    "createdAt": events.EventField.from_path("$.detail.createdAt"),
                    "updatedAt": events.EventField.from_path("$.detail.updatedAt")
                })
            )
        )

        # Add tags for resource management
        cdk.Tags.of(rule).add("Purpose", "ThreatDetection")
        cdk.Tags.of(rule).add("Service", "EventBridge")

        return rule

    def _create_cloudwatch_dashboard(self) -> cloudwatch.Dashboard:
        """
        Create CloudWatch dashboard for security monitoring
        
        Returns:
            CloudWatch dashboard construct
        """
        dashboard = cloudwatch.Dashboard(
            self,
            "GuardDutyDashboard",
            dashboard_name="GuardDuty-Security-Monitoring",
            period_override=cloudwatch.PeriodOverride.AUTO,
            start="-PT1H",  # Show last hour by default
        )

        # Add GuardDuty findings count widget
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="GuardDuty Findings Count",
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/GuardDuty",
                        metric_name="FindingCount",
                        statistic="Sum",
                        period=Duration.minutes(5)
                    )
                ],
                width=12,
                height=6,
                period=Duration.minutes(5),
            )
        )

        # Add findings by severity widget
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Findings by Severity",
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/GuardDuty",
                        metric_name="FindingCount",
                        statistic="Sum",
                        period=Duration.minutes(15),
                        dimensions_map={"Severity": "High"}
                    ),
                    cloudwatch.Metric(
                        namespace="AWS/GuardDuty",
                        metric_name="FindingCount",
                        statistic="Sum",
                        period=Duration.minutes(15),
                        dimensions_map={"Severity": "Medium"}
                    ),
                    cloudwatch.Metric(
                        namespace="AWS/GuardDuty",
                        metric_name="FindingCount",
                        statistic="Sum",
                        period=Duration.minutes(15),
                        dimensions_map={"Severity": "Low"}
                    )
                ],
                width=12,
                height=6,
                period=Duration.minutes(15),
            )
        )

        # Add tags for resource management
        cdk.Tags.of(dashboard).add("Purpose", "ThreatDetection")
        cdk.Tags.of(dashboard).add("Service", "CloudWatch")

        return dashboard

    def _create_s3_bucket(self) -> s3.Bucket:
        """
        Create S3 bucket for GuardDuty findings export
        
        Returns:
            S3 bucket construct
        """
        bucket = s3.Bucket(
            self,
            "GuardDutyFindingsBucket",
            bucket_name=f"guardduty-findings-{self.account}-{self.region}",
            # Enable versioning for audit trail
            versioned=True,
            # Enable server-side encryption
            encryption=s3.BucketEncryption.S3_MANAGED,
            # Block public access
            public_read_access=False,
            public_write_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            # Lifecycle management
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="GuardDutyFindingsRetention",
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
                    ],
                    expiration=Duration.days(2555)  # 7 years retention
                )
            ],
            # Remove bucket when stack is deleted (for demo purposes)
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True
        )

        # Add tags for resource management
        cdk.Tags.of(bucket).add("Purpose", "ThreatDetection")
        cdk.Tags.of(bucket).add("Service", "S3")
        cdk.Tags.of(bucket).add("DataClassification", "SecurityFindings")

        return bucket

    def _configure_findings_export(self) -> None:
        """Configure GuardDuty to export findings to S3"""
        if not hasattr(self, 'findings_bucket'):
            return

        # Create IAM role for GuardDuty to write to S3
        guardduty_role = iam.Role(
            self,
            "GuardDutyS3ExportRole",
            assumed_by=iam.ServicePrincipal("guardduty.amazonaws.com"),
            inline_policies={
                "S3Export": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:PutObject",
                                "s3:GetBucketLocation"
                            ],
                            resources=[
                                self.findings_bucket.bucket_arn,
                                f"{self.findings_bucket.bucket_arn}/*"
                            ]
                        )
                    ]
                )
            }
        )

        # Configure publishing destination
        publishing_destination = guardduty.CfnPublishingDestination(
            self,
            "GuardDutyPublishingDestination",
            detector_id=self.guardduty_detector.ref,
            destination_type="S3",
            destination_properties=guardduty.CfnPublishingDestination.DestinationPropertiesProperty(
                destination_arn=self.findings_bucket.bucket_arn,
                kms_key_arn=""  # Use default encryption
            )
        )

        # Ensure the role is created before the publishing destination
        publishing_destination.node.add_dependency(guardduty_role)

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources"""
        CfnOutput(
            self,
            "GuardDutyDetectorId",
            description="GuardDuty Detector ID",
            value=self.guardduty_detector.ref
        )

        CfnOutput(
            self,
            "SNSTopicArn",
            description="SNS Topic ARN for GuardDuty alerts",
            value=self.sns_topic.topic_arn
        )

        CfnOutput(
            self,
            "EventBridgeRuleName",
            description="EventBridge Rule Name for GuardDuty findings",
            value=self.eventbridge_rule.rule_name
        )

        CfnOutput(
            self,
            "CloudWatchDashboardName",
            description="CloudWatch Dashboard Name for security monitoring",
            value=self.dashboard.dashboard_name
        )

        CfnOutput(
            self,
            "DashboardURL",
            description="CloudWatch Dashboard URL",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.dashboard.dashboard_name}"
        )

        if self.enable_s3_export and hasattr(self, 'findings_bucket'):
            CfnOutput(
                self,
                "FindingsBucketName",
                description="S3 Bucket Name for GuardDuty findings export",
                value=self.findings_bucket.bucket_name
            )


class GuardDutyThreatDetectionApp(cdk.App):
    """CDK Application for GuardDuty Threat Detection"""

    def __init__(self, **kwargs):
        super().__init__(**kwargs)

        # Get configuration from environment variables or context
        notification_email = self.node.try_get_context("notification_email") or os.environ.get("NOTIFICATION_EMAIL")
        enable_s3_export = self.node.try_get_context("enable_s3_export") != "false"
        finding_publishing_frequency = self.node.try_get_context("finding_publishing_frequency") or "FIFTEEN_MINUTES"

        if not notification_email:
            raise ValueError(
                "notification_email must be provided via context variable or NOTIFICATION_EMAIL environment variable"
            )

        # Create the main stack
        GuardDutyThreatDetectionStack(
            self,
            "GuardDutyThreatDetectionStack",
            notification_email=notification_email,
            enable_s3_export=enable_s3_export,
            finding_publishing_frequency=finding_publishing_frequency,
            description="Comprehensive threat detection system using Amazon GuardDuty, CloudWatch, SNS, and EventBridge"
        )


def main():
    """Main entry point for the CDK application"""
    app = GuardDutyThreatDetectionApp()
    
    # Add common tags to all resources
    cdk.Tags.of(app).add("Project", "GuardDutyThreatDetection")
    cdk.Tags.of(app).add("Environment", "Production")
    cdk.Tags.of(app).add("ManagedBy", "CDK")
    
    app.synth()


if __name__ == "__main__":
    main()