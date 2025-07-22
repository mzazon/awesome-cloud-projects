#!/usr/bin/env python3
"""
AWS CDK Python application for Identity Federation with AWS SSO.

This application creates a comprehensive identity federation solution using AWS IAM Identity Center
(successor to AWS SSO), AWS Organizations, and CloudTrail for audit logging. The solution
establishes centralized identity management that integrates with external identity providers
and enables single sign-on across multiple AWS accounts and applications.

Author: AWS CDK Python Generator
Version: 1.0
Recipe: Centralized Identity Federation
"""

import os
from typing import Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    App,
    Stack,
    StackProps,
    Environment,
    Tags,
    RemovalPolicy,
    Duration
)
from aws_cdk import aws_iam as iam
from aws_cdk import aws_organizations as organizations
from aws_cdk import aws_cloudtrail as cloudtrail
from aws_cdk import aws_s3 as s3
from aws_cdk import aws_logs as logs
from aws_cdk import aws_cloudwatch as cloudwatch
from aws_cdk import aws_ssm as ssm
from aws_cdk import aws_sns as sns
from aws_cdk import aws_kms as kms


class IdentityFederationStack(Stack):
    """
    AWS CDK Stack for Identity Federation with AWS SSO.
    
    This stack creates:
    - CloudTrail for audit logging
    - S3 bucket for CloudTrail logs
    - CloudWatch Log Group for audit logs
    - CloudWatch Dashboard for monitoring
    - SSM Document for disaster recovery
    - KMS key for encryption
    - SNS topic for alerts
    """

    def __init__(self, scope: App, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        random_suffix = self.node.addr[-6:].lower()
        
        # Environment variables
        aws_region = self.region
        aws_account_id = self.account

        # Create KMS key for encryption
        self.kms_key = self._create_kms_key()

        # Create SNS topic for alerts
        self.sns_topic = self._create_sns_topic(random_suffix)

        # Create S3 bucket for CloudTrail logs
        self.audit_bucket = self._create_audit_bucket(aws_account_id, random_suffix)

        # Create CloudTrail for audit logging
        self.cloudtrail = self._create_cloudtrail(random_suffix)

        # Create CloudWatch Log Group for SSO audit logs
        self.audit_log_group = self._create_audit_log_group()

        # Create CloudWatch Dashboard for monitoring
        self.dashboard = self._create_cloudwatch_dashboard(aws_region)

        # Create CloudWatch Alarms
        self.health_alarm = self._create_health_alarm(aws_region, aws_account_id)

        # Create SSM Document for disaster recovery
        self.dr_document = self._create_disaster_recovery_document()

        # Create IAM roles for Identity Center (placeholders)
        self._create_identity_center_roles()

        # Output important values
        self._create_outputs(random_suffix)

    def _create_kms_key(self) -> kms.Key:
        """Create KMS key for encryption."""
        return kms.Key(
            self, "IdentityFederationKMSKey",
            description="KMS key for Identity Federation resources",
            enable_key_rotation=True,
            removal_policy=RemovalPolicy.DESTROY
        )

    def _create_sns_topic(self, random_suffix: str) -> sns.Topic:
        """Create SNS topic for alerts."""
        return sns.Topic(
            self, "IdentityAlertsTopicaG",
            topic_name=f"identity-alerts-{random_suffix}",
            display_name="Identity Federation Alerts",
            kms_master_key=self.kms_key
        )

    def _create_audit_bucket(self, aws_account_id: str, random_suffix: str) -> s3.Bucket:
        """Create S3 bucket for CloudTrail audit logs."""
        bucket = s3.Bucket(
            self, "IdentityAuditLogsBucket",
            bucket_name=f"identity-audit-logs-{aws_account_id}-{random_suffix}",
            encryption=s3.BucketEncryption.KMS,
            encryption_key=self.kms_key,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            versioned=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteOldLogs",
                    enabled=True,
                    expiration=Duration.days(2555),  # 7 years
                    noncurrent_version_expiration=Duration.days(90)
                )
            ],
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True
        )

        # CloudTrail service principal policy
        cloudtrail_policy = iam.PolicyDocument(
            statements=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    principals=[iam.ServicePrincipal("cloudtrail.amazonaws.com")],
                    actions=["s3:PutObject"],
                    resources=[f"{bucket.bucket_arn}/*"],
                    conditions={
                        "StringEquals": {
                            "s3:x-amz-acl": "bucket-owner-full-control"
                        }
                    }
                ),
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    principals=[iam.ServicePrincipal("cloudtrail.amazonaws.com")],
                    actions=["s3:GetBucketAcl"],
                    resources=[bucket.bucket_arn]
                )
            ]
        )

        bucket.add_to_resource_policy(cloudtrail_policy.statements[0])
        bucket.add_to_resource_policy(cloudtrail_policy.statements[1])

        return bucket

    def _create_cloudtrail(self, random_suffix: str) -> cloudtrail.Trail:
        """Create CloudTrail for audit logging."""
        return cloudtrail.Trail(
            self, "IdentityFederationAuditTrail",
            trail_name=f"identity-federation-audit-trail-{random_suffix}",
            bucket=self.audit_bucket,
            include_global_service_events=True,
            is_multi_region_trail=True,
            enable_file_validation=True,
            kms_key=self.kms_key,
            send_to_cloud_watch_logs=True,
            cloud_watch_log_group=logs.LogGroup(
                self, "CloudTrailLogGroup",
                log_group_name=f"/aws/cloudtrail/identity-federation-{random_suffix}",
                retention=logs.RetentionDays.ONE_YEAR,
                encryption_key=self.kms_key,
                removal_policy=RemovalPolicy.DESTROY
            )
        )

    def _create_audit_log_group(self) -> logs.LogGroup:
        """Create CloudWatch Log Group for SSO audit logs."""
        return logs.LogGroup(
            self, "SSOAuditLogGroup",
            log_group_name="/aws/sso/audit-logs",
            retention=logs.RetentionDays.ONE_YEAR,
            encryption_key=self.kms_key,
            removal_policy=RemovalPolicy.DESTROY
        )

    def _create_cloudwatch_dashboard(self, aws_region: str) -> cloudwatch.Dashboard:
        """Create CloudWatch Dashboard for monitoring."""
        dashboard = cloudwatch.Dashboard(
            self, "IdentityFederationDashboard",
            dashboard_name="IdentityFederationDashboard"
        )

        # Sign-in metrics widget
        signin_widget = cloudwatch.GraphWidget(
            title="Identity Center Sign-in Metrics",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/SSO",
                    metric_name="SignInAttempts",
                    statistic="Sum",
                    period=Duration.minutes(5)
                ),
                cloudwatch.Metric(
                    namespace="AWS/SSO",
                    metric_name="SignInSuccesses",
                    statistic="Sum",
                    period=Duration.minutes(5)
                ),
                cloudwatch.Metric(
                    namespace="AWS/SSO",
                    metric_name="SignInFailures",
                    statistic="Sum",
                    period=Duration.minutes(5)
                )
            ],
            region=aws_region
        )

        # Log insights widget for IP analysis
        log_widget = cloudwatch.LogQueryWidget(
            title="Sign-in Activity by IP Address",
            log_groups=[self.audit_log_group],
            query_lines=[
                "fields @timestamp, eventName, sourceIPAddress, userIdentity.type",
                "filter eventName like /SignIn/",
                "stats count() by sourceIPAddress",
                "sort count desc"
            ],
            region=aws_region,
            width=12,
            height=6
        )

        dashboard.add_widgets(signin_widget)
        dashboard.add_widgets(log_widget)

        return dashboard

    def _create_health_alarm(self, aws_region: str, aws_account_id: str) -> cloudwatch.Alarm:
        """Create CloudWatch Alarm for service health monitoring."""
        return cloudwatch.Alarm(
            self, "IdentityFederationHealthAlarm",
            alarm_name="IdentityFederationHealthAlarm",
            alarm_description="Monitor Identity Center service health",
            metric=cloudwatch.Metric(
                namespace="AWS/SSO",
                metric_name="ServiceHealth",
                statistic="Average",
                period=Duration.minutes(5)
            ),
            threshold=1,
            comparison_operator=cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
            evaluation_periods=2,
            treat_missing_data=cloudwatch.TreatMissingData.BREACHING
        )

    def _create_disaster_recovery_document(self) -> ssm.CfnDocument:
        """Create SSM Document for disaster recovery procedures."""
        return ssm.CfnDocument(
            self, "IdentityFederationDisasterRecovery",
            name="IdentityFederationDisasterRecovery",
            document_type="Automation",
            document_format="YAML",
            content={
                "schemaVersion": "0.3",
                "description": "Disaster recovery procedures for Identity Federation",
                "parameters": {
                    "BackupRegion": {
                        "type": "String",
                        "description": "Region to restore from",
                        "default": "us-west-2"
                    }
                },
                "mainSteps": [
                    {
                        "name": "RestoreIdentityCenter",
                        "action": "aws:executeAwsApi",
                        "description": "Restore Identity Center instance from backup",
                        "inputs": {
                            "Service": "sso-admin",
                            "Api": "DescribeInstance",
                            "InstanceArn": "{{ BackupInstanceArn }}"
                        }
                    }
                ]
            }
        )

    def _create_identity_center_roles(self) -> None:
        """Create placeholder IAM roles for Identity Center permission sets."""
        # Developer role template
        developer_role = iam.Role(
            self, "DeveloperRoleTemplate",
            role_name="IdentityCenter-Developer-Template",
            assumed_by=iam.ServicePrincipal("sso.amazonaws.com"),
            description="Template for developer permission set",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("PowerUserAccess")
            ],
            inline_policies={
                "DeveloperRestrictions": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.DENY,
                            actions=[
                                "iam:*",
                                "organizations:*",
                                "account:*",
                                "billing:*",
                                "aws-portal:*"
                            ],
                            resources=["*"]
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "iam:GetRole",
                                "iam:GetRolePolicy",
                                "iam:ListRoles",
                                "iam:ListRolePolicies",
                                "iam:PassRole"
                            ],
                            resources=["*"],
                            conditions={
                                "StringLike": {
                                    "iam:PassedToService": [
                                        "lambda.amazonaws.com",
                                        "ec2.amazonaws.com",
                                        "ecs-tasks.amazonaws.com"
                                    ]
                                }
                            }
                        )
                    ]
                )
            }
        )

        # Read-only role template
        readonly_role = iam.Role(
            self, "ReadOnlyRoleTemplate",
            role_name="IdentityCenter-ReadOnly-Template",
            assumed_by=iam.ServicePrincipal("sso.amazonaws.com"),
            description="Template for read-only permission set",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("ReadOnlyAccess")
            ],
            inline_policies={
                "BusinessUserAccess": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:GetObject",
                                "s3:ListBucket",
                                "cloudwatch:GetMetricStatistics",
                                "cloudwatch:ListMetrics",
                                "logs:DescribeLogGroups",
                                "logs:DescribeLogStreams",
                                "logs:FilterLogEvents",
                                "quicksight:*"
                            ],
                            resources=["*"]
                        )
                    ]
                )
            }
        )

        # Administrator role template
        admin_role = iam.Role(
            self, "AdministratorRoleTemplate",
            role_name="IdentityCenter-Administrator-Template",
            assumed_by=iam.ServicePrincipal("sso.amazonaws.com"),
            description="Template for administrator permission set",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AdministratorAccess")
            ]
        )

    def _create_outputs(self, random_suffix: str) -> None:
        """Create CloudFormation outputs."""
        cdk.CfnOutput(
            self, "AuditBucketName",
            value=self.audit_bucket.bucket_name,
            description="S3 bucket for CloudTrail audit logs"
        )

        cdk.CfnOutput(
            self, "CloudTrailArn",
            value=self.cloudtrail.trail_arn,
            description="ARN of the CloudTrail for audit logging"
        )

        cdk.CfnOutput(
            self, "AuditLogGroupName",
            value=self.audit_log_group.log_group_name,
            description="CloudWatch Log Group for SSO audit logs"
        )

        cdk.CfnOutput(
            self, "DashboardURL",
            value=f"https://console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name=IdentityFederationDashboard",
            description="URL to the CloudWatch Dashboard"
        )

        cdk.CfnOutput(
            self, "SNSTopicArn",
            value=self.sns_topic.topic_arn,
            description="SNS topic for identity federation alerts"
        )

        cdk.CfnOutput(
            self, "KMSKeyId",
            value=self.kms_key.key_id,
            description="KMS key ID for encryption"
        )

        cdk.CfnOutput(
            self, "DisasterRecoveryDocument",
            value=self.dr_document.name or "IdentityFederationDisasterRecovery",
            description="SSM document for disaster recovery procedures"
        )


def main() -> None:
    """Main application entry point."""
    app = App()

    # Get environment configuration
    env = Environment(
        account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
        region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
    )

    # Create the Identity Federation stack
    identity_stack = IdentityFederationStack(
        app, "IdentityFederationStack",
        env=env,
        description="Identity Federation with AWS SSO - CDK Python Implementation"
    )

    # Add common tags
    Tags.of(identity_stack).add("Project", "IdentityFederation")
    Tags.of(identity_stack).add("Environment", "Production")
    Tags.of(identity_stack).add("ManagedBy", "CDK")
    Tags.of(identity_stack).add("Recipe", "identity-federation-aws-sso")

    app.synth()


if __name__ == "__main__":
    main()