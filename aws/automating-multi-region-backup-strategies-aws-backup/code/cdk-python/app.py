#!/usr/bin/env python3
"""
AWS CDK Python application for automating multi-region backup strategies using AWS Backup.

This application creates a comprehensive backup solution with cross-region replication,
automated monitoring, and notification capabilities across multiple AWS regions.
"""

import os
from typing import Dict, List

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    aws_backup as backup,
    aws_events as events,
    aws_events_targets as targets,
    aws_iam as iam,
    aws_lambda as lambda_,
    aws_logs as logs,
    aws_sns as sns,
    aws_sns_subscriptions as subscriptions,
    Duration,
    RemovalPolicy,
    Tags,
)
from constructs import Construct


class MultiRegionBackupStack(Stack):
    """
    CDK Stack for implementing multi-region backup strategies with AWS Backup.
    
    This stack creates:
    - IAM service roles for AWS Backup operations
    - Backup vaults in multiple regions with encryption
    - Comprehensive backup plans with cross-region copy
    - EventBridge rules for backup monitoring
    - Lambda functions for backup validation
    - SNS topics for notifications
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Configuration parameters
        self.organization_name = self.node.try_get_context("organization_name") or "MyOrg"
        self.primary_region = self.region
        self.secondary_region = self.node.try_get_context("secondary_region") or "us-west-2"
        self.tertiary_region = self.node.try_get_context("tertiary_region") or "eu-west-1"
        self.notification_email = self.node.try_get_context("notification_email") or "admin@example.com"
        
        # Create IAM service role for AWS Backup
        self.backup_service_role = self._create_backup_service_role()
        
        # Create backup vaults
        self.primary_vault = self._create_backup_vault("primary")
        
        # Create backup plan with cross-region copy
        self.backup_plan = self._create_backup_plan()
        
        # Create backup selection for resource tagging
        self.backup_selection = self._create_backup_selection()
        
        # Create SNS topic for notifications
        self.notification_topic = self._create_notification_topic()
        
        # Create Lambda function for backup validation
        self.validation_function = self._create_validation_function()
        
        # Create EventBridge rules for monitoring
        self._create_eventbridge_monitoring()
        
        # Apply tags to all resources
        self._apply_resource_tags()

    def _create_backup_service_role(self) -> iam.Role:
        """
        Create IAM service role for AWS Backup with necessary permissions.
        
        Returns:
            iam.Role: The created IAM role for AWS Backup service
        """
        role = iam.Role(
            self, "AWSBackupServiceRole",
            role_name="AWSBackupServiceRole",
            assumed_by=iam.ServicePrincipal("backup.amazonaws.com"),
            description="Service role for AWS Backup operations with backup and restore permissions",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSBackupServiceRolePolicyForBackup"
                ),
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSBackupServiceRolePolicyForRestores"
                ),
            ],
        )
        
        return role

    def _create_backup_vault(self, vault_type: str) -> backup.BackupVault:
        """
        Create a backup vault with encryption enabled.
        
        Args:
            vault_type: Type of vault (primary, secondary, tertiary)
            
        Returns:
            backup.BackupVault: The created backup vault
        """
        vault_name = f"{self.organization_name}-{vault_type}-vault"
        
        vault = backup.BackupVault(
            self, f"BackupVault{vault_type.title()}",
            backup_vault_name=vault_name,
            encryption_key=None,  # Use default AWS Backup encryption key
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        return vault

    def _create_backup_plan(self) -> backup.BackupPlan:
        """
        Create a comprehensive backup plan with cross-region copy rules.
        
        Returns:
            backup.BackupPlan: The created backup plan
        """
        backup_plan = backup.BackupPlan(
            self, "MultiRegionBackupPlan",
            backup_plan_name=f"{self.organization_name}-MultiRegionBackupPlan",
        )
        
        # Daily backups with cross-region copy to secondary region
        backup_plan.add_rule(backup.BackupPlanRule(
            backup_vault=self.primary_vault,
            rule_name="DailyBackupsWithCrossRegionCopy",
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
                        self, "SecondaryVault",
                        f"{self.organization_name}-secondary-vault"
                    ),
                    delete_after=Duration.days(365),
                    move_to_cold_storage_after=Duration.days(30),
                )
            ],
            recovery_point_tags={
                "BackupType": "Daily",
                "Environment": "Production",
                "CrossRegion": "true"
            }
        ))
        
        # Weekly backups for long-term archival to tertiary region
        backup_plan.add_rule(backup.BackupPlanRule(
            backup_vault=self.primary_vault,
            rule_name="WeeklyLongTermArchival",
            schedule_expression=events.Schedule.cron(
                minute="0",
                hour="3",
                month="*",
                week_day="SUN",
                year="*"
            ),
            start_window=Duration.hours(8),
            completion_window=Duration.hours(168),  # 7 days
            delete_after=Duration.days(2555),  # 7 years
            move_to_cold_storage_after=Duration.days(90),
            copy_actions=[
                backup.BackupPlanCopyAction(
                    destination_backup_vault=backup.BackupVault.from_backup_vault_name(
                        self, "TertiaryVault",
                        f"{self.organization_name}-tertiary-vault"
                    ),
                    delete_after=Duration.days(2555),  # 7 years
                    move_to_cold_storage_after=Duration.days(90),
                )
            ],
            recovery_point_tags={
                "BackupType": "Weekly",
                "Environment": "Production",
                "LongTerm": "true"
            }
        ))
        
        return backup_plan

    def _create_backup_selection(self) -> backup.BackupSelection:
        """
        Create backup selection using tag-based resource discovery.
        
        Returns:
            backup.BackupSelection: The created backup selection
        """
        selection = backup.BackupSelection(
            self, "ProductionResourcesSelection",
            backup_plan=self.backup_plan,
            selection_name="ProductionResourcesSelection",
            role=self.backup_service_role,
            resources=[
                backup.BackupResource.from_construct(self),  # All resources in this construct
            ],
            conditions={
                "StringEquals": {
                    "aws:ResourceTag/Environment": ["Production"],
                    "aws:ResourceTag/BackupEnabled": ["true"]
                }
            }
        )
        
        return selection

    def _create_notification_topic(self) -> sns.Topic:
        """
        Create SNS topic for backup notifications.
        
        Returns:
            sns.Topic: The created SNS topic
        """
        topic = sns.Topic(
            self, "BackupNotifications",
            topic_name="backup-notifications",
            display_name="AWS Backup Notifications",
        )
        
        # Add email subscription
        topic.add_subscription(
            subscriptions.EmailSubscription(self.notification_email)
        )
        
        return topic

    def _create_validation_function(self) -> lambda_.Function:
        """
        Create Lambda function for backup validation and monitoring.
        
        Returns:
            lambda_.Function: The created Lambda function
        """
        # Create execution role for Lambda
        lambda_role = iam.Role(
            self, "BackupValidatorRole",
            role_name="BackupValidatorRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Execution role for backup validation Lambda function",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                ),
            ],
        )
        
        # Add custom policy for backup operations
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
        
        # Create Lambda function
        function = lambda_.Function(
            self, "BackupValidator",
            function_name="backup-validator",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_lambda_code()),
            role=lambda_role,
            timeout=Duration.minutes(5),
            environment={
                "SNS_TOPIC_ARN": self.notification_topic.topic_arn,
            },
            log_retention=logs.RetentionDays.ONE_MONTH,
        )
        
        # Grant SNS publish permissions
        self.notification_topic.grant_publish(function)
        
        return function

    def _create_eventbridge_monitoring(self) -> None:
        """Create EventBridge rules for backup job monitoring."""
        # Rule for backup job failures
        failure_rule = events.Rule(
            self, "BackupJobFailureRule",
            rule_name="BackupJobFailureRule",
            description="Monitor backup job failures and trigger notifications",
            event_pattern=events.EventPattern(
                source=["aws.backup"],
                detail_type=["Backup Job State Change"],
                detail={
                    "state": ["FAILED", "ABORTED"]
                }
            ),
        )
        
        # Add Lambda function as target
        failure_rule.add_target(
            targets.LambdaFunction(
                self.validation_function,
                retry_attempts=2,
            )
        )
        
        # Rule for successful backup jobs (for validation)
        success_rule = events.Rule(
            self, "BackupJobSuccessRule",
            rule_name="BackupJobSuccessRule",
            description="Monitor successful backup jobs for validation",
            event_pattern=events.EventPattern(
                source=["aws.backup"],
                detail_type=["Backup Job State Change"],
                detail={
                    "state": ["COMPLETED"]
                }
            ),
        )
        
        # Add Lambda function as target for success validation
        success_rule.add_target(
            targets.LambdaFunction(
                self.validation_function,
                retry_attempts=2,
            )
        )

    def _get_lambda_code(self) -> str:
        """
        Generate Lambda function code for backup validation.
        
        Returns:
            str: Python code for the Lambda function
        """
        return '''
import json
import boto3
import os
import logging
from datetime import datetime, timedelta

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Lambda function to validate backup jobs and send notifications.
    
    Args:
        event: EventBridge event containing backup job details
        context: Lambda context object
        
    Returns:
        dict: Response with status code and message
    """
    backup_client = boto3.client('backup')
    sns_client = boto3.client('sns')
    
    # Extract backup job details from EventBridge event
    detail = event['detail']
    backup_job_id = detail['backupJobId']
    
    try:
        # Get backup job details
        response = backup_client.describe_backup_job(
            BackupJobId=backup_job_id
        )
        
        backup_job = response['BackupJob']
        
        # Validate backup job completion and health
        if backup_job['State'] in ['COMPLETED']:
            recovery_point_arn = backup_job['RecoveryPointArn']
            message = f"Backup validation successful for job {backup_job_id}\\n"
            message += f"Resource: {backup_job.get('ResourceArn', 'Unknown')}\\n"
            message += f"Recovery Point: {recovery_point_arn}\\n"
            message += f"Completion Time: {backup_job.get('CompletionDate', 'Unknown')}"
            
            logger.info(message)
            
            # Send success notification for critical resources
            if backup_job.get('ResourceType') in ['EC2', 'RDS', 'EFS']:
                sns_client.publish(
                    TopicArn=os.environ['SNS_TOPIC_ARN'],
                    Subject=f'AWS Backup Job Completed - {backup_job.get("ResourceType", "Unknown")}',
                    Message=message
                )
            
        elif backup_job['State'] in ['FAILED', 'ABORTED']:
            error_message = f"Backup job {backup_job_id} failed\\n"
            error_message += f"Resource: {backup_job.get('ResourceArn', 'Unknown')}\\n"
            error_message += f"Status: {backup_job['State']}\\n"
            error_message += f"Error: {backup_job.get('StatusMessage', 'Unknown error')}\\n"
            error_message += f"Created: {backup_job.get('CreationDate', 'Unknown')}"
            
            logger.error(error_message)
            
            # Send SNS notification for failed jobs
            sns_client.publish(
                TopicArn=os.environ['SNS_TOPIC_ARN'],
                Subject=f'AWS Backup Job Failed - {backup_job.get("ResourceType", "Unknown")}',
                Message=error_message
            )
    
    except Exception as e:
        error_msg = f"Error validating backup job: {str(e)}"
        logger.error(error_msg)
        
        # Send notification about validation error
        try:
            sns_client.publish(
                TopicArn=os.environ['SNS_TOPIC_ARN'],
                Subject='AWS Backup Validation Error',
                Message=error_msg
            )
        except Exception as sns_error:
            logger.error(f"Failed to send SNS notification: {str(sns_error)}")
        
        raise
    
    return {
        'statusCode': 200,
        'body': json.dumps('Backup validation completed successfully')
    }
