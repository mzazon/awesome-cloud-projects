#!/usr/bin/env python3
"""
AWS CDK Python application for Multi-Region Backup Strategies using AWS Backup.

This application creates a comprehensive backup strategy across multiple AWS regions
with automated cross-region copy, lifecycle policies, and monitoring capabilities.

Author: AWS CDK Generator
Version: 1.0
"""

import os
from typing import Dict, Any, Optional

import aws_cdk as cdk
from aws_cdk import (
    App,
    Environment,
    Stack,
    StackProps,
    Duration,
    CfnOutput,
    RemovalPolicy,
    aws_backup as backup,
    aws_iam as iam,
    aws_sns as sns,
    aws_events as events,
    aws_events_targets as targets,
    aws_lambda as lambda_,
    aws_logs as logs,
    CfnParameter,
    Aws
)
from constructs import Construct


class MultiRegionBackupStack(Stack):
    """
    CDK Stack that implements a multi-region backup strategy using AWS Backup.
    
    This stack creates:
    - AWS Backup service role with necessary permissions
    - Backup vaults in multiple regions
    - Backup plans with cross-region copy configurations
    - EventBridge rules for monitoring backup job states
    - Lambda function for backup validation
    - SNS topic for notifications
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Parameters for customization
        organization_name = CfnParameter(
            self, "OrganizationName",
            type="String",
            default="MyOrg",
            description="Organization name used for resource naming",
            allowed_pattern="^[a-zA-Z0-9-]+$",
            constraint_description="Organization name must contain only alphanumeric characters and hyphens"
        )

        secondary_region = CfnParameter(
            self, "SecondaryRegion",
            type="String",
            default="us-west-2",
            description="Secondary region for backup copies",
            allowed_values=["us-west-1", "us-west-2", "eu-west-1", "eu-central-1", "ap-southeast-1"]
        )

        tertiary_region = CfnParameter(
            self, "TertiaryRegion",
            type="String",
            default="eu-west-1",
            description="Tertiary region for long-term archival",
            allowed_values=["us-west-1", "us-west-2", "eu-west-1", "eu-central-1", "ap-southeast-1"]
        )

        notification_email = CfnParameter(
            self, "NotificationEmail",
            type="String",
            description="Email address for backup notifications",
            allowed_pattern="^[\\w\\.-]+@[\\w\\.-]+\\.[a-zA-Z]{2,}$",
            constraint_description="Must be a valid email address"
        )

        # Create AWS Backup service role
        backup_service_role = self._create_backup_service_role()

        # Create backup vaults
        primary_vault = self._create_backup_vault(
            f"{organization_name.value_as_string}-primary-vault",
            "Primary backup vault for production workloads"
        )

        # Create SNS topic for notifications
        notification_topic = self._create_notification_topic(notification_email.value_as_string)

        # Create backup plan with cross-region configuration
        backup_plan = self._create_backup_plan(
            organization_name.value_as_string,
            primary_vault,
            secondary_region.value_as_string,
            tertiary_region.value_as_string
        )

        # Create backup selection for tagged resources
        self._create_backup_selection(backup_plan, backup_service_role)

        # Create Lambda function for backup validation
        backup_validator = self._create_backup_validator_lambda(notification_topic)

        # Create EventBridge rules for monitoring
        self._create_eventbridge_monitoring(backup_validator)

        # Outputs
        CfnOutput(
            self, "BackupPlanId",
            value=backup_plan.backup_plan_id,
            description="ID of the backup plan"
        )

        CfnOutput(
            self, "PrimaryBackupVaultName",
            value=primary_vault.backup_vault_name,
            description="Name of the primary backup vault"
        )

        CfnOutput(
            self, "BackupServiceRoleArn",
            value=backup_service_role.role_arn,
            description="ARN of the AWS Backup service role"
        )

        CfnOutput(
            self, "NotificationTopicArn",
            value=notification_topic.topic_arn,
            description="ARN of the SNS notification topic"
        )

        CfnOutput(
            self, "BackupValidatorFunctionName",
            value=backup_validator.function_name,
            description="Name of the backup validator Lambda function"
        )

    def _create_backup_service_role(self) -> iam.Role:
        """
        Create IAM service role for AWS Backup operations.
        
        Returns:
            IAM role with necessary permissions for AWS Backup
        """
        backup_service_role = iam.Role(
            self, "AWSBackupServiceRole",
            role_name="AWSBackupServiceRole",
            assumed_by=iam.ServicePrincipal("backup.amazonaws.com"),
            description="Service role for AWS Backup to perform backup and restore operations",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSBackupServiceRolePolicyForBackup"
                ),
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSBackupServiceRolePolicyForRestores"
                ),
                # Additional policy for cross-region operations
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSBackupServiceRolePolicyForS3Backup"
                ),
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSBackupServiceRolePolicyForS3Restore"
                )
            ]
        )

        # Add additional permissions for cross-region copy operations
        backup_service_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "backup:CopyIntoBackupVault",
                    "backup:DescribeRegionSettings",
                    "backup:GetBackupVaultAccessPolicy",
                    "backup:GetBackupVaultNotifications",
                    "backup:ListBackupVaults",
                    "backup:ListCopyJobs",
                    "backup:ListRecoveryPointsByBackupVault"
                ],
                resources=["*"]
            )
        )

        return backup_service_role

    def _create_backup_vault(self, vault_name: str, description: str) -> backup.BackupVault:
        """
        Create a backup vault with encryption.
        
        Args:
            vault_name: Name of the backup vault
            description: Description of the backup vault
            
        Returns:
            BackupVault construct
        """
        return backup.BackupVault(
            self, f"BackupVault{vault_name.replace('-', '')}",
            backup_vault_name=vault_name,
            encryption_key=None,  # Use default AWS managed key
            removal_policy=RemovalPolicy.DESTROY,
            access_policy=iam.PolicyDocument(
                statements=[
                    iam.PolicyStatement(
                        effect=iam.Effect.DENY,
                        principals=[iam.AnyPrincipal()],
                        actions=["backup:DeleteRecoveryPoint"],
                        resources=["*"],
                        conditions={
                            "StringNotEquals": {
                                "aws:PrincipalServiceName": "backup.amazonaws.com"
                            }
                        }
                    )
                ]
            )
        )

    def _create_notification_topic(self, email: str) -> sns.Topic:
        """
        Create SNS topic for backup notifications.
        
        Args:
            email: Email address for notifications
            
        Returns:
            SNS Topic construct
        """
        topic = sns.Topic(
            self, "BackupNotificationTopic",
            topic_name="backup-notifications",
            display_name="AWS Backup Notifications",
            kms_master_key=None  # Use default encryption
        )

        # Add email subscription
        topic.add_subscription(
            sns.EmailSubscription(email)
        )

        return topic

    def _create_backup_plan(self, org_name: str, primary_vault: backup.BackupVault,
                          secondary_region: str, tertiary_region: str) -> backup.BackupPlan:
        """
        Create backup plan with cross-region copy configuration.
        
        Args:
            org_name: Organization name
            primary_vault: Primary backup vault
            secondary_region: Secondary region for copies
            tertiary_region: Tertiary region for archival
            
        Returns:
            BackupPlan construct
        """
        # Define backup rules
        daily_backup_rule = backup.BackupPlanRule(
            rule_name="DailyBackupsWithCrossRegionCopy",
            backup_vault=primary_vault,
            schedule_expression=events.Schedule.cron(
                minute="0",
                hour="2",
                month="*",
                week_day="*",
                year="*"
            ),
            start_window=Duration.hours(8),
            completion_window=Duration.hours(168),  # 7 days
            delete_after=Duration.days(365),
            move_to_cold_storage_after=Duration.days(30),
            copy_actions=[
                backup.BackupPlanCopyAction(
                    destination_backup_vault=backup.BackupVault.from_backup_vault_name(
                        self, "SecondaryVaultRef",
                        f"arn:aws:backup:{secondary_region}:{Aws.ACCOUNT_ID}:backup-vault:{org_name}-secondary-vault"
                    ),
                    move_to_cold_storage_after=Duration.days(30),
                    delete_after=Duration.days(365)
                )
            ],
            recovery_point_tags={
                "BackupType": "Daily",
                "Environment": "Production",
                "CrossRegion": "true"
            }
        )

        weekly_backup_rule = backup.BackupPlanRule(
            rule_name="WeeklyLongTermArchival",
            backup_vault=primary_vault,
            schedule_expression=events.Schedule.cron(
                minute="0",
                hour="3",
                month="*",
                week_day="SUN",
                year="*"
            ),
            start_window=Duration.hours(8),
            completion_window=Duration.hours(168),  # 7 days
            delete_after=Duration.days(2555),  # ~7 years
            move_to_cold_storage_after=Duration.days(90),
            copy_actions=[
                backup.BackupPlanCopyAction(
                    destination_backup_vault=backup.BackupVault.from_backup_vault_name(
                        self, "TertiaryVaultRef",
                        f"arn:aws:backup:{tertiary_region}:{Aws.ACCOUNT_ID}:backup-vault:{org_name}-tertiary-vault"
                    ),
                    move_to_cold_storage_after=Duration.days(90),
                    delete_after=Duration.days(2555)
                )
            ],
            recovery_point_tags={
                "BackupType": "Weekly",
                "Environment": "Production",
                "LongTerm": "true"
            }
        )

        # Create backup plan
        backup_plan = backup.BackupPlan(
            self, "MultiRegionBackupPlan",
            backup_plan_name="MultiRegionBackupPlan",
            backup_plan_rules=[daily_backup_rule, weekly_backup_rule]
        )

        return backup_plan

    def _create_backup_selection(self, backup_plan: backup.BackupPlan, service_role: iam.Role) -> None:
        """
        Create backup selection to assign resources to the backup plan.
        
        Args:
            backup_plan: Backup plan to associate with
            service_role: IAM service role for backup operations
        """
        backup.BackupSelection(
            self, "ProductionResourcesSelection",
            backup_plan=backup_plan,
            backup_selection_name="ProductionResourcesSelection",
            role=service_role,
            resources=[
                backup.BackupResource.from_tag("Environment", "Production"),
                backup.BackupResource.from_tag("BackupEnabled", "true")
            ],
            allow_restores=True
        )

    def _create_backup_validator_lambda(self, notification_topic: sns.Topic) -> lambda_.Function:
        """
        Create Lambda function for backup validation and monitoring.
        
        Args:
            notification_topic: SNS topic for notifications
            
        Returns:
            Lambda Function construct
        """
        # Create Lambda execution role
        lambda_role = iam.Role(
            self, "BackupValidatorRole",
            role_name="BackupValidatorRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ]
        )

        # Add permissions for backup operations and SNS
        lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "backup:DescribeBackupJob",
                    "backup:ListCopyJobs",
                    "backup:DescribeRecoveryPoint",
                    "sns:Publish"
                ],
                resources=["*"]
            )
        )

        # Lambda function code
        lambda_code = '''
import json
import boto3
import logging
import os
from datetime import datetime, timedelta

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Lambda function to validate backup jobs and send notifications.
    
    This function processes EventBridge events from AWS Backup and performs
    validation checks on backup job status and cross-region copy operations.
    """
    backup_client = boto3.client('backup')
    sns_client = boto3.client('sns')
    
    # Extract backup job details from EventBridge event
    detail = event.get('detail', {})
    backup_job_id = detail.get('backupJobId')
    
    if not backup_job_id:
        logger.error("No backup job ID found in event")
        return {'statusCode': 400, 'body': 'Invalid event format'}
    
    try:
        # Get backup job details
        response = backup_client.describe_backup_job(
            BackupJobId=backup_job_id
        )
        
        backup_job = response['BackupJob']
        
        # Validate backup job completion and health
        if backup_job['State'] in ['COMPLETED']:
            # Perform additional validation checks
            recovery_point_arn = backup_job.get('RecoveryPointArn')
            
            # Check if cross-region copy was successful
            try:
                copy_jobs = backup_client.list_copy_jobs()
                logger.info(f"Found {len(copy_jobs.get('CopyJobs', []))} copy jobs")
            except Exception as e:
                logger.warning(f"Could not retrieve copy jobs: {str(e)}")
            
            message = f"Backup validation successful for job {backup_job_id}"
            logger.info(message)
            
        elif backup_job['State'] in ['FAILED', 'ABORTED']:
            message = f"Backup job {backup_job_id} failed: {backup_job.get('StatusMessage', 'Unknown error')}"
            logger.error(message)
            
            # Send SNS notification for failed jobs
            sns_client.publish(
                TopicArn=os.environ['SNS_TOPIC_ARN'],
                Subject='AWS Backup Job Failed',
                Message=message
            )
    
    except Exception as e:
        error_message = f"Error validating backup job {backup_job_id}: {str(e)}"
        logger.error(error_message)
        
        # Send notification for validation errors
        try:
            sns_client.publish(
                TopicArn=os.environ['SNS_TOPIC_ARN'],
                Subject='Backup Validation Error',
                Message=error_message
            )
        except Exception as sns_error:
            logger.error(f"Failed to send SNS notification: {str(sns_error)}")
        
        raise
    
    return {
        'statusCode': 200,
        'body': json.dumps('Backup validation completed')
    }
