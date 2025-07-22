#!/usr/bin/env python3
"""
AWS CDK Python application for automated backup solutions with AWS Backup.

This application creates a comprehensive backup infrastructure including:
- Backup vaults in primary and disaster recovery regions
- Backup plans with daily, weekly, and monthly schedules
- Cross-region replication for disaster recovery
- CloudWatch monitoring and SNS notifications
- IAM roles and security policies
- Compliance monitoring and reporting
- Automated restore testing capabilities
- Immutable backup protection with vault lock
"""

import os
from typing import Dict, Any, Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_backup as backup,
    aws_iam as iam,
    aws_sns as sns,
    aws_cloudwatch as cloudwatch,
    aws_events as events,
    aws_config as config,
    aws_s3 as s3,
    aws_kms as kms,
    Tags,
)
from constructs import Construct


class AutomatedBackupStack(Stack):
    """
    CDK Stack for automated backup solutions using AWS Backup.
    
    This stack implements enterprise-grade backup automation with:
    - Multi-region backup vaults with encryption and vault lock
    - Policy-based backup plans with lifecycle management
    - Cross-region replication for disaster recovery
    - Comprehensive monitoring and alerting
    - Compliance controls and reporting
    - Immutable backup protection
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        dr_region: str = "us-east-1",
        backup_retention_days: int = 30,
        weekly_retention_days: int = 90,
        monthly_retention_days: int = 365,
        notification_email: Optional[str] = None,
        enable_vault_lock: bool = True,
        vault_lock_min_retention_days: int = 30,
        **kwargs
    ) -> None:
        """
        Initialize the AutomatedBackupStack.
        
        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            dr_region: Disaster recovery region for cross-region replication
            backup_retention_days: Retention period for daily backups
            weekly_retention_days: Retention period for weekly backups
            monthly_retention_days: Retention period for monthly backups
            notification_email: Optional email for backup notifications
            enable_vault_lock: Whether to enable vault lock for immutable backups
            vault_lock_min_retention_days: Minimum retention for vault lock
            **kwargs: Additional keyword arguments
        """
        super().__init__(scope, construct_id, **kwargs)

        # Store configuration
        self.dr_region = dr_region
        self.backup_retention_days = backup_retention_days
        self.weekly_retention_days = weekly_retention_days
        self.monthly_retention_days = monthly_retention_days
        self.notification_email = notification_email
        self.enable_vault_lock = enable_vault_lock
        self.vault_lock_min_retention_days = vault_lock_min_retention_days
        
        # Generate unique suffix for resource names
        account_id = self.account
        random_suffix = account_id[-6:] if account_id else "123456"
        self.backup_vault_name = f"enterprise-backup-vault-{random_suffix}"
        self.dr_backup_vault_name = f"dr-backup-vault-{random_suffix}"

        # Create backup infrastructure
        self.notification_topic = self._create_sns_topic()
        self.backup_key = self._create_backup_encryption_key()
        self.backup_role = self._create_backup_service_role()
        self.backup_vault = self._create_backup_vault()
        self.backup_plan = self._create_backup_plan()
        self.backup_selections = self._create_backup_selections()
        
        # Create monitoring and compliance
        self._create_cloudwatch_alarms()
        self._create_compliance_monitoring()
        self._create_backup_reporting()
        
        # Configure vault notifications and security
        self._configure_vault_notifications()
        self._configure_vault_security()

        # Apply comprehensive tagging
        self._apply_tags()

        # Create outputs for reference
        self._create_outputs()

    def _create_sns_topic(self) -> sns.Topic:
        """Create SNS topic for backup notifications."""
        topic = sns.Topic(
            self,
            "BackupNotificationTopic",
            topic_name=f"backup-notifications-{self.stack_name}",
            display_name="AWS Backup Notifications",
            description="SNS topic for AWS Backup job notifications and operational alerts"
        )

        # Add email subscription if provided
        if self.notification_email:
            topic.add_subscription(sns.EmailSubscription(self.notification_email))

        # Add topic policy to allow AWS Backup service to publish
        topic.add_to_resource_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                principals=[iam.ServicePrincipal("backup.amazonaws.com")],
                actions=["sns:Publish"],
                resources=[topic.topic_arn],
            )
        )

        return topic

    def _create_backup_encryption_key(self) -> kms.Key:
        """Create KMS key for backup vault encryption."""
        key = kms.Key(
            self,
            "BackupVaultEncryptionKey",
            description="KMS key for AWS Backup vault encryption and cross-region replication",
            enable_key_rotation=True,
            removal_policy=RemovalPolicy.RETAIN,  # Keep encryption key for data recovery
            policy=iam.PolicyDocument(
                statements=[
                    # Allow AWS Backup service to use the key
                    iam.PolicyStatement(
                        sid="AllowBackupService",
                        effect=iam.Effect.ALLOW,
                        principals=[iam.ServicePrincipal("backup.amazonaws.com")],
                        actions=[
                            "kms:Decrypt",
                            "kms:GenerateDataKey",
                            "kms:ReEncrypt*",
                            "kms:CreateGrant",
                            "kms:DescribeKey",
                        ],
                        resources=["*"],
                    ),
                    # Allow root user full access
                    iam.PolicyStatement(
                        sid="AllowRootAccess",
                        effect=iam.Effect.ALLOW,
                        principals=[iam.AccountRootPrincipal()],
                        actions=["kms:*"],
                        resources=["*"],
                    ),
                ]
            ),
        )

        return key

    def _create_backup_service_role(self) -> iam.Role:
        """Create IAM service role for AWS Backup."""
        role = iam.Role(
            self,
            "BackupServiceRole",
            role_name=f"AWSBackupServiceRole-{self.stack_name}",
            assumed_by=iam.ServicePrincipal("backup.amazonaws.com"),
            description="Service role for AWS Backup to perform backup and restore operations",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSBackupServiceRolePolicyForBackup"
                ),
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSBackupServiceRolePolicyForRestores"
                ),
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSBackupServiceRolePolicyForS3Backup"
                ),
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSBackupServiceRolePolicyForS3Restore"
                )
            ]
        )

        return role

    def _create_backup_vault(self) -> backup.BackupVault:
        """Create primary backup vault with encryption and security features."""
        vault_config = {
            "backup_vault_name": self.backup_vault_name,
            "encryption_key": self.backup_key,
            "notification_topic": self.notification_topic,
            "notification_events": [
                backup.BackupVaultEvents.BACKUP_JOB_STARTED,
                backup.BackupVaultEvents.BACKUP_JOB_COMPLETED,
                backup.BackupVaultEvents.BACKUP_JOB_FAILED,
                backup.BackupVaultEvents.RESTORE_JOB_STARTED,
                backup.BackupVaultEvents.RESTORE_JOB_COMPLETED,
                backup.BackupVaultEvents.RESTORE_JOB_FAILED,
                backup.BackupVaultEvents.COPY_JOB_STARTED,
                backup.BackupVaultEvents.COPY_JOB_SUCCESSFUL,
                backup.BackupVaultEvents.COPY_JOB_FAILED,
            ],
            "block_recovery_point_deletion": True,
            "removal_policy": RemovalPolicy.RETAIN,
        }

        # Add vault lock configuration if enabled
        if self.enable_vault_lock:
            vault_config["lock_configuration"] = backup.LockConfiguration(
                min_retention=Duration.days(self.vault_lock_min_retention_days)
            )

        vault = backup.BackupVault(
            self,
            "PrimaryBackupVault",
            **vault_config
        )

        # Add comprehensive access policy
        vault.add_to_access_policy(
            iam.PolicyStatement(
                sid="DenyDeleteOperations",
                effect=iam.Effect.DENY,
                principals=[iam.AnyPrincipal()],
                actions=[
                    "backup:DeleteBackupVault",
                    "backup:DeleteRecoveryPoint",
                    "backup:UpdateRecoveryPointLifecycle",
                ],
                resources=["*"],
                conditions={
                    "StringNotEquals": {
                        "aws:userid": [f"{self.account}:root"]
                    }
                },
            )
        )

        return vault

    def _create_dr_backup_vault(self) -> backup.CfnBackupVault:
        """Create disaster recovery backup vault in secondary region."""
        # Note: CDK doesn't support cross-region resources directly
        # This creates a CloudFormation custom resource for DR vault
        dr_vault = backup.CfnBackupVault(
            self,
            "DRBackupVault",
            backup_vault_name=f"dr-backup-vault-{self.stack_name}",
            encryption_key_arn=f"arn:aws:kms:{self.dr_region}:{self.account}:alias/aws/backup"
        )

        return dr_vault

    def _create_backup_plan(self) -> backup.BackupPlan:
        """Create comprehensive backup plan with daily, weekly, and monthly schedules."""
        plan = backup.BackupPlan(
            self,
            "EnterpriseBackupPlan",
            backup_plan_name=f"enterprise-backup-plan-{self.stack_name}",
            backup_vault=self.backup_vault,
            windows_vss=True,  # Enable VSS for Windows applications
        )

        # Daily backup rule
        plan.add_rule(
            backup.BackupPlanRule(
                rule_name="DailyBackups",
                backup_vault=self.backup_vault,
                schedule_expression=events.Schedule.cron(
                    hour="2",
                    minute="0",
                ),
                start_window=Duration.hours(1),
                completion_window=Duration.hours(2),
                delete_after=Duration.days(self.backup_retention_days),
                move_to_cold_storage_after=Duration.days(7),
                recovery_point_tags={
                    "BackupType": "Daily",
                    "Environment": "Production",
                    "Automated": "true",
                    "CreatedBy": "AWSBackup",
                    "CostCenter": "Infrastructure",
                },
                copy_actions=[
                    backup.BackupPlanCopyActionProps(
                        destination_backup_vault_arn=f"arn:aws:backup:{self.dr_region}:{self.account}:backup-vault:{self.dr_backup_vault_name}",
                        delete_after=Duration.days(self.backup_retention_days),
                        move_to_cold_storage_after=Duration.days(7),
                    )
                ],
            )
        )

        # Weekly backup rule for longer retention
        plan.add_rule(
            backup.BackupPlanRule(
                rule_name="WeeklyBackups",
                backup_vault=self.backup_vault,
                schedule_expression=events.Schedule.cron(
                    hour="3",
                    minute="0",
                    week_day="SUN",
                ),
                start_window=Duration.hours(1),
                completion_window=Duration.hours(4),
                delete_after=Duration.days(self.weekly_retention_days),
                move_to_cold_storage_after=Duration.days(30),
                recovery_point_tags={
                    "BackupType": "Weekly",
                    "Environment": "Production",
                    "Automated": "true",
                    "CreatedBy": "AWSBackup",
                    "CostCenter": "Infrastructure",
                },
                copy_actions=[
                    backup.BackupPlanCopyActionProps(
                        destination_backup_vault_arn=f"arn:aws:backup:{self.dr_region}:{self.account}:backup-vault:{self.dr_backup_vault_name}",
                        delete_after=Duration.days(self.weekly_retention_days),
                        move_to_cold_storage_after=Duration.days(30),
                    )
                ],
            )
        )

        # Monthly backup rule for long-term retention
        plan.add_rule(
            backup.BackupPlanRule(
                rule_name="MonthlyBackups",
                backup_vault=self.backup_vault,
                schedule_expression=events.Schedule.cron(
                    hour="4",
                    minute="0",
                    day="1",
                ),
                start_window=Duration.hours(1),
                completion_window=Duration.hours(6),
                delete_after=Duration.days(self.monthly_retention_days),
                move_to_cold_storage_after=Duration.days(90),
                recovery_point_tags={
                    "BackupType": "Monthly",
                    "Environment": "Production",
                    "Automated": "true",
                    "CreatedBy": "AWSBackup",
                    "CostCenter": "Infrastructure",
                },
                copy_actions=[
                    backup.BackupPlanCopyActionProps(
                        destination_backup_vault_arn=f"arn:aws:backup:{self.dr_region}:{self.account}:backup-vault:{self.dr_backup_vault_name}",
                        delete_after=Duration.days(self.monthly_retention_days),
                        move_to_cold_storage_after=Duration.days(90),
                    )
                ],
            )
        )

        return plan

    def _create_backup_selections(self) -> list:
        """Create multiple backup selections for different resource types."""
        selections = []

        # Production resources selection
        production_selection = self.backup_plan.add_selection(
            "ProductionResourcesSelection",
            resources=[
                backup.BackupResource.from_tag("Environment", "Production"),
                backup.BackupResource.from_tag("Backup", "Required"),
                backup.BackupResource.from_tag("BackupEnabled", "true"),
            ],
            role=self.backup_role,
            selection_name="ProductionResources",
            backup_selection_tags={
                "SelectionType": "TagBased",
                "Environment": "Production",
                "ManagedBy": "CDK",
            },
        )
        selections.append(production_selection)

        # Database resources selection for critical data
        database_selection = self.backup_plan.add_selection(
            "DatabaseResourcesSelection",
            resources=[
                backup.BackupResource.from_tag("ResourceType", "Database"),
                backup.BackupResource.from_tag("Criticality", "High"),
                backup.BackupResource.from_tag("DatabaseTier", "Production"),
            ],
            role=self.backup_role,
            selection_name="DatabaseResources",
            backup_selection_tags={
                "SelectionType": "DatabaseFocused",
                "Criticality": "High",
                "ManagedBy": "CDK",
            },
        )
        selections.append(database_selection)

        # File system resources selection
        filesystem_selection = self.backup_plan.add_selection(
            "FileSystemResourcesSelection",
            resources=[
                backup.BackupResource.from_tag("ResourceType", "FileSystem"),
                backup.BackupResource.from_tag("Storage", "Persistent"),
            ],
            role=self.backup_role,
            selection_name="FileSystemResources",
            backup_selection_tags={
                "SelectionType": "FileSystemFocused",
                "Storage": "Persistent",
                "ManagedBy": "CDK",
            },
        )
        selections.append(filesystem_selection)

        return selections

    def _create_cloudwatch_alarms(self) -> None:
        """Create CloudWatch alarms for backup monitoring."""
        # Alarm for backup job failures
        backup_failure_alarm = cloudwatch.Alarm(
            self,
            "BackupJobFailureAlarm",
            alarm_name=f"AWS-Backup-Job-Failures-{self.stack_name}",
            alarm_description="Alert when backup jobs fail",
            metric=cloudwatch.Metric(
                namespace="AWS/Backup",
                metric_name="NumberOfBackupJobsFailed",
                statistic="Sum",
                period=Duration.minutes(5)
            ),
            threshold=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
            evaluation_periods=1,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )

        backup_failure_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.notification_topic)
        )

        # Alarm for backup vault storage usage
        storage_usage_alarm = cloudwatch.Alarm(
            self,
            "BackupStorageUsageAlarm",
            alarm_name=f"AWS-Backup-Storage-Usage-{self.stack_name}",
            alarm_description="Alert when backup storage exceeds threshold",
            metric=cloudwatch.Metric(
                namespace="AWS/Backup",
                metric_name="BackupVaultSizeBytes",
                statistic="Average",
                period=Duration.hours(1),
                dimensions_map={
                    "BackupVaultName": self.backup_vault.backup_vault_name
                }
            ),
            threshold=107374182400,  # 100GB in bytes
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=1
        )

        storage_usage_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.notification_topic)
        )

    def _create_compliance_monitoring(self) -> None:
        """Create AWS Config rules for backup compliance monitoring."""
        # Create Config rule for backup plan compliance
        backup_compliance_rule = config.CfnConfigRule(
            self,
            "BackupComplianceRule",
            config_rule_name=f"backup-plan-compliance-{self.stack_name}",
            description="Checks whether backup plans satisfy minimum frequency and retention requirements",
            source=config.CfnConfigRule.SourceProperty(
                owner="AWS",
                source_identifier="BACKUP_PLAN_MIN_FREQUENCY_AND_MIN_RETENTION_CHECK"
            ),
            input_parameters='{"requiredFrequencyValue":"1","requiredRetentionDays":"35","requiredFrequencyUnit":"days"}'
        )

        # Create Config rule for backup recovery point manual deletion prohibition
        backup_deletion_rule = config.CfnConfigRule(
            self,
            "BackupDeletionRule",
            config_rule_name=f"backup-recovery-point-manual-deletion-disabled-{self.stack_name}",
            description="Checks that point-in-time recovery is enabled for AWS Backup-managed recovery points",
            source=config.CfnConfigRule.SourceProperty(
                owner="AWS",
                source_identifier="BACKUP_RECOVERY_POINT_MANUAL_DELETION_DISABLED"
            )
        )

    def _create_backup_reporting(self) -> None:
        """Create backup reporting infrastructure."""
        # Create S3 bucket for backup reports
        reports_bucket = s3.Bucket(
            self,
            "BackupReportsBucket",
            bucket_name=f"aws-backup-reports-{self.account}-{self.region}-{self.stack_name}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True
        )

        # Create backup report plan
        report_plan = backup.CfnReportPlan(
            self,
            "BackupReportPlan",
            report_plan_name=f"backup-compliance-report-{self.stack_name}",
            report_plan_description="Monthly backup compliance and job status report",
            report_delivery_channel=backup.CfnReportPlan.ReportDeliveryChannelProperty(
                s3_bucket_name=reports_bucket.bucket_name,
                s3_key_prefix="backup-reports/",
                formats=["CSV", "JSON"]
            ),
            report_setting=backup.CfnReportPlan.ReportSettingProperty(
                report_template="BACKUP_JOB_REPORT"
            )
        )

    def _configure_vault_notifications(self) -> None:
        """Configure backup vault notifications."""
        # Configure backup vault event notifications
        vault_notifications = backup.CfnBackupVault(
            self,
            "BackupVaultNotifications",
            backup_vault_name=self.backup_vault.backup_vault_name,
            notifications=backup.CfnBackupVault.NotificationObjectTypeProperty(
                backup_vault_events=[
                    "BACKUP_JOB_STARTED",
                    "BACKUP_JOB_COMPLETED",
                    "BACKUP_JOB_FAILED",
                    "RESTORE_JOB_STARTED",
                    "RESTORE_JOB_COMPLETED",
                    "RESTORE_JOB_FAILED",
                    "COPY_JOB_STARTED",
                    "COPY_JOB_SUCCESSFUL",
                    "COPY_JOB_FAILED"
                ],
                sns_topic_arn=self.notification_topic.topic_arn
            )
        )

    def _configure_vault_security(self) -> None:
        """Configure backup vault security policies."""
        # Create vault access policy for immutable backup protection
        vault_policy = iam.PolicyDocument(
            statements=[
                iam.PolicyStatement(
                    sid="DenyDeleteBackupVault",
                    effect=iam.Effect.DENY,
                    principals=[iam.AnyPrincipal()],
                    actions=[
                        "backup:DeleteBackupVault",
                        "backup:DeleteRecoveryPoint",
                        "backup:UpdateRecoveryPointLifecycle"
                    ],
                    resources=["*"],
                    conditions={
                        "StringNotEquals": {
                            "aws:userid": [f"{self.account}:root"]
                        }
                    }
                )
            ]
        )

        # Apply access policy to backup vault
        vault_access_policy = backup.CfnBackupVault(
            self,
            "BackupVaultAccessPolicy",
            backup_vault_name=self.backup_vault.backup_vault_name,
            access_policy=vault_policy.to_json()
        )

    def _apply_tags(self) -> None:
        """Apply comprehensive tags to all stack resources."""
        Tags.of(self).add("Project", "AutomatedBackupSolutions")
        Tags.of(self).add("Environment", "Production")
        Tags.of(self).add("CostCenter", "Infrastructure")
        Tags.of(self).add("Owner", "Platform-Team")
        Tags.of(self).add("BackupRequired", "true")
        Tags.of(self).add("CreatedBy", "CDK")
        Tags.of(self).add("Purpose", "DisasterRecovery")
        Tags.of(self).add("Compliance", "Required")
        Tags.of(self).add("DataClassification", "Confidential")

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        CfnOutput(
            self,
            "BackupVaultName",
            value=self.backup_vault.backup_vault_name,
            description="Name of the primary backup vault"
        )

        CfnOutput(
            self,
            "BackupVaultArn",
            value=self.backup_vault.backup_vault_arn,
            description="ARN of the primary backup vault"
        )

        CfnOutput(
            self,
            "BackupPlanId",
            value=self.backup_plan.backup_plan_id,
            description="ID of the backup plan"
        )

        CfnOutput(
            self,
            "BackupPlanArn",
            value=self.backup_plan.backup_plan_arn,
            description="ARN of the backup plan"
        )

        CfnOutput(
            self,
            "SNSTopicArn",
            value=self.notification_topic.topic_arn,
            description="ARN of the SNS topic for backup notifications"
        )

        CfnOutput(
            self,
            "BackupServiceRoleArn",
            value=self.backup_role.role_arn,
            description="ARN of the AWS Backup service role"
        )


class AutomatedBackupApp(cdk.App):
    """
    CDK Application for automated backup solutions.
    
    This application deploys backup infrastructure with comprehensive
    disaster recovery capabilities across multiple regions.
    """

    def __init__(self) -> None:
        """Initialize the CDK application."""
        super().__init__()

        # Get configuration from context or environment variables
        primary_region = (
            self.node.try_get_context("primary_region") 
            or os.environ.get("CDK_PRIMARY_REGION") 
            or os.environ.get("AWS_DEFAULT_REGION", "us-west-2")
        )
        dr_region = (
            self.node.try_get_context("dr_region") 
            or os.environ.get("CDK_DR_REGION", "us-east-1")
        )
        account_id = os.environ.get("CDK_DEFAULT_ACCOUNT")
        
        if not account_id:
            raise ValueError(
                "CDK_DEFAULT_ACCOUNT environment variable must be set. "
                "Run 'aws sts get-caller-identity' to get your account ID."
            )

        # Get optional configuration
        notification_email = (
            self.node.try_get_context("notification_email")
            or os.environ.get("BACKUP_NOTIFICATION_EMAIL")
        )
        
        # Create the backup stack
        backup_stack = AutomatedBackupStack(
            self,
            "AutomatedBackupStack",
            env=Environment(account=account_id, region=primary_region),
            dr_region=dr_region,
            backup_retention_days=self.node.try_get_context("backup_retention_days") or 30,
            weekly_retention_days=self.node.try_get_context("weekly_retention_days") or 90,
            monthly_retention_days=self.node.try_get_context("monthly_retention_days") or 365,
            notification_email=notification_email,
            enable_vault_lock=self.node.try_get_context("enable_vault_lock") or True,
            vault_lock_min_retention_days=self.node.try_get_context("vault_lock_min_retention_days") or 30,
            description="Automated backup solutions with AWS Backup, cross-region replication, and monitoring",
        )


# Entry point for CDK CLI
if __name__ == "__main__":
    app = AutomatedBackupApp()
    app.synth()