#!/usr/bin/env python3
"""
CDK Python application for implementing database backup and point-in-time recovery strategies
with Amazon RDS, AWS Backup, and cross-region replication.

This application creates a comprehensive backup and recovery solution including:
- RDS instance with automated backups
- AWS Backup vault with encryption
- Cross-region backup replication
- IAM roles and policies
- CloudWatch monitoring and alerting
- KMS encryption keys
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    aws_rds as rds,
    aws_backup as backup,
    aws_iam as iam,
    aws_kms as kms,
    aws_cloudwatch as cloudwatch,
    aws_sns as sns,
    aws_ec2 as ec2,
    aws_logs as logs,
    RemovalPolicy,
    Duration,
    CfnOutput,
    Tags
)
from typing import Dict, List, Optional
from constructs import Construct
import json


class DatabaseBackupRecoveryStack(Stack):
    """
    Main stack for database backup and point-in-time recovery implementation.
    
    This stack creates all necessary resources for a comprehensive backup strategy
    including RDS with automated backups, AWS Backup integration, cross-region
    replication, and monitoring.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Configuration parameters
        self.db_instance_class = "db.t3.micro"
        self.db_engine = "mysql"
        self.db_allocated_storage = 20
        self.backup_retention_period = 7
        self.dr_region = "us-west-2"
        self.environment_name = "production"
        
        # Create KMS key for backup encryption
        self.backup_kms_key = self._create_backup_kms_key()
        
        # Create VPC and security groups
        self.vpc = self._create_vpc()
        self.db_security_group = self._create_db_security_group()
        
        # Create RDS subnet group
        self.db_subnet_group = self._create_db_subnet_group()
        
        # Create IAM roles
        self.backup_role = self._create_backup_iam_role()
        
        # Create RDS instance with backup configuration
        self.db_instance = self._create_rds_instance()
        
        # Create AWS Backup vault
        self.backup_vault = self._create_backup_vault()
        
        # Create backup plan
        self.backup_plan = self._create_backup_plan()
        
        # Create backup selection
        self.backup_selection = self._create_backup_selection()
        
        # Create monitoring and alerting
        self.sns_topic = self._create_sns_topic()
        self.backup_alarm = self._create_backup_alarm()
        
        # Create outputs
        self._create_outputs()
        
        # Add tags to all resources
        self._add_tags()

    def _create_backup_kms_key(self) -> kms.Key:
        """Create KMS key for backup encryption with proper permissions."""
        key = kms.Key(
            self, "BackupKMSKey",
            description="KMS key for RDS backup encryption",
            enable_key_rotation=True,
            removal_policy=RemovalPolicy.DESTROY,
            policy=iam.PolicyDocument(
                statements=[
                    iam.PolicyStatement(
                        sid="Enable IAM User Permissions",
                        effect=iam.Effect.ALLOW,
                        principals=[iam.AccountRootPrincipal()],
                        actions=["kms:*"],
                        resources=["*"]
                    ),
                    iam.PolicyStatement(
                        sid="Allow AWS Backup to use the key",
                        effect=iam.Effect.ALLOW,
                        principals=[iam.ServicePrincipal("backup.amazonaws.com")],
                        actions=[
                            "kms:Decrypt",
                            "kms:GenerateDataKey",
                            "kms:CreateGrant",
                            "kms:RetireGrant",
                            "kms:DescribeKey"
                        ],
                        resources=["*"]
                    ),
                    iam.PolicyStatement(
                        sid="Allow RDS to use the key",
                        effect=iam.Effect.ALLOW,
                        principals=[iam.ServicePrincipal("rds.amazonaws.com")],
                        actions=[
                            "kms:Decrypt",
                            "kms:GenerateDataKey",
                            "kms:CreateGrant",
                            "kms:RetireGrant",
                            "kms:DescribeKey"
                        ],
                        resources=["*"]
                    )
                ]
            )
        )
        
        # Create alias for the key
        kms.Alias(
            self, "BackupKMSKeyAlias",
            alias_name="alias/rds-backup-key",
            target_key=key
        )
        
        return key

    def _create_vpc(self) -> ec2.Vpc:
        """Create VPC with private subnets for RDS."""
        vpc = ec2.Vpc(
            self, "DatabaseVPC",
            max_azs=2,
            nat_gateways=0,  # No NAT gateways needed for this demo
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="Private",
                    subnet_type=ec2.SubnetType.PRIVATE_ISOLATED,
                    cidr_mask=24
                ),
                ec2.SubnetConfiguration(
                    name="Public",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24
                )
            ]
        )
        
        return vpc

    def _create_db_security_group(self) -> ec2.SecurityGroup:
        """Create security group for RDS instance."""
        sg = ec2.SecurityGroup(
            self, "DatabaseSecurityGroup",
            vpc=self.vpc,
            description="Security group for RDS database instance",
            allow_all_outbound=False
        )
        
        # Allow MySQL traffic from VPC
        sg.add_ingress_rule(
            peer=ec2.Peer.ipv4(self.vpc.vpc_cidr_block),
            connection=ec2.Port.tcp(3306),
            description="Allow MySQL traffic from VPC"
        )
        
        return sg

    def _create_db_subnet_group(self) -> rds.SubnetGroup:
        """Create RDS subnet group using private subnets."""
        return rds.SubnetGroup(
            self, "DatabaseSubnetGroup",
            description="Subnet group for RDS database instance",
            vpc=self.vpc,
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PRIVATE_ISOLATED
            )
        )

    def _create_backup_iam_role(self) -> iam.Role:
        """Create IAM role for AWS Backup service."""
        role = iam.Role(
            self, "BackupServiceRole",
            assumed_by=iam.ServicePrincipal("backup.amazonaws.com"),
            description="IAM role for AWS Backup service operations",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSBackupServiceRolePolicyForBackup"
                ),
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSBackupServiceRolePolicyForRestores"
                )
            ]
        )
        
        # Add additional permissions for cross-region operations
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "kms:Decrypt",
                    "kms:GenerateDataKey",
                    "kms:CreateGrant",
                    "kms:RetireGrant",
                    "kms:DescribeKey"
                ],
                resources=[self.backup_kms_key.key_arn]
            )
        )
        
        return role

    def _create_rds_instance(self) -> rds.DatabaseInstance:
        """Create RDS instance with backup configuration."""
        # Create parameter group for backup optimization
        parameter_group = rds.ParameterGroup(
            self, "DatabaseParameterGroup",
            engine=rds.DatabaseInstanceEngine.mysql(
                version=rds.MysqlEngineVersion.VER_8_0
            ),
            description="Parameter group for backup optimized MySQL instance"
        )
        
        # Create RDS instance
        db_instance = rds.DatabaseInstance(
            self, "ProductionDatabase",
            identifier="production-db",
            engine=rds.DatabaseInstanceEngine.mysql(
                version=rds.MysqlEngineVersion.VER_8_0
            ),
            instance_type=ec2.InstanceType(self.db_instance_class),
            allocated_storage=self.db_allocated_storage,
            storage_type=rds.StorageType.GP2,
            storage_encrypted=True,
            storage_encryption_key=self.backup_kms_key,
            vpc=self.vpc,
            subnet_group=self.db_subnet_group,
            security_groups=[self.db_security_group],
            backup_retention=Duration.days(self.backup_retention_period),
            preferred_backup_window="03:00-04:00",
            preferred_maintenance_window="sun:04:00-sun:05:00",
            copy_tags_to_snapshot=True,
            delete_automated_backups=True,
            deletion_protection=False,  # Set to True for production
            parameter_group=parameter_group,
            cloudwatch_logs_exports=["error", "general", "slow-query"],
            cloudwatch_logs_retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY  # Change for production
        )
        
        # Add tags for backup selection
        Tags.of(db_instance).add("Environment", self.environment_name)
        Tags.of(db_instance).add("BackupRequired", "true")
        
        return db_instance

    def _create_backup_vault(self) -> backup.BackupVault:
        """Create AWS Backup vault with encryption."""
        vault = backup.BackupVault(
            self, "DatabaseBackupVault",
            backup_vault_name="rds-backup-vault",
            encryption_key=self.backup_kms_key,
            removal_policy=RemovalPolicy.DESTROY
        )
        
        # Create access policy for the vault
        vault_policy = {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Sid": "AllowBackupAccess",
                    "Effect": "Allow",
                    "Principal": {
                        "AWS": f"arn:aws:iam::{self.account}:root"
                    },
                    "Action": [
                        "backup:DescribeBackupVault",
                        "backup:DescribeRecoveryPoint",
                        "backup:ListRecoveryPointsByBackupVault"
                    ],
                    "Resource": "*"
                }
            ]
        }
        
        # Apply access policy to vault
        backup.CfnBackupVault(
            self, "BackupVaultPolicy",
            backup_vault_name=vault.backup_vault_name,
            access_policy=vault_policy
        )
        
        return vault

    def _create_backup_plan(self) -> backup.BackupPlan:
        """Create comprehensive backup plan with multiple retention tiers."""
        plan = backup.BackupPlan(
            self, "DatabaseBackupPlan",
            backup_plan_name="rds-backup-plan",
            backup_plan_rules=[
                # Daily backups with lifecycle management
                backup.BackupPlanRule(
                    backup_vault=self.backup_vault,
                    rule_name="DailyBackups",
                    schedule_expression=backup.BackupPlanRule.daily_at_5am(),
                    start_window=Duration.hours(1),
                    completion_window=Duration.hours(2),
                    delete_after=Duration.days(30),
                    move_to_cold_storage_after=Duration.days(7),
                    recovery_point_tags={
                        "Environment": self.environment_name,
                        "BackupType": "Automated"
                    }
                ),
                # Weekly backups for longer retention
                backup.BackupPlanRule(
                    backup_vault=self.backup_vault,
                    rule_name="WeeklyBackups",
                    schedule_expression=backup.BackupPlanRule.weekly_on_sunday_at_3am(),
                    start_window=Duration.hours(1),
                    completion_window=Duration.hours(3),
                    delete_after=Duration.days(90),
                    move_to_cold_storage_after=Duration.days(14),
                    recovery_point_tags={
                        "Environment": self.environment_name,
                        "BackupType": "Weekly"
                    }
                )
            ]
        )
        
        return plan

    def _create_backup_selection(self) -> backup.BackupSelection:
        """Create backup selection to assign resources to backup plan."""
        selection = backup.BackupSelection(
            self, "DatabaseBackupSelection",
            backup_plan=self.backup_plan,
            resources=[
                backup.BackupResource.from_rds_database_instance(self.db_instance)
            ],
            role=self.backup_role,
            backup_selection_name="rds-backup-selection",
            conditions={
                "StringEquals": {
                    "aws:ResourceTag/Environment": [self.environment_name]
                }
            }
        )
        
        return selection

    def _create_sns_topic(self) -> sns.Topic:
        """Create SNS topic for backup notifications."""
        topic = sns.Topic(
            self, "BackupNotifications",
            topic_name="rds-backup-notifications",
            display_name="RDS Backup Notifications",
            fifo=False
        )
        
        # Add email subscription (you can customize this)
        # topic.add_subscription(
        #     sns.EmailSubscription("admin@example.com")
        # )
        
        return topic

    def _create_backup_alarm(self) -> cloudwatch.Alarm:
        """Create CloudWatch alarm for backup failure monitoring."""
        alarm = cloudwatch.Alarm(
            self, "BackupFailureAlarm",
            alarm_name="RDS-Backup-Failures",
            alarm_description="Alert on RDS backup failures",
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
        
        # Add SNS action
        alarm.add_alarm_action(
            cloudwatch.SnsAction(self.sns_topic)
        )
        
        return alarm

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        CfnOutput(
            self, "DatabaseInstanceIdentifier",
            value=self.db_instance.instance_identifier,
            description="RDS database instance identifier"
        )
        
        CfnOutput(
            self, "DatabaseEndpoint",
            value=self.db_instance.instance_endpoint.hostname,
            description="RDS database endpoint"
        )
        
        CfnOutput(
            self, "BackupVaultName",
            value=self.backup_vault.backup_vault_name,
            description="AWS Backup vault name"
        )
        
        CfnOutput(
            self, "BackupPlanId",
            value=self.backup_plan.backup_plan_id,
            description="AWS Backup plan ID"
        )
        
        CfnOutput(
            self, "KMSKeyId",
            value=self.backup_kms_key.key_id,
            description="KMS key ID for backup encryption"
        )
        
        CfnOutput(
            self, "BackupRoleArn",
            value=self.backup_role.role_arn,
            description="IAM role ARN for backup operations"
        )
        
        CfnOutput(
            self, "SNSTopicArn",
            value=self.sns_topic.topic_arn,
            description="SNS topic ARN for backup notifications"
        )

    def _add_tags(self) -> None:
        """Add common tags to all resources in the stack."""
        Tags.of(self).add("Project", "DatabaseBackupRecovery")
        Tags.of(self).add("Environment", self.environment_name)
        Tags.of(self).add("ManagedBy", "CDK")
        Tags.of(self).add("CostCenter", "Infrastructure")


class CrossRegionReplicationStack(Stack):
    """
    Stack for cross-region backup replication resources.
    
    This stack should be deployed in the DR region to support
    cross-region backup replication capabilities.
    """

    def __init__(self, scope: Construct, construct_id: str, 
                 primary_region: str, primary_kms_key_arn: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)
        
        self.primary_region = primary_region
        self.primary_kms_key_arn = primary_kms_key_arn
        
        # Create KMS key for DR region
        self.dr_kms_key = self._create_dr_kms_key()
        
        # Create backup vault in DR region
        self.dr_backup_vault = self._create_dr_backup_vault()
        
        # Create outputs
        self._create_outputs()
        
        # Add tags
        self._add_tags()

    def _create_dr_kms_key(self) -> kms.Key:
        """Create KMS key for DR region backup encryption."""
        key = kms.Key(
            self, "DRBackupKMSKey",
            description="KMS key for DR region backup encryption",
            enable_key_rotation=True,
            removal_policy=RemovalPolicy.DESTROY,
            policy=iam.PolicyDocument(
                statements=[
                    iam.PolicyStatement(
                        sid="Enable IAM User Permissions",
                        effect=iam.Effect.ALLOW,
                        principals=[iam.AccountRootPrincipal()],
                        actions=["kms:*"],
                        resources=["*"]
                    ),
                    iam.PolicyStatement(
                        sid="Allow AWS Backup to use the key",
                        effect=iam.Effect.ALLOW,
                        principals=[iam.ServicePrincipal("backup.amazonaws.com")],
                        actions=[
                            "kms:Decrypt",
                            "kms:GenerateDataKey",
                            "kms:CreateGrant",
                            "kms:RetireGrant",
                            "kms:DescribeKey"
                        ],
                        resources=["*"]
                    )
                ]
            )
        )
        
        # Create alias for the key
        kms.Alias(
            self, "DRBackupKMSKeyAlias",
            alias_name="alias/rds-backup-key-dr",
            target_key=key
        )
        
        return key

    def _create_dr_backup_vault(self) -> backup.BackupVault:
        """Create backup vault in DR region."""
        vault = backup.BackupVault(
            self, "DRBackupVault",
            backup_vault_name="rds-backup-vault-dr",
            encryption_key=self.dr_kms_key,
            removal_policy=RemovalPolicy.DESTROY
        )
        
        return vault

    def _create_outputs(self) -> None:
        """Create outputs for DR region resources."""
        CfnOutput(
            self, "DRBackupVaultName",
            value=self.dr_backup_vault.backup_vault_name,
            description="DR region backup vault name"
        )
        
        CfnOutput(
            self, "DRKMSKeyId",
            value=self.dr_kms_key.key_id,
            description="DR region KMS key ID"
        )

    def _add_tags(self) -> None:
        """Add tags to DR region resources."""
        Tags.of(self).add("Project", "DatabaseBackupRecovery")
        Tags.of(self).add("Environment", "disaster-recovery")
        Tags.of(self).add("ManagedBy", "CDK")
        Tags.of(self).add("Region", "DR")


def main() -> None:
    """Main function to create and deploy the CDK application."""
    app = cdk.App()
    
    # Get configuration from context or environment variables
    primary_region = app.node.try_get_context("primary_region") or "us-east-1"
    dr_region = app.node.try_get_context("dr_region") or "us-west-2"
    
    # Create primary stack
    primary_stack = DatabaseBackupRecoveryStack(
        app, "DatabaseBackupRecoveryStack",
        env=Environment(region=primary_region),
        description="Database backup and point-in-time recovery solution"
    )
    
    # Create DR stack
    dr_stack = CrossRegionReplicationStack(
        app, "CrossRegionReplicationStack",
        primary_region=primary_region,
        primary_kms_key_arn=primary_stack.backup_kms_key.key_arn,
        env=Environment(region=dr_region),
        description="Cross-region backup replication resources"
    )
    
    # Add dependency
    dr_stack.add_dependency(primary_stack)
    
    app.synth()


if __name__ == "__main__":
    main()