#!/usr/bin/env python3
"""
AWS CDK Python Application for Database Migration with AWS DMS

This CDK application implements a complete database migration solution using AWS DMS,
including replication instances, endpoints, migration tasks, and monitoring.
"""

import aws_cdk as cdk
from aws_cdk import (
    App,
    Stack,
    Duration,
    RemovalPolicy,
    aws_dms as dms,
    aws_ec2 as ec2,
    aws_iam as iam,
    aws_sns as sns,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
    CfnOutput,
)
from constructs import Construct
from typing import Dict, Any, List, Optional


class DatabaseMigrationStack(Stack):
    """
    CDK Stack for AWS Database Migration Service (DMS) infrastructure.
    
    This stack creates:
    - DMS Replication Instance with Multi-AZ support
    - DMS Subnet Group for network isolation
    - DMS Source and Target Endpoints
    - DMS Migration Task with full load and CDC
    - SNS Topic for event notifications
    - CloudWatch Alarms for monitoring
    - IAM roles and policies for DMS operations
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        vpc: Optional[ec2.IVpc] = None,
        source_database_config: Optional[Dict[str, Any]] = None,
        target_database_config: Optional[Dict[str, Any]] = None,
        **kwargs
    ) -> None:
        """
        Initialize the Database Migration Stack.
        
        Args:
            scope: CDK scope
            construct_id: Construct identifier
            vpc: VPC for DMS resources (optional, will use default if not provided)
            source_database_config: Source database configuration
            target_database_config: Target database configuration
            **kwargs: Additional stack arguments
        """
        super().__init__(scope, construct_id, **kwargs)

        # Use provided VPC or create/reference default VPC
        self.vpc = vpc or ec2.Vpc.from_lookup(self, "DefaultVpc", is_default=True)
        
        # Create SNS topic for notifications
        self.notification_topic = self._create_notification_topic()
        
        # Create DMS service role
        self.dms_service_role = self._create_dms_service_role()
        
        # Create DMS subnet group
        self.subnet_group = self._create_subnet_group()
        
        # Create DMS replication instance
        self.replication_instance = self._create_replication_instance()
        
        # Create DMS endpoints
        self.source_endpoint = self._create_source_endpoint(source_database_config)
        self.target_endpoint = self._create_target_endpoint(target_database_config)
        
        # Create migration task
        self.migration_task = self._create_migration_task()
        
        # Create event subscription
        self.event_subscription = self._create_event_subscription()
        
        # Create CloudWatch alarms
        self._create_cloudwatch_alarms()
        
        # Create CloudWatch log group
        self.log_group = self._create_log_group()
        
        # Create outputs
        self._create_outputs()

    def _create_notification_topic(self) -> sns.Topic:
        """Create SNS topic for DMS event notifications."""
        topic = sns.Topic(
            self,
            "DMSNotificationTopic",
            topic_name=f"dms-migration-alerts-{self.node.addr}",
            display_name="DMS Migration Alerts",
            description="SNS topic for DMS migration event notifications"
        )
        
        # Add tags
        cdk.Tags.of(topic).add("Project", "DatabaseMigration")
        cdk.Tags.of(topic).add("Component", "Notifications")
        
        return topic

    def _create_dms_service_role(self) -> iam.Role:
        """Create IAM role for DMS service operations."""
        # DMS service role
        role = iam.Role(
            self,
            "DMSServiceRole",
            role_name="dms-access-for-endpoint",
            assumed_by=iam.ServicePrincipal("dms.amazonaws.com"),
            description="IAM role for DMS service operations",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AmazonDMSRedshiftS3Role"),
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AmazonDMSCloudWatchLogsRole")
            ]
        )
        
        # Add custom policy for additional permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "ec2:CreateNetworkInterface",
                    "ec2:DescribeNetworkInterfaces",
                    "ec2:DeleteNetworkInterface",
                    "ec2:DescribeVpcs",
                    "ec2:DescribeSubnets",
                    "ec2:DescribeSecurityGroups",
                    "rds:DescribeDBInstances",
                    "rds:DescribeDBClusters"
                ],
                resources=["*"]
            )
        )
        
        return role

    def _create_subnet_group(self) -> dms.CfnReplicationSubnetGroup:
        """Create DMS replication subnet group."""
        # Get subnet IDs from VPC
        subnet_ids = [subnet.subnet_id for subnet in self.vpc.private_subnets]
        
        # If no private subnets, use public subnets
        if not subnet_ids:
            subnet_ids = [subnet.subnet_id for subnet in self.vpc.public_subnets]
        
        subnet_group = dms.CfnReplicationSubnetGroup(
            self,
            "DMSSubnetGroup",
            replication_subnet_group_identifier=f"dms-subnet-group-{self.node.addr}",
            replication_subnet_group_description="DMS subnet group for database migration",
            subnet_ids=subnet_ids,
            tags=[
                {"Key": "Project", "Value": "DatabaseMigration"},
                {"Key": "Component", "Value": "Networking"}
            ]
        )
        
        return subnet_group

    def _create_replication_instance(self) -> dms.CfnReplicationInstance:
        """Create DMS replication instance with Multi-AZ support."""
        # Create security group for DMS replication instance
        security_group = ec2.SecurityGroup(
            self,
            "DMSSecurityGroup",
            vpc=self.vpc,
            description="Security group for DMS replication instance",
            allow_all_outbound=True
        )
        
        # Allow inbound connections from within VPC
        security_group.add_ingress_rule(
            peer=ec2.Peer.ipv4(self.vpc.vpc_cidr_block),
            connection=ec2.Port.all_traffic(),
            description="Allow all traffic from VPC"
        )
        
        replication_instance = dms.CfnReplicationInstance(
            self,
            "DMSReplicationInstance",
            replication_instance_identifier=f"dms-replication-{self.node.addr}",
            replication_instance_class="dms.t3.medium",
            allocated_storage=100,
            replication_subnet_group_identifier=self.subnet_group.replication_subnet_group_identifier,
            vpc_security_group_ids=[security_group.security_group_id],
            multi_az=True,
            publicly_accessible=False,
            auto_minor_version_upgrade=True,
            preferred_maintenance_window="sun:05:00-sun:06:00",
            tags=[
                {"Key": "Project", "Value": "DatabaseMigration"},
                {"Key": "Environment", "Value": "Production"},
                {"Key": "Component", "Value": "ReplicationInstance"}
            ]
        )
        
        # Add dependency on subnet group
        replication_instance.add_dependency(self.subnet_group)
        
        return replication_instance

    def _create_source_endpoint(self, config: Optional[Dict[str, Any]]) -> dms.CfnEndpoint:
        """Create DMS source endpoint."""
        # Default configuration for MySQL source
        default_config = {
            "engine_name": "mysql",
            "server_name": "source-db-server.example.com",
            "port": 3306,
            "database_name": "sourcedb",
            "username": "migration_user",
            "password": "CHANGE_ME_SOURCE_PASSWORD"
        }
        
        endpoint_config = config or default_config
        
        source_endpoint = dms.CfnEndpoint(
            self,
            "DMSSourceEndpoint",
            endpoint_identifier=f"dms-source-{self.node.addr}",
            endpoint_type="source",
            engine_name=endpoint_config["engine_name"],
            server_name=endpoint_config["server_name"],
            port=endpoint_config["port"],
            database_name=endpoint_config["database_name"],
            username=endpoint_config["username"],
            password=endpoint_config["password"],
            ssl_mode="require",
            tags=[
                {"Key": "Project", "Value": "DatabaseMigration"},
                {"Key": "Type", "Value": "Source"},
                {"Key": "Engine", "Value": endpoint_config["engine_name"]}
            ]
        )
        
        return source_endpoint

    def _create_target_endpoint(self, config: Optional[Dict[str, Any]]) -> dms.CfnEndpoint:
        """Create DMS target endpoint."""
        # Default configuration for RDS MySQL target
        default_config = {
            "engine_name": "mysql",
            "server_name": "target-rds-instance.region.rds.amazonaws.com",
            "port": 3306,
            "database_name": "targetdb",
            "username": "admin",
            "password": "CHANGE_ME_TARGET_PASSWORD"
        }
        
        endpoint_config = config or default_config
        
        target_endpoint = dms.CfnEndpoint(
            self,
            "DMSTargetEndpoint",
            endpoint_identifier=f"dms-target-{self.node.addr}",
            endpoint_type="target",
            engine_name=endpoint_config["engine_name"],
            server_name=endpoint_config["server_name"],
            port=endpoint_config["port"],
            database_name=endpoint_config["database_name"],
            username=endpoint_config["username"],
            password=endpoint_config["password"],
            ssl_mode="require",
            tags=[
                {"Key": "Project", "Value": "DatabaseMigration"},
                {"Key": "Type", "Value": "Target"},
                {"Key": "Engine", "Value": endpoint_config["engine_name"]}
            ]
        )
        
        return target_endpoint

    def _create_migration_task(self) -> dms.CfnReplicationTask:
        """Create DMS migration task with full load and CDC."""
        # Table mappings configuration
        table_mappings = {
            "rules": [
                {
                    "rule-type": "selection",
                    "rule-id": "1",
                    "rule-name": "include-all-tables",
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
                    "rule-name": "add-prefix",
                    "rule-target": "table",
                    "object-locator": {
                        "schema-name": "%",
                        "table-name": "%"
                    },
                    "rule-action": "add-prefix",
                    "value": "migrated_"
                }
            ]
        }
        
        # Replication task settings
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
                "ParallelApplyThreads": 0,
                "ParallelApplyBufferSize": 0,
                "ParallelApplyQueuesPerThread": 0
            },
            "FullLoadSettings": {
                "TargetTablePrepMode": "DROP_AND_CREATE",
                "CreatePkAfterFullLoad": False,
                "StopTaskCachedChangesApplied": False,
                "StopTaskCachedChangesNotApplied": False,
                "MaxFullLoadSubTasks": 8,
                "TransactionConsistencyTimeout": 600,
                "CommitRate": 10000
            },
            "Logging": {
                "EnableLogging": True,
                "LogComponents": [
                    {
                        "Id": "SOURCE_UNLOAD",
                        "Severity": "LOGGER_SEVERITY_DEFAULT"
                    },
                    {
                        "Id": "TARGET_LOAD",
                        "Severity": "LOGGER_SEVERITY_DEFAULT"
                    },
                    {
                        "Id": "SOURCE_CAPTURE",
                        "Severity": "LOGGER_SEVERITY_DEFAULT"
                    },
                    {
                        "Id": "TARGET_APPLY",
                        "Severity": "LOGGER_SEVERITY_DEFAULT"
                    }
                ]
            },
            "ValidationSettings": {
                "EnableValidation": True,
                "ValidationMode": "ROW_LEVEL",
                "ThreadCount": 5,
                "PartitionSize": 10000,
                "FailureMaxCount": 10000,
                "RecordFailureDelayInMinutes": 5,
                "RecordSuspendDelayInMinutes": 30,
                "MaxKeyColumnSize": 8096,
                "TableFailureMaxCount": 1000,
                "ValidationOnly": False,
                "HandleCollationDiff": False,
                "RecordFailureDelayLimitInMinutes": 0,
                "SkipLobColumns": False,
                "ValidationPartialLobSize": 0,
                "ValidationQueryCdcDelaySeconds": 0
            },
            "ErrorBehavior": {
                "DataErrorPolicy": "LOG_ERROR",
                "DataTruncationErrorPolicy": "LOG_ERROR",
                "DataErrorEscalationPolicy": "SUSPEND_TABLE",
                "DataErrorEscalationCount": 0,
                "TableErrorPolicy": "SUSPEND_TABLE",
                "TableErrorEscalationPolicy": "STOP_TASK",
                "TableErrorEscalationCount": 0,
                "RecoverableErrorCount": -1,
                "RecoverableErrorInterval": 5,
                "RecoverableErrorThrottling": True,
                "RecoverableErrorThrottlingMax": 1800,
                "RecoverableErrorStopRetryAfterThrottlingMax": True,
                "ApplyErrorDeletePolicy": "IGNORE_RECORD",
                "ApplyErrorInsertPolicy": "LOG_ERROR",
                "ApplyErrorUpdatePolicy": "LOG_ERROR",
                "ApplyErrorEscalationPolicy": "LOG_ERROR",
                "ApplyErrorEscalationCount": 0,
                "ApplyErrorFailOnTruncationDdl": False,
                "FullLoadIgnoreConflicts": True,
                "FailOnTransactionConsistencyBreached": False,
                "FailOnNoTablesCaptured": True
            }
        }
        
        migration_task = dms.CfnReplicationTask(
            self,
            "DMSMigrationTask",
            replication_task_identifier=f"dms-migration-task-{self.node.addr}",
            source_endpoint_arn=self.source_endpoint.ref,
            target_endpoint_arn=self.target_endpoint.ref,
            replication_instance_arn=self.replication_instance.ref,
            migration_type="full-load-and-cdc",
            table_mappings=cdk.Fn.to_json_string(table_mappings),
            replication_task_settings=cdk.Fn.to_json_string(task_settings),
            tags=[
                {"Key": "Project", "Value": "DatabaseMigration"},
                {"Key": "Environment", "Value": "Production"},
                {"Key": "MigrationType", "Value": "full-load-and-cdc"}
            ]
        )
        
        # Add dependencies
        migration_task.add_dependency(self.replication_instance)
        migration_task.add_dependency(self.source_endpoint)
        migration_task.add_dependency(self.target_endpoint)
        
        return migration_task

    def _create_event_subscription(self) -> dms.CfnEventSubscription:
        """Create DMS event subscription for monitoring."""
        event_subscription = dms.CfnEventSubscription(
            self,
            "DMSEventSubscription",
            subscription_name=f"dms-migration-events-{self.node.addr}",
            sns_topic_arn=self.notification_topic.topic_arn,
            source_type="replication-task",
            event_categories=["failure", "creation", "deletion", "state change"],
            source_ids=[self.migration_task.replication_task_identifier],
            enabled=True,
            tags=[
                {"Key": "Project", "Value": "DatabaseMigration"},
                {"Key": "Component", "Value": "Monitoring"}
            ]
        )
        
        # Add dependency on migration task
        event_subscription.add_dependency(self.migration_task)
        
        return event_subscription

    def _create_cloudwatch_alarms(self) -> None:
        """Create CloudWatch alarms for DMS monitoring."""
        # Task failure alarm
        task_failure_alarm = cloudwatch.Alarm(
            self,
            "DMSTaskFailureAlarm",
            alarm_name=f"DMS-Task-Failure-{self.node.addr}",
            alarm_description="Alert when DMS task fails",
            metric=cloudwatch.Metric(
                namespace="AWS/DMS",
                metric_name="ReplicationTaskStatus",
                dimensions_map={
                    "ReplicationTaskIdentifier": self.migration_task.replication_task_identifier
                },
                statistic="Average",
                period=Duration.minutes(5)
            ),
            threshold=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
            evaluation_periods=1,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        
        # Add SNS action
        task_failure_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.notification_topic)
        )
        
        # High latency alarm
        high_latency_alarm = cloudwatch.Alarm(
            self,
            "DMSHighLatencyAlarm",
            alarm_name=f"DMS-High-Latency-{self.node.addr}",
            alarm_description="Alert when DMS replication latency is high",
            metric=cloudwatch.Metric(
                namespace="AWS/DMS",
                metric_name="CDCLatencySource",
                dimensions_map={
                    "ReplicationTaskIdentifier": self.migration_task.replication_task_identifier
                },
                statistic="Average",
                period=Duration.minutes(5)
            ),
            threshold=300,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        
        # Add SNS action
        high_latency_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.notification_topic)
        )

    def _create_log_group(self) -> logs.LogGroup:
        """Create CloudWatch log group for DMS logs."""
        log_group = logs.LogGroup(
            self,
            "DMSLogGroup",
            log_group_name=f"/aws/dms/migration-task-{self.node.addr}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY
        )
        
        return log_group

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs."""
        CfnOutput(
            self,
            "ReplicationInstanceArn",
            value=self.replication_instance.ref,
            description="ARN of the DMS replication instance",
            export_name=f"{self.stack_name}-ReplicationInstanceArn"
        )
        
        CfnOutput(
            self,
            "SourceEndpointArn",
            value=self.source_endpoint.ref,
            description="ARN of the DMS source endpoint",
            export_name=f"{self.stack_name}-SourceEndpointArn"
        )
        
        CfnOutput(
            self,
            "TargetEndpointArn",
            value=self.target_endpoint.ref,
            description="ARN of the DMS target endpoint",
            export_name=f"{self.stack_name}-TargetEndpointArn"
        )
        
        CfnOutput(
            self,
            "MigrationTaskArn",
            value=self.migration_task.ref,
            description="ARN of the DMS migration task",
            export_name=f"{self.stack_name}-MigrationTaskArn"
        )
        
        CfnOutput(
            self,
            "NotificationTopicArn",
            value=self.notification_topic.topic_arn,
            description="ARN of the SNS notification topic",
            export_name=f"{self.stack_name}-NotificationTopicArn"
        )
        
        CfnOutput(
            self,
            "LogGroupName",
            value=self.log_group.log_group_name,
            description="Name of the CloudWatch log group",
            export_name=f"{self.stack_name}-LogGroupName"
        )