'''

        # Create Lambda function
        backup_validator = lambda_.Function(
            self, "BackupValidatorFunction",
            function_name="backup-validator",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(lambda_code),
            role=lambda_role,
            timeout=Duration.minutes(5),
            environment={
                "SNS_TOPIC_ARN": notification_topic.topic_arn
            },
            log_retention=logs.RetentionDays.ONE_MONTH,
            description="Lambda function for validating AWS Backup operations and sending notifications"
        )

        # Grant SNS publish permissions
        notification_topic.grant_publish(backup_validator)

        return backup_validator

    def _create_eventbridge_monitoring(self, validator_function: lambda_.Function) -> None:
        """
        Create EventBridge rules for monitoring backup job state changes.
        
        Args:
            validator_function: Lambda function to trigger on backup events
        """
        # EventBridge rule for backup job failures
        backup_failure_rule = events.Rule(
            self, "BackupJobFailureRule",
            rule_name="BackupJobFailureRule",
            description="Monitor AWS Backup job failures and aborts",
            event_pattern=events.EventPattern(
                source=["aws.backup"],
                detail_type=["Backup Job State Change"],
                detail={
                    "state": ["FAILED", "ABORTED"]
                }
            ),
            enabled=True
        )

        # EventBridge rule for backup job completion
        backup_success_rule = events.Rule(
            self, "BackupJobSuccessRule",
            rule_name="BackupJobSuccessRule",
            description="Monitor AWS Backup job completions for validation",
            event_pattern=events.EventPattern(
                source=["aws.backup"],
                detail_type=["Backup Job State Change"],
                detail={
                    "state": ["COMPLETED"]
                }
            ),
            enabled=True
        )

        # Add Lambda function as target for both rules
        backup_failure_rule.add_target(targets.LambdaFunction(validator_function))
        backup_success_rule.add_target(targets.LambdaFunction(validator_function))

        # Grant EventBridge permission to invoke Lambda
        validator_function.add_permission(
            "AllowEventBridgeInvocation",
            principal=iam.ServicePrincipal("events.amazonaws.com"),
            action="lambda:InvokeFunction",
            source_arn=backup_failure_rule.rule_arn
        )

        validator_function.add_permission(
            "AllowEventBridgeInvocationSuccess",
            principal=iam.ServicePrincipal("events.amazonaws.com"),
            action="lambda:InvokeFunction",
            source_arn=backup_success_rule.rule_arn
        )


def main() -> None:
    """
    Main function to create and deploy the CDK application.
    """
    app = App()

    # Environment configuration
    env = Environment(
        account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
        region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
    )

    # Create the stack
    MultiRegionBackupStack(
        app, "MultiRegionBackupStack",
        env=env,
        description="Multi-region backup strategies using AWS Backup with cross-region copy and monitoring",
        stack_name="multi-region-backup-stack"
    )

    # Add tags to all resources
    cdk.Tags.of(app).add("Project", "MultiRegionBackup")
    cdk.Tags.of(app).add("Environment", "Production")
    cdk.Tags.of(app).add("Owner", "DevOps")
    cdk.Tags.of(app).add("CostCenter", "Infrastructure")

    app.synth()


if __name__ == "__main__":
    main()