'''

    def _apply_resource_tags(self) -> None:
        """Apply standardized tags to all resources in the stack."""
        Tags.of(self).add("Project", "MultiRegionBackup")
        Tags.of(self).add("Environment", "Production")
        Tags.of(self).add("Owner", self.organization_name)
        Tags.of(self).add("BackupEnabled", "true")
        Tags.of(self).add("ManagedBy", "CDK")


class MultiRegionBackupApp(cdk.App):
    """CDK Application for multi-region backup strategies."""

    def __init__(self):
        super().__init__()
        
        # Get configuration from context or environment
        organization_name = self.node.try_get_context("organization_name") or "MyOrg"
        primary_region = self.node.try_get_context("primary_region") or "us-east-1"
        secondary_region = self.node.try_get_context("secondary_region") or "us-west-2"
        tertiary_region = self.node.try_get_context("tertiary_region") or "eu-west-1"
        aws_account = self.node.try_get_context("aws_account") or os.environ.get("CDK_DEFAULT_ACCOUNT")
        
        # Create primary stack in primary region
        primary_stack = MultiRegionBackupStack(
            self, f"{organization_name}-backup-primary",
            env=Environment(
                account=aws_account,
                region=primary_region
            ),
            description="Primary stack for multi-region backup strategies with AWS Backup",
        )
        
        # Create secondary vault stack (simplified for cross-region copy destination)
        secondary_stack = Stack(
            self, f"{organization_name}-backup-secondary",
            env=Environment(
                account=aws_account,
                region=secondary_region
            ),
            description="Secondary backup vault for cross-region backup copies",
        )
        
        # Create secondary backup vault
        secondary_vault = backup.BackupVault(
            secondary_stack, "SecondaryBackupVault",
            backup_vault_name=f"{organization_name}-secondary-vault",
            encryption_key=None,  # Use default AWS Backup encryption key
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        # Create tertiary vault stack (for long-term archival)
        tertiary_stack = Stack(
            self, f"{organization_name}-backup-tertiary",
            env=Environment(
                account=aws_account,
                region=tertiary_region
            ),
            description="Tertiary backup vault for long-term archival storage",
        )
        
        # Create tertiary backup vault
        tertiary_vault = backup.BackupVault(
            tertiary_stack, "TertiaryBackupVault",
            backup_vault_name=f"{organization_name}-tertiary-vault",
            encryption_key=None,  # Use default AWS Backup encryption key
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        # Apply tags to all stacks
        for stack in [primary_stack, secondary_stack, tertiary_stack]:
            Tags.of(stack).add("Project", "MultiRegionBackup")
            Tags.of(stack).add("Environment", "Production")
            Tags.of(stack).add("Owner", organization_name)
            Tags.of(stack).add("ManagedBy", "CDK")


# Application entry point
app = MultiRegionBackupApp()
app.synth()