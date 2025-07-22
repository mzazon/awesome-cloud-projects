#!/usr/bin/env python3
"""
CDK Python application for Multi-Factor Authentication with AWS IAM and MFA Devices

This application creates:
- IAM users and groups for MFA testing
- MFA enforcement policies with conditional access
- CloudWatch monitoring and alerting for MFA compliance
- CloudTrail integration for security auditing

Author: AWS CDK Team
Version: 1.0
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    StackProps,
    CfnOutput,
    Tags,
    RemovalPolicy,
    Duration,
)
from aws_cdk import aws_iam as iam
from aws_cdk import aws_cloudwatch as cloudwatch
from aws_cdk import aws_logs as logs
from aws_cdk import aws_cloudtrail as cloudtrail
from aws_cdk import aws_s3 as s3
from constructs import Construct


class MfaIamStack(Stack):
    """
    CDK Stack for implementing Multi-Factor Authentication with AWS IAM.
    
    This stack creates comprehensive MFA enforcement including:
    - IAM users, groups, and policies for MFA testing
    - CloudWatch monitoring and alerting
    - CloudTrail logging for security auditing
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Stack configuration
        self.project_name = "mfa-iam-security"
        
        # Create CloudTrail bucket first
        self.cloudtrail_bucket = self._create_cloudtrail_bucket()
        
        # Create CloudTrail for audit logging
        self.cloudtrail = self._create_cloudtrail()
        
        # Create IAM resources
        self.test_user = self._create_test_user()
        self.admin_group = self._create_admin_group()
        self.mfa_policy = self._create_mfa_enforcement_policy()
        
        # Attach policy to group and add user to group
        self._configure_group_membership()
        
        # Create monitoring resources
        self.log_group = self._create_log_group()
        self.metric_filters = self._create_metric_filters()
        self.dashboard = self._create_cloudwatch_dashboard()
        self.alarms = self._create_cloudwatch_alarms()
        
        # Add stack outputs
        self._create_outputs()
        
        # Apply tags to all resources
        self._apply_tags()

    def _create_cloudtrail_bucket(self) -> s3.Bucket:
        """Create S3 bucket for CloudTrail logs with security best practices."""
        bucket = s3.Bucket(
            self, "CloudTrailBucket",
            bucket_name=f"{self.project_name}-cloudtrail-{self.account}-{self.region}",
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            versioned=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteOldVersions",
                    enabled=True,
                    noncurrent_version_expiration=Duration.days(30)
                )
            ]
        )
        
        # Add bucket policy for CloudTrail
        bucket.add_to_resource_policy(
            iam.PolicyStatement(
                sid="AWSCloudTrailAclCheck",
                effect=iam.Effect.ALLOW,
                principals=[iam.ServicePrincipal("cloudtrail.amazonaws.com")],
                actions=["s3:GetBucketAcl"],
                resources=[bucket.bucket_arn],
                conditions={
                    "StringEquals": {
                        "AWS:SourceArn": f"arn:aws:cloudtrail:{self.region}:{self.account}:trail/{self.project_name}-trail"
                    }
                }
            )
        )
        
        bucket.add_to_resource_policy(
            iam.PolicyStatement(
                sid="AWSCloudTrailWrite",
                effect=iam.Effect.ALLOW,
                principals=[iam.ServicePrincipal("cloudtrail.amazonaws.com")],
                actions=["s3:PutObject"],
                resources=[f"{bucket.bucket_arn}/*"],
                conditions={
                    "StringEquals": {
                        "s3:x-amz-acl": "bucket-owner-full-control",
                        "AWS:SourceArn": f"arn:aws:cloudtrail:{self.region}:{self.account}:trail/{self.project_name}-trail"
                    }
                }
            )
        )
        
        return bucket

    def _create_cloudtrail(self) -> cloudtrail.Trail:
        """Create CloudTrail for comprehensive audit logging."""
        trail = cloudtrail.Trail(
            self, "MfaAuditTrail",
            trail_name=f"{self.project_name}-trail",
            bucket=self.cloudtrail_bucket,
            include_global_service_events=True,
            is_multi_region_trail=True,
            enable_file_validation=True,
            send_to_cloud_watch_logs=True,
            cloud_watch_logs_retention=logs.RetentionDays.ONE_MONTH
        )
        
        # Add event selectors for IAM and authentication events
        trail.add_event_selector(
            read_write_type=cloudtrail.ReadWriteType.ALL,
            include_management_events=True,
            data_resources=[
                {
                    "type": "AWS::IAM::User",
                    "values": ["arn:aws:iam::*:user/*"]
                },
                {
                    "type": "AWS::IAM::Group", 
                    "values": ["arn:aws:iam::*:group/*"]
                },
                {
                    "type": "AWS::IAM::Policy",
                    "values": ["arn:aws:iam::*:policy/*"]
                }
            ]
        )
        
        return trail

    def _create_test_user(self) -> iam.User:
        """Create test user for MFA demonstration."""
        user = iam.User(
            self, "TestUser",
            user_name=f"test-user-{self.project_name}",
            password=cdk.SecretValue.unsafe_plain_text("TempPassword123!"),
            password_reset_required=True,
            path="/mfa-demo/"
        )
        
        return user

    def _create_admin_group(self) -> iam.Group:
        """Create administrative group for MFA users."""
        group = iam.Group(
            self, "MfaAdminGroup",
            group_name=f"MFAAdmins-{self.project_name}",
            path="/mfa-demo/"
        )
        
        return group

    def _create_mfa_enforcement_policy(self) -> iam.ManagedPolicy:
        """
        Create comprehensive MFA enforcement policy.
        
        This policy enforces MFA by:
        1. Allowing basic account information viewing
        2. Allowing users to manage their own passwords and MFA devices
        3. Denying all other actions unless MFA is present
        4. Allowing full access when MFA is authenticated
        """
        policy_document = iam.PolicyDocument(
            statements=[
                # Allow viewing account information
                iam.PolicyStatement(
                    sid="AllowViewAccountInfo",
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "iam:GetAccountPasswordPolicy",
                        "iam:ListVirtualMFADevices",
                        "iam:GetUser",
                        "iam:ListUsers"
                    ],
                    resources=["*"]
                ),
                
                # Allow managing own passwords
                iam.PolicyStatement(
                    sid="AllowManageOwnPasswords",
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "iam:ChangePassword",
                        "iam:GetUser"
                    ],
                    resources=[
                        "arn:aws:iam::*:user/${aws:username}"
                    ]
                ),
                
                # Allow managing own MFA devices
                iam.PolicyStatement(
                    sid="AllowManageOwnMFA",
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "iam:CreateVirtualMFADevice",
                        "iam:DeleteVirtualMFADevice",
                        "iam:EnableMFADevice",
                        "iam:DeactivateMFADevice",
                        "iam:ListMFADevices",
                        "iam:ResyncMFADevice"
                    ],
                    resources=[
                        "arn:aws:iam::*:mfa/${aws:username}",
                        "arn:aws:iam::*:user/${aws:username}"
                    ]
                ),
                
                # Deny all except essential actions unless MFA is present
                iam.PolicyStatement(
                    sid="DenyAllExceptUnlessMFAAuthenticated",
                    effect=iam.Effect.DENY,
                    not_actions=[
                        "iam:CreateVirtualMFADevice",
                        "iam:EnableMFADevice",
                        "iam:GetUser",
                        "iam:ListMFADevices",
                        "iam:ListVirtualMFADevices",
                        "iam:ResyncMFADevice",
                        "sts:GetSessionToken",
                        "iam:ChangePassword",
                        "iam:GetAccountPasswordPolicy"
                    ],
                    resources=["*"],
                    conditions={
                        "BoolIfExists": {
                            "aws:MultiFactorAuthPresent": "false"
                        }
                    }
                ),
                
                # Allow full access when MFA is present
                iam.PolicyStatement(
                    sid="AllowFullAccessWithMFA",
                    effect=iam.Effect.ALLOW,
                    actions=["*"],
                    resources=["*"],
                    conditions={
                        "Bool": {
                            "aws:MultiFactorAuthPresent": "true"
                        }
                    }
                )
            ]
        )
        
        policy = iam.ManagedPolicy(
            self, "MfaEnforcementPolicy",
            managed_policy_name=f"EnforceMFA-{self.project_name}",
            description="Enforce MFA for all AWS access with granular permissions",
            document=policy_document,
            path="/mfa-demo/"
        )
        
        return policy

    def _configure_group_membership(self) -> None:
        """Configure group membership and policy attachments."""
        # Add user to group
        self.admin_group.add_user(self.test_user)
        
        # Attach MFA policy to group
        self.admin_group.add_managed_policy(self.mfa_policy)

    def _create_log_group(self) -> logs.LogGroup:
        """Create CloudWatch Log Group for MFA monitoring."""
        log_group = logs.LogGroup(
            self, "MfaLogGroup",
            log_group_name=f"/aws/mfa/{self.project_name}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY
        )
        
        return log_group

    def _create_metric_filters(self) -> Dict[str, logs.MetricFilter]:
        """Create CloudWatch metric filters for MFA monitoring."""
        metric_filters = {}
        
        # MFA login success filter
        metric_filters["mfa_logins"] = logs.MetricFilter(
            self, "MfaLoginFilter",
            log_group=self.cloudtrail.log_group,
            metric_namespace="AWS/Security/MFA",
            metric_name="MFALoginCount",
            metric_value="1",
            filter_pattern=logs.FilterPattern.all(
                logs.FilterPattern.literal('{ ($.eventName = "ConsoleLogin") && ($.responseElements.ConsoleLogin = "Success") && ($.additionalEventData.MFAUsed = "Yes") }')
            )
        )
        
        # Non-MFA login filter
        metric_filters["non_mfa_logins"] = logs.MetricFilter(
            self, "NonMfaLoginFilter",
            log_group=self.cloudtrail.log_group,
            metric_namespace="AWS/Security/MFA",
            metric_name="NonMFALoginCount",
            metric_value="1",
            filter_pattern=logs.FilterPattern.all(
                logs.FilterPattern.literal('{ ($.eventName = "ConsoleLogin") && ($.responseElements.ConsoleLogin = "Success") && ($.additionalEventData.MFAUsed = "No") }')
            )
        )
        
        # Failed login attempts
        metric_filters["failed_logins"] = logs.MetricFilter(
            self, "FailedLoginFilter",
            log_group=self.cloudtrail.log_group,
            metric_namespace="AWS/Security/MFA",
            metric_name="FailedLoginCount",
            metric_value="1",
            filter_pattern=logs.FilterPattern.all(
                logs.FilterPattern.literal('{ ($.eventName = "ConsoleLogin") && ($.responseElements.ConsoleLogin = "Failure") }')
            )
        )
        
        return metric_filters

    def _create_cloudwatch_dashboard(self) -> cloudwatch.Dashboard:
        """Create CloudWatch dashboard for MFA monitoring."""
        dashboard = cloudwatch.Dashboard(
            self, "MfaDashboard",
            dashboard_name=f"MFA-Security-Dashboard-{self.project_name}"
        )
        
        # MFA vs Non-MFA logins widget
        login_comparison_widget = cloudwatch.GraphWidget(
            title="MFA vs Non-MFA Console Logins",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/Security/MFA",
                    metric_name="MFALoginCount",
                    statistic="Sum",
                    period=Duration.minutes(5)
                ),
                cloudwatch.Metric(
                    namespace="AWS/Security/MFA", 
                    metric_name="NonMFALoginCount",
                    statistic="Sum",
                    period=Duration.minutes(5)
                )
            ],
            width=12,
            height=6
        )
        
        # Failed login attempts widget
        failed_logins_widget = cloudwatch.GraphWidget(
            title="Failed Login Attempts",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/Security/MFA",
                    metric_name="FailedLoginCount",
                    statistic="Sum",
                    period=Duration.minutes(5)
                )
            ],
            width=12,
            height=6
        )
        
        # MFA compliance widget (percentage)
        mfa_compliance_widget = cloudwatch.GraphWidget(
            title="MFA Compliance Rate",
            left=[
                cloudwatch.MathExpression(
                    expression="(mfa_logins / (mfa_logins + non_mfa_logins)) * 100",
                    using_metrics={
                        "mfa_logins": cloudwatch.Metric(
                            namespace="AWS/Security/MFA",
                            metric_name="MFALoginCount",
                            statistic="Sum"
                        ),
                        "non_mfa_logins": cloudwatch.Metric(
                            namespace="AWS/Security/MFA",
                            metric_name="NonMFALoginCount",
                            statistic="Sum"
                        )
                    },
                    label="MFA Compliance %"
                )
            ],
            width=12,
            height=6,
            left_y_axis=cloudwatch.YAxisProps(
                min=0,
                max=100
            )
        )
        
        dashboard.add_widgets(login_comparison_widget)
        dashboard.add_widgets(failed_logins_widget)
        dashboard.add_widgets(mfa_compliance_widget)
        
        return dashboard

    def _create_cloudwatch_alarms(self) -> Dict[str, cloudwatch.Alarm]:
        """Create CloudWatch alarms for MFA security monitoring."""
        alarms = {}
        
        # Alarm for non-MFA console logins
        alarms["non_mfa_logins"] = cloudwatch.Alarm(
            self, "NonMfaLoginAlarm",
            alarm_name=f"Non-MFA-Console-Logins-{self.project_name}",
            alarm_description="Alert when users login to console without MFA",
            metric=cloudwatch.Metric(
                namespace="AWS/Security/MFA",
                metric_name="NonMFALoginCount",
                statistic="Sum",
                period=Duration.minutes(5)
            ),
            threshold=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
            evaluation_periods=1,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        
        # Alarm for multiple failed login attempts
        alarms["failed_logins"] = cloudwatch.Alarm(
            self, "FailedLoginAlarm",
            alarm_name=f"Multiple-Failed-Logins-{self.project_name}",
            alarm_description="Alert on multiple failed login attempts (potential brute force)",
            metric=cloudwatch.Metric(
                namespace="AWS/Security/MFA",
                metric_name="FailedLoginCount",
                statistic="Sum",
                period=Duration.minutes(5)
            ),
            threshold=3,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
            evaluation_periods=1,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        
        # Alarm for low MFA compliance
        alarms["low_mfa_compliance"] = cloudwatch.Alarm(
            self, "LowMfaComplianceAlarm", 
            alarm_name=f"Low-MFA-Compliance-{self.project_name}",
            alarm_description="Alert when MFA compliance drops below 90%",
            metric=cloudwatch.MathExpression(
                expression="(mfa_logins / (mfa_logins + non_mfa_logins)) * 100",
                using_metrics={
                    "mfa_logins": cloudwatch.Metric(
                        namespace="AWS/Security/MFA",
                        metric_name="MFALoginCount",
                        statistic="Sum",
                        period=Duration.hours(1)
                    ),
                    "non_mfa_logins": cloudwatch.Metric(
                        namespace="AWS/Security/MFA",
                        metric_name="NonMFALoginCount", 
                        statistic="Sum",
                        period=Duration.hours(1)
                    )
                }
            ),
            threshold=90,
            comparison_operator=cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
            evaluation_periods=1,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        
        return alarms

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information."""
        CfnOutput(
            self, "TestUserName",
            description="Name of the test user for MFA demonstration",
            value=self.test_user.user_name
        )
        
        CfnOutput(
            self, "TestUserConsoleUrl",
            description="Console login URL for test user",
            value=f"https://{self.account}.signin.aws.amazon.com/console"
        )
        
        CfnOutput(
            self, "AdminGroupName",
            description="Name of the admin group with MFA enforcement",
            value=self.admin_group.group_name
        )
        
        CfnOutput(
            self, "MfaPolicyArn",
            description="ARN of the MFA enforcement policy",
            value=self.mfa_policy.managed_policy_arn
        )
        
        CfnOutput(
            self, "CloudTrailArn",
            description="ARN of the CloudTrail for audit logging",
            value=self.cloudtrail.trail_arn
        )
        
        CfnOutput(
            self, "DashboardUrl",
            description="URL to the MFA monitoring dashboard",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.dashboard.dashboard_name}"
        )
        
        CfnOutput(
            self, "SetupInstructions",
            description="Instructions for setting up MFA",
            value="1. Login with test user, 2. Navigate to IAM > Users > Security Credentials, 3. Add MFA device, 4. Test access with MFA"
        )

    def _apply_tags(self) -> None:
        """Apply tags to all resources in the stack."""
        Tags.of(self).add("Project", self.project_name)
        Tags.of(self).add("Purpose", "MFA-Security-Demo")
        Tags.of(self).add("Environment", "Demo")
        Tags.of(self).add("CostCenter", "Security")
        Tags.of(self).add("Owner", "SecurityTeam")


def main() -> None:
    """Main function to create and deploy the CDK application."""
    app = cdk.App()
    
    # Get configuration from environment or context
    env = cdk.Environment(
        account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
        region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
    )
    
    # Create the MFA IAM stack
    MfaIamStack(
        app, "MfaIamStack",
        env=env,
        description="Multi-Factor Authentication implementation with AWS IAM and comprehensive monitoring"
    )
    
    app.synth()


if __name__ == "__main__":
    main()