def main() -> None:
    """Main application entry point."""
    app = App()
    
    # Get context values for configuration
    env = cdk.Environment(
        account=app.node.try_get_context("account") or None,
        region=app.node.try_get_context("region") or None
    )
    
    # Source database configuration
    source_config = {
        "engine_name": app.node.try_get_context("source_engine") or "mysql",
        "server_name": app.node.try_get_context("source_server") or "source-db-server.example.com",
        "port": int(app.node.try_get_context("source_port") or 3306),
        "database_name": app.node.try_get_context("source_database") or "sourcedb",
        "username": app.node.try_get_context("source_username") or "migration_user",
        "password": app.node.try_get_context("source_password") or "CHANGE_ME_SOURCE_PASSWORD"
    }
    
    # Target database configuration
    target_config = {
        "engine_name": app.node.try_get_context("target_engine") or "mysql",
        "server_name": app.node.try_get_context("target_server") or "target-rds-instance.region.rds.amazonaws.com",
        "port": int(app.node.try_get_context("target_port") or 3306),
        "database_name": app.node.try_get_context("target_database") or "targetdb",
        "username": app.node.try_get_context("target_username") or "admin",
        "password": app.node.try_get_context("target_password") or "CHANGE_ME_TARGET_PASSWORD"
    }
    
    # Create the stack
    DatabaseMigrationStack(
        app,
        "DatabaseMigrationStack",
        source_database_config=source_config,
        target_database_config=target_config,
        env=env,
        description="AWS CDK stack for Database Migration with AWS DMS"
    )
    
    app.synth()


if __name__ == "__main__":
    main()