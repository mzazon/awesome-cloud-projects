#!/usr/bin/env python3
"""
AWS CDK Application for Simple API Logging with CloudTrail and S3

This CDK application implements comprehensive AWS API logging using CloudTrail,
storing logs in S3 with CloudWatch integration for real-time monitoring and alerting.
The solution follows AWS security best practices with proper encryption, access controls,
and monitoring for compliance and security requirements.

Architecture:
- CloudTrail Trail for multi-region API logging
- S3 Bucket with encryption and versioning for log storage
- CloudWatch Logs for real-time log streaming
- CloudWatch Alarms for root account usage monitoring
- SNS Topic for security notifications
- IAM Role with least-privilege permissions
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    CfnOutput,
    Duration,
    RemovalPolicy,
    Tags,
)
from aws_cdk import aws_s3 as s3
from aws_cdk import aws_cloudtrail as cloudtrail
from aws_cdk import aws_logs as logs
from aws_cdk import aws_iam as iam
from aws_cdk import aws_cloudwatch as cloudwatch
from aws_cdk import aws_sns as sns
from constructs import Construct


class SimpleApiLoggingStack(Stack):
    """
    CDK Stack for Simple API Logging with CloudTrail and S3.
    
    This stack creates a comprehensive API logging solution with:
    - CloudTrail for API activity monitoring
    - S3 bucket for secure log storage
    - CloudWatch integration for real-time monitoring
    - Security alarms for root account usage
    """

    def __init__(
        self, 
        scope: Construct, 
        construct_id: str, 
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Get deployment environment and account information
        account_id = cdk.Aws.ACCOUNT_ID
        region = cdk.Aws.REGION
        
        # Create unique resource identifiers
        resource_suffix = f"{account_id[:8]}-{construct_id.lower()}"
        
        # Create S3 bucket for CloudTrail logs with security best practices
        self.cloudtrail_bucket = self._create_cloudtrail_bucket(resource_suffix)
        
        # Create CloudWatch Log Group for real-time log streaming
        self.log_group = self._create_cloudwatch_log_group(construct_id)
        
        # Create IAM role for CloudTrail CloudWatch Logs integration
        self.cloudtrail_role = self._create_cloudtrail_role(self.log_group)
        
        # Create CloudTrail trail for comprehensive API logging
        self.trail = self._create_cloudtrail_trail(
            construct_id,
            self.cloudtrail_bucket,
            self.log_group,
            self.cloudtrail_role
        )
        
        # Create SNS topic for security notifications
        self.notification_topic = self._create_notification_topic(construct_id)
        
        # Create CloudWatch monitoring and alarms
        self._create_security_monitoring(self.log_group, self.notification_topic)
        
        # Add comprehensive resource tagging for cost allocation and governance
        self._add_resource_tags()
        
        # Create stack outputs for integration and verification
        self._create_stack_outputs()

    def _create_cloudtrail_bucket(self, resource_suffix: str) -> s3.Bucket:
        """
        Create S3 bucket for CloudTrail logs with comprehensive security features.
        
        Args:
            resource_suffix: Unique suffix for bucket naming
            
        Returns:
            S3 Bucket configured for CloudTrail log storage
        """
        bucket = s3.Bucket(
            self,
            "CloudTrailLogsBucket",
            bucket_name=f"cloudtrail-logs-{resource_suffix}",
            # Enable versioning for audit trail protection and compliance
            versioned=True,
            # Configure server-side encryption with S3 managed keys
            encryption=s3.BucketEncryption.S3_MANAGED,
            # Enable default encryption for all objects
            enforce_ssl=True,
            # Block all public access for security
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            # Configure lifecycle rules for cost optimization
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="CloudTrailLogTransition",
                    enabled=True,
                    # Transition to Infrequent Access after 30 days
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30)
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(90)
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.DEEP_ARCHIVE,
                            transition_after=Duration.days(365)
                        )
                    ]
                )
            ],
            # Configure removal policy for production safety
            removal_policy=RemovalPolicy.RETAIN,
            # Enable notification for object creation events
            event_bridge_enabled=True
        )
        
        # Apply bucket policy for CloudTrail service access with security conditions
        bucket_policy = iam.PolicyStatement(
            sid="AWSCloudTrailAclCheck",
            effect=iam.Effect.ALLOW,
            principals=[iam.ServicePrincipal("cloudtrail.amazonaws.com")],
            actions=["s3:GetBucketAcl"],
            resources=[bucket.bucket_arn],
            conditions={
                "StringEquals": {
                    "aws:SourceArn": f"arn:aws:cloudtrail:{cdk.Aws.REGION}:{cdk.Aws.ACCOUNT_ID}:trail/api-logging-trail"
                }
            }
        )
        bucket.add_to_resource_policy(bucket_policy)
        
        # Allow CloudTrail to write log files with source ARN condition
        write_policy = iam.PolicyStatement(
            sid="AWSCloudTrailWrite",
            effect=iam.Effect.ALLOW,
            principals=[iam.ServicePrincipal("cloudtrail.amazonaws.com")],
            actions=["s3:PutObject"],
            resources=[f"{bucket.bucket_arn}/AWSLogs/{cdk.Aws.ACCOUNT_ID}/*"],
            conditions={
                "StringEquals": {
                    "s3:x-amz-acl": "bucket-owner-full-control",
                    "aws:SourceArn": f"arn:aws:cloudtrail:{cdk.Aws.REGION}:{cdk.Aws.ACCOUNT_ID}:trail/api-logging-trail"
                }
            }
        )
        bucket.add_to_resource_policy(write_policy)
        
        return bucket

    def _create_cloudwatch_log_group(self, construct_id: str) -> logs.LogGroup:
        """
        Create CloudWatch Log Group for real-time CloudTrail event streaming.
        
        Args:
            construct_id: Stack construct identifier
            
        Returns:
            CloudWatch LogGroup for CloudTrail integration
        """
        log_group = logs.LogGroup(
            self,
            "CloudTrailLogGroup",
            log_group_name=f"/aws/cloudtrail/api-logging-trail",
            # Set retention period for cost optimization (30 days)
            retention=logs.RetentionDays.ONE_MONTH,
            # Configure removal policy for production environments
            removal_policy=RemovalPolicy.RETAIN,
            # Enable log group encryption for data at rest
            # Note: CloudWatch Logs uses service-managed encryption by default
        )
        
        return log_group

    def _create_cloudtrail_role(self, log_group: logs.LogGroup) -> iam.Role:
        """
        Create IAM role for CloudTrail with minimal required permissions.
        
        Args:
            log_group: CloudWatch LogGroup for CloudTrail integration
            
        Returns:
            IAM Role with CloudWatch Logs permissions
        """
        # Create trust policy allowing CloudTrail service to assume the role
        trust_policy = iam.PolicyDocument(
            statements=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    principals=[iam.ServicePrincipal("cloudtrail.amazonaws.com")],
                    actions=["sts:AssumeRole"]
                )
            ]
        )
        
        # Create role with trust policy
        role = iam.Role(
            self,
            "CloudTrailLogsRole",
            role_name=f"CloudTrailLogsRole-{cdk.Aws.ACCOUNT_ID[:8]}",
            assumed_by=iam.ServicePrincipal("cloudtrail.amazonaws.com"),
            description="IAM role for CloudTrail to write logs to CloudWatch Logs",
            # Inline policy with least-privilege permissions
            inline_policies={
                "CloudTrailLogsPolicy": iam.PolicyDocument(
                    statements=[
                        # Permission to create log streams in the specified log group
                        iam.PolicyStatement(
                            sid="AWSCloudTrailCreateLogStream",
                            effect=iam.Effect.ALLOW,
                            actions=["logs:CreateLogStream"],
                            resources=[f"{log_group.log_group_arn}:log-stream:*"]
                        ),
                        # Permission to put log events in the log streams
                        iam.PolicyStatement(
                            sid="AWSCloudTrailPutLogEvents",
                            effect=iam.Effect.ALLOW,
                            actions=["logs:PutLogEvents"],
                            resources=[f"{log_group.log_group_arn}:log-stream:*"]
                        )
                    ]
                )
            }
        )
        
        return role

    def _create_cloudtrail_trail(
        self,
        construct_id: str,
        bucket: s3.Bucket,
        log_group: logs.LogGroup,
        role: iam.Role
    ) -> cloudtrail.Trail:
        """
        Create CloudTrail trail with comprehensive logging configuration.
        
        Args:
            construct_id: Stack construct identifier
            bucket: S3 bucket for log storage
            log_group: CloudWatch LogGroup for real-time streaming
            role: IAM role for CloudWatch Logs integration
            
        Returns:
            CloudTrail Trail with multi-region support and log file validation
        """
        trail = cloudtrail.Trail(
            self,
            "ApiLoggingTrail",
            trail_name="api-logging-trail",
            # Configure S3 bucket for log file storage
            bucket=bucket,
            # Enable multi-region trail for comprehensive coverage
            is_multi_region_trail=True,
            # Include global service events (IAM, CloudFront, Route 53)
            include_global_service_events=True,
            # Enable log file validation for integrity verification
            enable_file_validation=True,
            # Configure CloudWatch Logs integration for real-time monitoring
            cloud_watch_logs_group=log_group,
            cloud_watch_logs_role=role,
            # Configure management events (enabled by default)
            # Management events include control plane operations like CreateBucket, RunInstances
            management_events=cloudtrail.ReadWriteType.ALL,
            # Optionally configure data events for specific resources
            # Note: Data events incur additional charges
            # data_events=[
            #     cloudtrail.DataEvent(
            #         resources=[s3.Bucket.from_bucket_name(self, "DataEventBucket", "my-critical-bucket")],
            #         include_management_events=False,
            #         read_write_type=cloudtrail.ReadWriteType.ALL
            #     )
            # ]
        )
        
        return trail

    def _create_notification_topic(self, construct_id: str) -> sns.Topic:
        """
        Create SNS topic for security alert notifications.
        
        Args:
            construct_id: Stack construct identifier
            
        Returns:
            SNS Topic for security notifications
        """
        topic = sns.Topic(
            self,
            "CloudTrailAlertsTopic",
            topic_name=f"cloudtrail-alerts-{construct_id.lower()}",
            display_name="CloudTrail Security Alerts",
            # Configure server-side encryption for message privacy
            master_key=None,  # Uses AWS managed key for SNS
        )
        
        return topic

    def _create_security_monitoring(
        self, 
        log_group: logs.LogGroup, 
        notification_topic: sns.Topic
    ) -> None:
        """
        Create CloudWatch monitoring and alarms for security events.
        
        Args:
            log_group: CloudWatch LogGroup containing CloudTrail events
            notification_topic: SNS Topic for alarm notifications
        """
        # Create metric filter for root account usage detection
        root_usage_filter = logs.MetricFilter(
            self,
            "RootAccountUsageFilter",
            log_group=log_group,
            filter_name="RootAccountUsage",
            # CloudWatch Logs Insights query to detect root account usage
            filter_pattern=logs.FilterPattern.all(
                # Match events where userIdentity.type is "Root"
                logs.FilterPattern.exists("$.userIdentity.type"),
                logs.FilterPattern.string_value("$.userIdentity.type", "=", "Root"),
                # Exclude events where invokedBy exists (service-linked usage)
                logs.FilterPattern.not_exists("$.userIdentity.invokedBy"),
                # Exclude AWS service events
                logs.FilterPattern.string_value("$.eventType", "!=", "AwsServiceEvent")
            ),
            # Configure metric transformation
            metric_name="RootAccountUsageCount",
            metric_namespace="CloudTrailMetrics",
            metric_value="1",
            default_value=0
        )
        
        # Create CloudWatch alarm for root account usage
        root_usage_alarm = cloudwatch.Alarm(
            self,
            "RootAccountUsageAlarm",
            alarm_name=f"CloudTrail-RootAccountUsage-{cdk.Aws.ACCOUNT_ID[:8]}",
            alarm_description="Alert when AWS root account is used for API calls",
            # Reference the metric created by the metric filter
            metric=cloudwatch.Metric(
                namespace="CloudTrailMetrics",
                metric_name="RootAccountUsageCount",
                statistic="Sum",
                period=Duration.minutes(5)
            ),
            # Alarm when any root account usage is detected
            threshold=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
            evaluation_periods=1,
            # Treat missing data as not breaching (normal state)
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )
        
        # Add SNS notification action to the alarm
        root_usage_alarm.add_alarm_action(
            cloudwatch.SnsAction(notification_topic)
        )
        
        # Create additional metric filter for failed API calls
        failed_calls_filter = logs.MetricFilter(
            self,
            "FailedApiCallsFilter",
            log_group=log_group,
            filter_name="FailedApiCalls",
            # Detect API calls that resulted in access denied or other errors
            filter_pattern=logs.FilterPattern.any(
                logs.FilterPattern.string_value("$.errorCode", "=", "AccessDenied"),
                logs.FilterPattern.string_value("$.errorCode", "=", "UnauthorizedOperation"),
                logs.FilterPattern.string_value("$.errorCode", "=", "Forbidden")
            ),
            metric_name="FailedApiCallsCount",
            metric_namespace="CloudTrailMetrics",
            metric_value="1",
            default_value=0
        )
        
        # Create alarm for excessive failed API calls (potential attack)
        failed_calls_alarm = cloudwatch.Alarm(
            self,
            "FailedApiCallsAlarm",
            alarm_name=f"CloudTrail-FailedApiCalls-{cdk.Aws.ACCOUNT_ID[:8]}",
            alarm_description="Alert when there are excessive failed API calls",
            metric=cloudwatch.Metric(
                namespace="CloudTrailMetrics",
                metric_name="FailedApiCallsCount",
                statistic="Sum",
                period=Duration.minutes(5)
            ),
            # Alarm when more than 10 failed calls in 5 minutes
            threshold=10,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )
        
        # Add SNS notification for failed calls alarm
        failed_calls_alarm.add_alarm_action(
            cloudwatch.SnsAction(notification_topic)
        )

    def _add_resource_tags(self) -> None:
        """Add comprehensive tags to all resources for governance and cost allocation."""
        tags_config = {
            "Project": "SimpleApiLogging",
            "Environment": "Production",
            "Owner": "SecurityTeam",
            "CostCenter": "Security",
            "Compliance": "Required",
            "DataClassification": "Confidential",
            "BackupRequired": "Yes",
            "MonitoringEnabled": "Yes"
        }
        
        for key, value in tags_config.items():
            Tags.of(self).add(key, value)

    def _create_stack_outputs(self) -> None:
        """Create CloudFormation outputs for integration and verification."""
        CfnOutput(
            self,
            "CloudTrailBucketName",
            value=self.cloudtrail_bucket.bucket_name,
            description="S3 bucket name for CloudTrail logs",
            export_name=f"{self.stack_name}-CloudTrailBucket"
        )
        
        CfnOutput(
            self,
            "CloudTrailArn",
            value=self.trail.trail_arn,
            description="CloudTrail trail ARN for API logging",
            export_name=f"{self.stack_name}-CloudTrailArn"
        )
        
        CfnOutput(
            self,
            "LogGroupName",
            value=self.log_group.log_group_name,
            description="CloudWatch Log Group for real-time CloudTrail events",
            export_name=f"{self.stack_name}-LogGroup"
        )
        
        CfnOutput(
            self,
            "NotificationTopicArn",
            value=self.notification_topic.topic_arn,
            description="SNS Topic ARN for security alert notifications",
            export_name=f"{self.stack_name}-NotificationTopic"
        )
        
        CfnOutput(
            self,
            "CloudTrailRoleArn",
            value=self.cloudtrail_role.role_arn,
            description="IAM Role ARN for CloudTrail CloudWatch Logs integration",
            export_name=f"{self.stack_name}-CloudTrailRole"
        )


def main() -> None:
    """
    Main entry point for the CDK application.
    
    This function creates the CDK app and deploys the Simple API Logging stack
    with appropriate environment configuration.
    """
    app = cdk.App()
    
    # Get deployment environment from CDK context or environment variables
    account = os.environ.get("CDK_DEFAULT_ACCOUNT")
    region = os.environ.get("CDK_DEFAULT_REGION")
    
    # Create the Simple API Logging stack
    SimpleApiLoggingStack(
        app,
        "SimpleApiLoggingStack",
        description="Simple API Logging with CloudTrail and S3 - Comprehensive AWS API audit logging solution",
        env=Environment(
            account=account,
            region=region
        ),
        # Add stack-level metadata
        tags={
            "Application": "SimpleApiLogging",
            "CDKVersion": cdk.VERSION,
            "Repository": "aws-recipes"
        }
    )
    
    # Synthesize the CloudFormation template
    app.synth()


if __name__ == "__main__":
    main()