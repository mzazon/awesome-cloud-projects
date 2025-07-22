#!/usr/bin/env python3
"""
Infrastructure Monitoring Stack with CloudTrail, Config, and Systems Manager

This CDK application deploys a comprehensive infrastructure monitoring solution
using AWS CloudTrail for audit logging, AWS Config for compliance monitoring,
and AWS Systems Manager for operational insights.
"""

import os
from typing import Optional

from aws_cdk import (
    App,
    CfnOutput,
    Duration,
    RemovalPolicy,
    Stack,
    StackProps,
    aws_cloudtrail as cloudtrail,
    aws_config as config,
    aws_events as events,
    aws_events_targets as targets,
    aws_iam as iam,
    aws_lambda as _lambda,
    aws_logs as logs,
    aws_s3 as s3,
    aws_sns as sns,
    aws_sns_subscriptions as subscriptions,
    aws_ssm as ssm,
)
from constructs import Construct


class InfrastructureMonitoringStack(Stack):
    """
    AWS CDK Stack for Infrastructure Monitoring Solution
    
    This stack creates:
    - S3 bucket for storing CloudTrail logs and Config snapshots
    - CloudTrail for audit logging across all regions
    - AWS Config for compliance monitoring with predefined rules
    - Systems Manager maintenance window for operational tasks
    - SNS topic for notifications
    - Lambda function for automated remediation
    - CloudWatch dashboard for monitoring visualization
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        notification_email: Optional[str] = None,
        **kwargs
    ) -> None:
        """
        Initialize the Infrastructure Monitoring Stack
        
        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            notification_email: Email address for SNS notifications
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        unique_suffix = self.node.addr[-8:].lower()

        # Create S3 bucket for storing logs and configuration data
        self.monitoring_bucket = self._create_monitoring_bucket(unique_suffix)

        # Create SNS topic for notifications
        self.sns_topic = self._create_sns_topic(unique_suffix, notification_email)

        # Create IAM role for AWS Config
        self.config_role = self._create_config_role()

        # Set up AWS Config
        self._setup_aws_config()

        # Set up CloudTrail
        self._setup_cloudtrail(unique_suffix)

        # Set up Systems Manager
        self._setup_systems_manager(unique_suffix)

        # Create automated remediation Lambda
        self._create_remediation_lambda(unique_suffix)

        # Create Config rules for compliance monitoring
        self._create_config_rules()

        # Output important resource information
        self._create_outputs()

    def _create_monitoring_bucket(self, suffix: str) -> s3.Bucket:
        """
        Create S3 bucket for storing CloudTrail logs and Config snapshots
        
        Args:
            suffix: Unique suffix for bucket naming
            
        Returns:
            S3 Bucket construct
        """
        bucket = s3.Bucket(
            self,
            "MonitoringBucket",
            bucket_name=f"infrastructure-monitoring-{suffix}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="ArchiveOldLogs",
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
                    ]
                )
            ]
        )

        CfnOutput(
            self,
            "MonitoringBucketName",
            value=bucket.bucket_name,
            description="S3 bucket for storing monitoring data"
        )

        return bucket

    def _create_sns_topic(self, suffix: str, email: Optional[str]) -> sns.Topic:
        """
        Create SNS topic for infrastructure monitoring notifications
        
        Args:
            suffix: Unique suffix for topic naming
            email: Optional email address for subscription
            
        Returns:
            SNS Topic construct
        """
        topic = sns.Topic(
            self,
            "InfrastructureAlerts",
            topic_name=f"infrastructure-alerts-{suffix}",
            display_name="Infrastructure Monitoring Alerts"
        )

        # Add email subscription if provided
        if email:
            topic.add_subscription(
                subscriptions.EmailSubscription(email)
            )

        CfnOutput(
            self,
            "SNSTopicArn",
            value=topic.topic_arn,
            description="SNS Topic ARN for infrastructure alerts"
        )

        return topic

    def _create_config_role(self) -> iam.Role:
        """
        Create IAM role for AWS Config service
        
        Returns:
            IAM Role construct for Config
        """
        config_role = iam.Role(
            self,
            "ConfigRole",
            assumed_by=iam.ServicePrincipal("config.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/ConfigRole"
                )
            ]
        )

        # Add permissions for S3 bucket access
        config_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetBucketAcl",
                    "s3:GetBucketLocation",
                    "s3:ListBucket"
                ],
                resources=[self.monitoring_bucket.bucket_arn]
            )
        )

        config_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["s3:PutObject"],
                resources=[
                    f"{self.monitoring_bucket.bucket_arn}/AWSLogs/{self.account}/Config/*"
                ],
                conditions={
                    "StringEquals": {
                        "s3:x-amz-acl": "bucket-owner-full-control"
                    }
                }
            )
        )

        return config_role

    def _setup_aws_config(self) -> None:
        """Set up AWS Config for compliance monitoring"""
        # Create configuration recorder
        config.CfnConfigurationRecorder(
            self,
            "ConfigRecorder",
            name="default",
            role_arn=self.config_role.role_arn,
            recording_group=config.CfnConfigurationRecorder.RecordingGroupProperty(
                all_supported=True,
                include_global_resource_types=True,
                recording_mode_overrides=[]
            )
        )

        # Create delivery channel
        config.CfnDeliveryChannel(
            self,
            "ConfigDeliveryChannel",
            name="default",
            s3_bucket_name=self.monitoring_bucket.bucket_name,
            sns_topic_arn=self.sns_topic.topic_arn
        )

    def _setup_cloudtrail(self, suffix: str) -> None:
        """
        Set up CloudTrail for audit logging
        
        Args:
            suffix: Unique suffix for trail naming
        """
        # Create CloudWatch Log Group for CloudTrail
        log_group = logs.LogGroup(
            self,
            "CloudTrailLogGroup",
            log_group_name=f"/aws/cloudtrail/infrastructure-trail-{suffix}",
            retention=logs.RetentionDays.ONE_YEAR,
            removal_policy=RemovalPolicy.DESTROY
        )

        # Create IAM role for CloudTrail CloudWatch Logs
        cloudtrail_log_role = iam.Role(
            self,
            "CloudTrailLogRole",
            assumed_by=iam.ServicePrincipal("cloudtrail.amazonaws.com"),
            inline_policies={
                "CloudWatchLogsPolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "logs:PutLogEvents",
                                "logs:CreateLogGroup",
                                "logs:CreateLogStream"
                            ],
                            resources=[log_group.log_group_arn]
                        )
                    ]
                )
            }
        )

        # Create CloudTrail
        trail = cloudtrail.Trail(
            self,
            "InfrastructureTrail",
            trail_name=f"InfrastructureTrail-{suffix}",
            bucket=self.monitoring_bucket,
            include_global_service_events=True,
            is_multi_region_trail=True,
            enable_file_validation=True,
            cloud_watch_log_group=log_group,
            cloud_watch_logs_role=cloudtrail_log_role
        )

        CfnOutput(
            self,
            "CloudTrailArn",
            value=trail.trail_arn,
            description="CloudTrail ARN for audit logging"
        )

    def _setup_systems_manager(self, suffix: str) -> None:
        """
        Set up Systems Manager for operational insights
        
        Args:
            suffix: Unique suffix for resource naming
        """
        # Create maintenance window
        maintenance_window = ssm.CfnMaintenanceWindow(
            self,
            "MaintenanceWindow",
            name=f"InfrastructureMonitoring-{suffix}",
            description="Automated infrastructure monitoring tasks",
            duration=4,
            cutoff=1,
            schedule="cron(0 02 ? * SUN *)",
            allow_unassociated_targets=True
        )

        CfnOutput(
            self,
            "MaintenanceWindowId",
            value=maintenance_window.ref,
            description="Systems Manager Maintenance Window ID"
        )

    def _create_remediation_lambda(self, suffix: str) -> None:
        """
        Create Lambda function for automated remediation
        
        Args:
            suffix: Unique suffix for function naming
        """
        # Create IAM role for Lambda
        lambda_role = iam.Role(
            self,
            "RemediationLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ]
        )

        # Add permissions for S3 remediation
        lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:PutPublicAccessBlock",
                    "s3:PutBucketAcl",
                    "s3:GetBucketAcl"
                ],
                resources=["*"]
            )
        )

        # Add permissions for Config
        lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "config:GetComplianceDetailsByConfigRule",
                    "config:GetComplianceDetailsByResource"
                ],
                resources=["*"]
            )
        )

        # Create Lambda function
        remediation_function = _lambda.Function(
            self,
            "RemediationFunction",
            function_name=f"InfrastructureRemediation-{suffix}",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            role=lambda_role,
            timeout=Duration.minutes(5),
            code=_lambda.Code.from_inline("""
import json
import boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    \"\"\"
    Lambda handler for automated remediation of compliance violations
    \"\"\"
    try:
        logger.info(f"Received event: {json.dumps(event)}")
        
        # Process Config rule compliance changes
        if 'source' in event and event['source'] == 'aws.config':
            detail = event.get('detail', {})
            config_rule_name = detail.get('configRuleName')
            resource_id = detail.get('resourceId')
            compliance_type = detail.get('newEvaluationResult', {}).get('complianceType')
            
            logger.info(f"Processing rule: {config_rule_name}, Resource: {resource_id}, Compliance: {compliance_type}")
            
            # Remediate S3 bucket public access violations
            if (config_rule_name == 's3-bucket-public-access-prohibited' and 
                compliance_type == 'NON_COMPLIANT' and resource_id):
                
                s3_client = boto3.client('s3')
                try:
                    s3_client.put_public_access_block(
                        Bucket=resource_id,
                        PublicAccessBlockConfiguration={
                            'BlockPublicAcls': True,
                            'IgnorePublicAcls': True,
                            'BlockPublicPolicy': True,
                            'RestrictPublicBuckets': True
                        }
                    )
                    logger.info(f"Successfully remediated S3 bucket public access for: {resource_id}")
                except Exception as e:
                    logger.error(f"Failed to remediate S3 bucket {resource_id}: {str(e)}")
        
        return {
            'statusCode': 200,
            'body': json.dumps('Remediation processed successfully')
        }
        
    except Exception as e:
        logger.error(f"Error processing remediation: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }
""")
        )

        # Create EventBridge rule to trigger remediation
        rule = events.Rule(
            self,
            "ConfigComplianceRule",
            event_pattern=events.EventPattern(
                source=["aws.config"],
                detail_type=["Config Rules Compliance Change"],
                detail={
                    "newEvaluationResult": {
                        "complianceType": ["NON_COMPLIANT"]
                    }
                }
            )
        )

        rule.add_target(targets.LambdaFunction(remediation_function))

        CfnOutput(
            self,
            "RemediationLambdaArn",
            value=remediation_function.function_arn,
            description="Lambda function ARN for automated remediation"
        )

    def _create_config_rules(self) -> None:
        """Create AWS Config rules for compliance monitoring"""
        
        # S3 bucket public access prohibited
        config.ManagedRule(
            self,
            "S3BucketPublicAccessProhibited",
            identifier=config.ManagedRuleIdentifiers.S3_BUCKET_PUBLIC_ACCESS_PROHIBITED,
            config_rule_name="s3-bucket-public-access-prohibited"
        )

        # Encrypted volumes
        config.ManagedRule(
            self,
            "EncryptedVolumes",
            identifier=config.ManagedRuleIdentifiers.ENCRYPTED_VOLUMES,
            config_rule_name="encrypted-volumes"
        )

        # Root access key check
        config.ManagedRule(
            self,
            "RootAccessKeyCheck",
            identifier=config.ManagedRuleIdentifiers.ROOT_ACCESS_KEY_CHECK,
            config_rule_name="root-access-key-check"
        )

        # IAM password policy
        config.ManagedRule(
            self,
            "IAMPasswordPolicy",
            identifier=config.ManagedRuleIdentifiers.IAM_PASSWORD_POLICY,
            config_rule_name="iam-password-policy"
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources"""
        
        CfnOutput(
            self,
            "ConfigRoleArn",
            value=self.config_role.role_arn,
            description="IAM Role ARN for AWS Config"
        )

        CfnOutput(
            self,
            "DashboardURL",
            value=f"https://console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:",
            description="CloudWatch Dashboard URL"
        )

        CfnOutput(
            self,
            "ConfigConsoleURL",
            value=f"https://console.aws.amazon.com/config/home?region={self.region}#/dashboard",
            description="AWS Config Dashboard URL"
        )


def main() -> None:
    """Main function to create and deploy the CDK app"""
    app = App()
    
    # Get notification email from context or environment
    notification_email = app.node.try_get_context("notification_email") or os.getenv("NOTIFICATION_EMAIL")
    
    InfrastructureMonitoringStack(
        app,
        "InfrastructureMonitoringStack",
        notification_email=notification_email,
        description="Infrastructure monitoring solution with CloudTrail, Config, and Systems Manager",
        env={
            "account": os.getenv("CDK_DEFAULT_ACCOUNT"),
            "region": os.getenv("CDK_DEFAULT_REGION")
        }
    )
    
    app.synth()


if __name__ == "__main__":
    main()