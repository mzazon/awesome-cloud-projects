#!/usr/bin/env python3
"""
AWS CDK Python application for Database Migration Strategies with AWS DMS

This CDK application implements a comprehensive database migration infrastructure
using AWS Database Migration Service (DMS) with replication instances, endpoints,
and migration tasks for minimal downtime database migrations.

Architecture:
- DMS replication instance with Multi-AZ deployment
- Source and target database endpoints
- Migration tasks with full-load-and-cdc capabilities
- S3 bucket for migration logs and monitoring
- CloudWatch monitoring and alerting
- VPC and networking components

Author: AWS CDK Generator
Version: 1.0.0
"""

import os
from typing import Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    App,
    CfnOutput,
    Duration,
    Environment,
    RemovalPolicy,
    Stack,
    StackProps,
    aws_dms as dms,
    aws_ec2 as ec2,
    aws_iam as iam,
    aws_logs as logs,
    aws_s3 as s3,
    aws_sns as sns,
    aws_cloudwatch as cloudwatch,
    aws_cloudwatch_actions as cw_actions,
)
from constructs import Construct


class DatabaseMigrationDmsStack(Stack):
    """
    CDK Stack for AWS Database Migration Service infrastructure.
    
    This stack creates all necessary resources for database migration including:
    - VPC and networking infrastructure
    - DMS replication instance with Multi-AZ deployment
    - Source and target database endpoints
    - Migration tasks with CDC capabilities
    - Monitoring and logging infrastructure
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        vpc_cidr: str = "10.0.0.0/16",
        source_db_config: Optional[Dict] = None,
        target_db_config: Optional[Dict] = None,
        replication_instance_class: str = "dms.t3.medium",
        enable_multi_az: bool = True,
        allocated_storage: int = 100,
        **kwargs
    ) -> None:
        """
        Initialize the Database Migration DMS Stack.
        
        Args:
            scope: CDK construct scope
            construct_id: Unique identifier for this construct
            vpc_cidr: CIDR block for the VPC (default: 10.0.0.0/16)
            source_db_config: Source database configuration parameters
            target_db_config: Target database configuration parameters
            replication_instance_class: DMS replication instance class
            enable_multi_az: Enable Multi-AZ deployment for high availability
            allocated_storage: Storage allocation for replication instance (GB)
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)

        # Store configuration
        self.source_db_config = source_db_config or {}
        self.target_db_config = target_db_config or {}
        
        # Create unique suffix for resource naming
        self.unique_suffix = self.node.addr[-8:].lower()

        # Create networking infrastructure
        self.vpc = self._create_vpc(vpc_cidr)
        
        # Create S3 bucket for migration logs
        self.migration_logs_bucket = self._create_s3_bucket()
        
        # Create CloudWatch resources
        self.log_group = self._create_log_group()
        self.sns_topic = self._create_sns_topic()
        
        # Create DMS IAM roles
        self.dms_roles = self._create_dms_iam_roles()
        
        # Create DMS subnet group
        self.subnet_group = self._create_dms_subnet_group()
        
        # Create DMS replication instance
        self.replication_instance = self._create_replication_instance(
            instance_class=replication_instance_class,
            multi_az=enable_multi_az,
            allocated_storage=allocated_storage
        )
        
        # Create database endpoints
        self.source_endpoint = self._create_source_endpoint()
        self.target_endpoint = self._create_target_endpoint()
        
        # Create migration tasks
        self.migration_task = self._create_migration_task()
        self.cdc_task = self._create_cdc_task()
        
        # Create CloudWatch alarms
        self._create_cloudwatch_alarms()
        
        # Create stack outputs
        self._create_outputs()

    def _create_vpc(self, vpc_cidr: str) -> ec2.Vpc:
        """
        Create VPC with public and private subnets across multiple AZs.
        
        Args:
            vpc_cidr: CIDR block for the VPC
            
        Returns:
            ec2.Vpc: The created VPC
        """
        vpc = ec2.Vpc(
            self,
            "DmsMigrationVpc",
            ip_addresses=ec2.IpAddresses.cidr(vpc_cidr),
            max_azs=3,
            nat_gateways=1,
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    subnet_type=ec2.SubnetType.PUBLIC,
                    name="Public",
                    cidr_mask=24,
                ),
                ec2.SubnetConfiguration(
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                    name="Private",
                    cidr_mask=24,
                ),
                ec2.SubnetConfiguration(
                    subnet_type=ec2.SubnetType.PRIVATE_ISOLATED,
                    name="Database",
                    cidr_mask=24,
                ),
            ],
            enable_dns_hostnames=True,
            enable_dns_support=True,
        )

        # Tag VPC and subnets for identification
        cdk.Tags.of(vpc).add("Name", f"dms-migration-vpc-{self.unique_suffix}")
        cdk.Tags.of(vpc).add("Environment", "migration")
        cdk.Tags.of(vpc).add("Purpose", "database-migration")

        return vpc

    def _create_s3_bucket(self) -> s3.Bucket:
        """
        Create S3 bucket for storing DMS migration logs and artifacts.
        
        Returns:
            s3.Bucket: The created S3 bucket
        """
        bucket = s3.Bucket(
            self,
            "DmsMigrationLogsBucket",
            bucket_name=f"dms-migration-logs-{self.unique_suffix}",
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            versioned=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteOldLogs",
                    enabled=True,
                    expiration=Duration.days(90),
                    noncurrent_version_expiration=Duration.days(30),
                )
            ],
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        # Add tags
        cdk.Tags.of(bucket).add("Name", f"dms-migration-logs-{self.unique_suffix}")
        cdk.Tags.of(bucket).add("Environment", "migration")
        cdk.Tags.of(bucket).add("Purpose", "dms-logging")

        return bucket

    def _create_log_group(self) -> logs.LogGroup:
        """
        Create CloudWatch log group for DMS task logging.
        
        Returns:
            logs.LogGroup: The created log group
        """
        log_group = logs.LogGroup(
            self,
            "DmsTaskLogGroup",
            log_group_name=f"/aws/dms/tasks/dms-replication-{self.unique_suffix}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY,
        )

        return log_group

    def _create_sns_topic(self) -> sns.Topic:
        """
        Create SNS topic for DMS alerts and notifications.
        
        Returns:
            sns.Topic: The created SNS topic
        """
        topic = sns.Topic(
            self,
            "DmsAlertsTopic",
            topic_name=f"dms-alerts-{self.unique_suffix}",
            display_name="DMS Migration Alerts",
        )

        return topic

    def _create_dms_iam_roles(self) -> Dict[str, iam.Role]:
        """
        Create required IAM roles for DMS service.
        
        Returns:
            Dict[str, iam.Role]: Dictionary of created IAM roles
        """
        roles = {}

        # DMS VPC role
        vpc_role = iam.Role(
            self,
            "DmsVpcRole",
            role_name="dms-vpc-role",
            assumed_by=iam.ServicePrincipal("dms.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AmazonDMSVPCManagementRole")
            ],
        )
        roles["vpc"] = vpc_role

        # DMS CloudWatch logs role
        cloudwatch_role = iam.Role(
            self,
            "DmsCloudWatchRole",
            role_name="dms-cloudwatch-logs-role",
            assumed_by=iam.ServicePrincipal("dms.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AmazonDMSCloudWatchLogsRole")
            ],
        )
        roles["cloudwatch"] = cloudwatch_role

        # DMS S3 access role
        s3_role = iam.Role(
            self,
            "DmsS3Role",
            role_name=f"dms-s3-role-{self.unique_suffix}",
            assumed_by=iam.ServicePrincipal("dms.amazonaws.com"),
            inline_policies={
                "DmsS3Access": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:GetObject",
                                "s3:PutObject",
                                "s3:DeleteObject",
                                "s3:ListBucket",
                            ],
                            resources=[
                                self.migration_logs_bucket.bucket_arn,
                                f"{self.migration_logs_bucket.bucket_arn}/*",
                            ],
                        )
                    ]
                )
            },
        )
        roles["s3"] = s3_role

        return roles

    def _create_dms_subnet_group(self) -> dms.CfnReplicationSubnetGroup:
        """
        Create DMS replication subnet group.
        
        Returns:
            dms.CfnReplicationSubnetGroup: The created subnet group
        """
        # Get subnet IDs from private subnets
        subnet_ids = [subnet.subnet_id for subnet in self.vpc.private_subnets]

        subnet_group = dms.CfnReplicationSubnetGroup(
            self,
            "DmsSubnetGroup",
            replication_subnet_group_identifier=f"dms-subnet-group-{self.unique_suffix}",
            replication_subnet_group_description="DMS subnet group for migration",
            subnet_ids=subnet_ids,
            tags=[
                {"Key": "Name", "Value": f"dms-subnet-group-{self.unique_suffix}"},
                {"Key": "Environment", "Value": "migration"},
                {"Key": "Purpose", "Value": "database-migration"},
            ],
        )

        return subnet_group

    def _create_replication_instance(
        self,
        instance_class: str,
        multi_az: bool,
        allocated_storage: int
    ) -> dms.CfnReplicationInstance:
        """
        Create DMS replication instance.
        
        Args:
            instance_class: EC2 instance class for replication instance
            multi_az: Enable Multi-AZ deployment
            allocated_storage: Allocated storage in GB
            
        Returns:
            dms.CfnReplicationInstance: The created replication instance
        """
        replication_instance = dms.CfnReplicationInstance(
            self,
            "DmsReplicationInstance",
            replication_instance_identifier=f"dms-replication-{self.unique_suffix}",
            replication_instance_class=instance_class,
            allocated_storage=allocated_storage,
            multi_az=multi_az,
            engine_version="3.5.2",
            replication_subnet_group_identifier=self.subnet_group.replication_subnet_group_identifier,
            publicly_accessible=False,
            auto_minor_version_upgrade=True,
            allow_major_version_upgrade=False,
            apply_immediately=True,
            tags=[
                {"Key": "Name", "Value": f"dms-replication-{self.unique_suffix}"},
                {"Key": "Environment", "Value": "migration"},
                {"Key": "Purpose", "Value": "database-migration"},
            ],
        )

        # Add dependency on subnet group
        replication_instance.add_dependency(self.subnet_group)

        return replication_instance

    def _create_source_endpoint(self) -> dms.CfnEndpoint:
        """
        Create DMS source endpoint configuration.
        
        Returns:
            dms.CfnEndpoint: The created source endpoint
        """
        # Default MySQL source configuration
        default_config = {
            "engine_name": "mysql",
            "server_name": "source-db-hostname.com",
            "port": 3306,
            "database_name": "source_database",
            "username": "source_user",
            "password": "source_password",
            "extra_connection_attributes": "initstmt=SET foreign_key_checks=0"
        }
        
        # Merge with provided configuration
        config = {**default_config, **self.source_db_config}

        source_endpoint = dms.CfnEndpoint(
            self,
            "DmsSourceEndpoint",
            endpoint_identifier=f"source-endpoint-{self.unique_suffix}",
            endpoint_type="source",
            engine_name=config["engine_name"],
            server_name=config["server_name"],
            port=config["port"],
            database_name=config["database_name"],
            username=config["username"],
            password=config["password"],
            extra_connection_attributes=config["extra_connection_attributes"],
            ssl_mode="none",  # Configure based on your security requirements
            tags=[
                {"Key": "Name", "Value": f"source-endpoint-{self.unique_suffix}"},
                {"Key": "Environment", "Value": "migration"},
                {"Key": "EndpointType", "Value": "source"},
            ],
        )

        return source_endpoint

    def _create_target_endpoint(self) -> dms.CfnEndpoint:
        """
        Create DMS target endpoint configuration.
        
        Returns:
            dms.CfnEndpoint: The created target endpoint
        """
        # Default RDS MySQL target configuration
        default_config = {
            "engine_name": "mysql",
            "server_name": "target-rds-hostname.com",
            "port": 3306,
            "database_name": "target_database",
            "username": "target_user",
            "password": "target_password",
            "extra_connection_attributes": "initstmt=SET foreign_key_checks=0"
        }
        
        # Merge with provided configuration
        config = {**default_config, **self.target_db_config}

        target_endpoint = dms.CfnEndpoint(
            self,
            "DmsTargetEndpoint",
            endpoint_identifier=f"target-endpoint-{self.unique_suffix}",
            endpoint_type="target",
            engine_name=config["engine_name"],
            server_name=config["server_name"],
            port=config["port"],
            database_name=config["database_name"],
            username=config["username"],
            password=config["password"],
            extra_connection_attributes=config["extra_connection_attributes"],
            ssl_mode="none",  # Configure based on your security requirements
            tags=[
                {"Key": "Name", "Value": f"target-endpoint-{self.unique_suffix}"},
                {"Key": "Environment", "Value": "migration"},
                {"Key": "EndpointType", "Value": "target"},
            ],
        )

        return target_endpoint

    def _create_migration_task(self) -> dms.CfnReplicationTask:
        """
        Create DMS migration task for full-load-and-cdc.
        
        Returns:
            dms.CfnReplicationTask: The created migration task
        """
        # Table mapping configuration
        table_mappings = {
            "rules": [
                {
                    "rule-type": "selection",
                    "rule-id": "1",
                    "rule-name": "1",
                    "object-locator": {
                        "schema-name": "%",
                        "table-name": "%"
                    },
                    "rule-action": "include",
                    "filters": []
                },
                {
                    "rule-type": "transformation",
                    "rule-id": "2",
                    "rule-name": "2",
                    "rule-target": "schema",
                    "object-locator": {
                        "schema-name": "%"
                    },
                    "rule-action": "rename",
                    "value": "migrated_${schema-name}"
                }
            ]
        }

        # Task settings configuration
        task_settings = {
            "TargetMetadata": {
                "TargetSchema": "",
                "SupportLobs": True,
                "FullLobMode": False,
                "LobChunkSize": 0,
                "LimitedSizeLobMode": True,
                "LobMaxSize": 32,
                "InlineLobMaxSize": 0,
                "LoadMaxFileSize": 0,
                "ParallelLoadThreads": 0,
                "ParallelLoadBufferSize": 0,
                "BatchApplyEnabled": False,
                "TaskRecoveryTableEnabled": False,
            },
            "FullLoadSettings": {
                "TargetTablePrepMode": "DROP_AND_CREATE",
                "CreatePkAfterFullLoad": False,
                "StopTaskCachedChangesApplied": False,
                "StopTaskCachedChangesNotApplied": False,
                "MaxFullLoadSubTasks": 8,
                "TransactionConsistencyTimeout": 600,
                "CommitRate": 10000,
            },
            "Logging": {
                "EnableLogging": True,
                "LogComponents": [
                    {"Id": "SOURCE_UNLOAD", "Severity": "LOGGER_SEVERITY_DEFAULT"},
                    {"Id": "TARGET_LOAD", "Severity": "LOGGER_SEVERITY_DEFAULT"},
                    {"Id": "SOURCE_CAPTURE", "Severity": "LOGGER_SEVERITY_DEFAULT"},
                    {"Id": "TARGET_APPLY", "Severity": "LOGGER_SEVERITY_DEFAULT"},
                ],
                "CloudWatchLogGroup": self.log_group.log_group_name,
                "CloudWatchLogStream": f"dms-task-{self.unique_suffix}",
            },
            "ValidationSettings": {
                "EnableValidation": True,
                "ValidationMode": "ROW_LEVEL",
                "ThreadCount": 5,
                "PartitionSize": 10000,
                "FailureMaxCount": 10000,
            },
            "ErrorBehavior": {
                "DataErrorPolicy": "LOG_ERROR",
                "DataTruncationErrorPolicy": "LOG_ERROR",
                "DataErrorEscalationPolicy": "SUSPEND_TABLE",
                "TableErrorPolicy": "SUSPEND_TABLE",
                "TableErrorEscalationPolicy": "STOP_TASK",
                "FullLoadIgnoreConflicts": True,
            },
        }

        migration_task = dms.CfnReplicationTask(
            self,
            "DmsMigrationTask",
            replication_task_identifier=f"migration-task-{self.unique_suffix}",
            source_endpoint_arn=self.source_endpoint.ref,
            target_endpoint_arn=self.target_endpoint.ref,
            replication_instance_arn=self.replication_instance.ref,
            migration_type="full-load-and-cdc",
            table_mappings=cdk.Fn.to_json_string(table_mappings),
            replication_task_settings=cdk.Fn.to_json_string(task_settings),
            tags=[
                {"Key": "Name", "Value": f"migration-task-{self.unique_suffix}"},
                {"Key": "Environment", "Value": "migration"},
                {"Key": "TaskType", "Value": "full-load-and-cdc"},
            ],
        )

        # Add dependencies
        migration_task.add_dependency(self.replication_instance)
        migration_task.add_dependency(self.source_endpoint)
        migration_task.add_dependency(self.target_endpoint)

        return migration_task

    def _create_cdc_task(self) -> dms.CfnReplicationTask:
        """
        Create DMS CDC-only task for ongoing replication.
        
        Returns:
            dms.CfnReplicationTask: The created CDC task
        """
        # Simple table mapping for CDC
        table_mappings = {
            "rules": [
                {
                    "rule-type": "selection",
                    "rule-id": "1",
                    "rule-name": "1",
                    "object-locator": {
                        "schema-name": "%",
                        "table-name": "%"
                    },
                    "rule-action": "include",
                    "filters": []
                }
            ]
        }

        # CDC task settings
        task_settings = {
            "Logging": {
                "EnableLogging": True,
                "LogComponents": [
                    {"Id": "SOURCE_CAPTURE", "Severity": "LOGGER_SEVERITY_DEFAULT"},
                    {"Id": "TARGET_APPLY", "Severity": "LOGGER_SEVERITY_DEFAULT"},
                ],
                "CloudWatchLogGroup": self.log_group.log_group_name,
                "CloudWatchLogStream": f"cdc-task-{self.unique_suffix}",
            },
            "ChangeProcessingTuning": {
                "BatchApplyPreserveTransaction": True,
                "BatchApplyTimeoutMin": 1,
                "BatchApplyTimeoutMax": 30,
                "BatchApplyMemoryLimit": 500,
                "MinTransactionSize": 1000,
                "CommitTimeout": 1,
                "MemoryLimitTotal": 1024,
            },
        }

        cdc_task = dms.CfnReplicationTask(
            self,
            "DmsCdcTask",
            replication_task_identifier=f"cdc-task-{self.unique_suffix}",
            source_endpoint_arn=self.source_endpoint.ref,
            target_endpoint_arn=self.target_endpoint.ref,
            replication_instance_arn=self.replication_instance.ref,
            migration_type="cdc",
            table_mappings=cdk.Fn.to_json_string(table_mappings),
            replication_task_settings=cdk.Fn.to_json_string(task_settings),
            tags=[
                {"Key": "Name", "Value": f"cdc-task-{self.unique_suffix}"},
                {"Key": "Environment", "Value": "migration"},
                {"Key": "TaskType", "Value": "cdc"},
            ],
        )

        # Add dependencies
        cdc_task.add_dependency(self.replication_instance)
        cdc_task.add_dependency(self.source_endpoint)
        cdc_task.add_dependency(self.target_endpoint)

        return cdc_task

    def _create_cloudwatch_alarms(self) -> None:
        """Create CloudWatch alarms for monitoring DMS tasks."""
        
        # Alarm for task failures
        task_failure_alarm = cloudwatch.Alarm(
            self,
            "DmsTaskFailureAlarm",
            alarm_name=f"DMS-Task-Failure-{self.unique_suffix}",
            alarm_description="Monitor DMS task failures",
            metric=cloudwatch.Metric(
                namespace="AWS/DMS",
                metric_name="ReplicationTasksState",
                dimensions_map={
                    "ReplicationTaskIdentifier": self.migration_task.replication_task_identifier
                },
                statistic="Average",
                period=Duration.minutes(5),
            ),
            threshold=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
            evaluation_periods=1,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

        # Add SNS action to alarm
        task_failure_alarm.add_alarm_action(
            cw_actions.SnsAction(self.sns_topic)
        )

        # Alarm for high CDC latency
        cdc_latency_alarm = cloudwatch.Alarm(
            self,
            "DmsCdcLatencyAlarm",
            alarm_name=f"DMS-CDC-Latency-{self.unique_suffix}",
            alarm_description="Monitor CDC replication latency",
            metric=cloudwatch.Metric(
                namespace="AWS/DMS",
                metric_name="CDCLatencyTarget",
                dimensions_map={
                    "ReplicationTaskIdentifier": self.migration_task.replication_task_identifier
                },
                statistic="Average",
                period=Duration.minutes(5),
            ),
            threshold=300,  # 5 minutes
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

        cdc_latency_alarm.add_alarm_action(
            cw_actions.SnsAction(self.sns_topic)
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources."""
        
        CfnOutput(
            self,
            "VpcId",
            value=self.vpc.vpc_id,
            description="VPC ID for the DMS migration infrastructure",
            export_name=f"DmsMigration-VpcId-{self.unique_suffix}",
        )

        CfnOutput(
            self,
            "ReplicationInstanceId",
            value=self.replication_instance.replication_instance_identifier,
            description="DMS Replication Instance Identifier",
            export_name=f"DmsMigration-ReplicationInstanceId-{self.unique_suffix}",
        )

        CfnOutput(
            self,
            "SourceEndpointId",
            value=self.source_endpoint.endpoint_identifier,
            description="DMS Source Endpoint Identifier",
            export_name=f"DmsMigration-SourceEndpointId-{self.unique_suffix}",
        )

        CfnOutput(
            self,
            "TargetEndpointId",
            value=self.target_endpoint.endpoint_identifier,
            description="DMS Target Endpoint Identifier",
            export_name=f"DmsMigration-TargetEndpointId-{self.unique_suffix}",
        )

        CfnOutput(
            self,
            "MigrationTaskId",
            value=self.migration_task.replication_task_identifier,
            description="DMS Migration Task Identifier",
            export_name=f"DmsMigration-MigrationTaskId-{self.unique_suffix}",
        )

        CfnOutput(
            self,
            "CdcTaskId",
            value=self.cdc_task.replication_task_identifier,
            description="DMS CDC Task Identifier",
            export_name=f"DmsMigration-CdcTaskId-{self.unique_suffix}",
        )

        CfnOutput(
            self,
            "LogsBucketName",
            value=self.migration_logs_bucket.bucket_name,
            description="S3 bucket for DMS migration logs",
            export_name=f"DmsMigration-LogsBucketName-{self.unique_suffix}",
        )

        CfnOutput(
            self,
            "SnsTopicArn",
            value=self.sns_topic.topic_arn,
            description="SNS topic for DMS alerts",
            export_name=f"DmsMigration-SnsTopicArn-{self.unique_suffix}",
        )


def main() -> None:
    """Main entry point for the CDK application."""
    
    # Initialize CDK app
    app = App()

    # Get environment configuration
    env = Environment(
        account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
        region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
    )

    # Get configuration from context or environment variables
    source_db_config = app.node.try_get_context("source_db_config") or {}
    target_db_config = app.node.try_get_context("target_db_config") or {}
    
    # Create the DMS migration stack
    DatabaseMigrationDmsStack(
        app,
        "DatabaseMigrationDmsStack",
        env=env,
        source_db_config=source_db_config,
        target_db_config=target_db_config,
        description="AWS CDK stack for Database Migration Service (DMS) infrastructure",
    )

    # Synthesize the app
    app.synth()


if __name__ == "__main__":
    main()