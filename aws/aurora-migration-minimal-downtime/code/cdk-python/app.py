#!/usr/bin/env python3
"""
CDK Python application for Aurora Migration with Minimal Downtime.

This application creates the infrastructure needed for database migration using AWS DMS
and Amazon Aurora, implementing best practices for security, monitoring, and high availability.
"""

import os
from typing import Optional

import aws_cdk as cdk
from aws_cdk import (
    Duration,
    RemovalPolicy,
    Stack,
    StackProps,
    Tags,
    aws_dms as dms,
    aws_ec2 as ec2,
    aws_iam as iam,
    aws_logs as logs,
    aws_rds as rds,
    aws_route53 as route53,
    aws_s3 as s3,
    aws_secretsmanager as secretsmanager,
)
from constructs import Construct


class DatabaseMigrationStack(Stack):
    """
    CDK Stack for Aurora database migration infrastructure.
    
    This stack creates:
    - VPC with subnets for database resources
    - Security groups for Aurora and DMS
    - Aurora MySQL cluster with read replicas
    - DMS replication instance and endpoints
    - Route 53 hosted zone for DNS cutover
    - CloudWatch logging and monitoring
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        source_db_host: str,
        source_db_port: int = 3306,
        source_db_username: str = "admin",
        source_db_name: str = "sourcedb",
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Store source database configuration
        self.source_db_host = source_db_host
        self.source_db_port = source_db_port
        self.source_db_username = source_db_username
        self.source_db_name = source_db_name

        # Create VPC and networking infrastructure
        self._create_vpc()
        
        # Create security groups
        self._create_security_groups()
        
        # Create Aurora cluster
        self._create_aurora_cluster()
        
        # Create DMS infrastructure
        self._create_dms_infrastructure()
        
        # Create Route 53 hosted zone for DNS cutover
        self._create_route53_zone()
        
        # Create monitoring and logging
        self._create_monitoring()
        
        # Output important values
        self._create_outputs()

    def _create_vpc(self) -> None:
        """Create VPC with public and private subnets across multiple AZs."""
        self.vpc = ec2.Vpc(
            self,
            "AuroraMigrationVpc",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=2,
            nat_gateways=1,
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="PublicSubnet",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24,
                ),
                ec2.SubnetConfiguration(
                    name="PrivateSubnet",
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                    cidr_mask=24,
                ),
            ],
            enable_dns_hostnames=True,
            enable_dns_support=True,
        )

        # Create database subnet group
        self.db_subnet_group = rds.SubnetGroup(
            self,
            "AuroraSubnetGroup",
            description="Subnet group for Aurora migration cluster",
            vpc=self.vpc,
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS
            ),
        )

        # Create DMS subnet group
        self.dms_subnet_group = dms.CfnReplicationSubnetGroup(
            self,
            "DmsSubnetGroup",
            replication_subnet_group_description="DMS subnet group for migration",
            subnet_ids=[
                subnet.subnet_id for subnet in self.vpc.private_subnets
            ],
            replication_subnet_group_identifier="dms-migration-subnet-group",
            tags=[
                cdk.CfnTag(key="Name", value="dms-migration-subnet-group"),
                cdk.CfnTag(key="Purpose", value="database-migration"),
            ],
        )

    def _create_security_groups(self) -> None:
        """Create security groups for Aurora and DMS with proper access controls."""
        # Security group for Aurora cluster
        self.aurora_sg = ec2.SecurityGroup(
            self,
            "AuroraSecurityGroup",
            vpc=self.vpc,
            description="Security group for Aurora cluster",
            allow_all_outbound=False,
        )

        # Security group for DMS replication instance
        self.dms_sg = ec2.SecurityGroup(
            self,
            "DmsSecurityGroup",
            vpc=self.vpc,
            description="Security group for DMS replication instance",
            allow_all_outbound=True,
        )

        # Allow DMS to connect to Aurora
        self.aurora_sg.add_ingress_rule(
            peer=self.dms_sg,
            connection=ec2.Port.tcp(3306),
            description="Allow DMS to connect to Aurora",
        )

        # Allow DMS outbound to source database (adjust CIDR as needed)
        self.dms_sg.add_egress_rule(
            peer=ec2.Peer.ipv4("0.0.0.0/0"),
            connection=ec2.Port.tcp(self.source_db_port),
            description="Allow DMS to connect to source database",
        )

        # Allow management access to Aurora from VPC
        self.aurora_sg.add_ingress_rule(
            peer=ec2.Peer.ipv4(self.vpc.vpc_cidr_block),
            connection=ec2.Port.tcp(3306),
            description="Allow VPC access to Aurora",
        )

    def _create_aurora_cluster(self) -> None:
        """Create Aurora MySQL cluster with optimized settings for migration."""
        # Create Aurora cluster parameter group with migration optimizations
        self.cluster_parameter_group = rds.ParameterGroup(
            self,
            "AuroraClusterParameterGroup",
            engine=rds.DatabaseClusterEngine.aurora_mysql(
                version=rds.AuroraMysqlEngineVersion.VER_8_0_35
            ),
            description="Parameter group for Aurora migration cluster",
            parameters={
                "innodb_buffer_pool_size": "{DBInstanceClassMemory*3/4}",
                "max_connections": "1000",
                "innodb_log_file_size": "536870912",
                "innodb_flush_log_at_trx_commit": "2",
                "sync_binlog": "0",
            },
        )

        # Create Aurora DB parameter group for instances
        self.db_parameter_group = rds.ParameterGroup(
            self,
            "AuroraDbParameterGroup",
            engine=rds.DatabaseClusterEngine.aurora_mysql(
                version=rds.AuroraMysqlEngineVersion.VER_8_0_35
            ),
            description="Parameter group for Aurora migration instances",
            parameters={
                "innodb_buffer_pool_size": "{DBInstanceClassMemory*3/4}",
                "query_cache_type": "1",
                "query_cache_size": "67108864",
            },
        )

        # Generate secure password for Aurora
        self.aurora_password = secretsmanager.Secret(
            self,
            "AuroraPassword",
            description="Master password for Aurora cluster",
            generate_secret_string=secretsmanager.SecretStringGenerator(
                exclude_characters=" %+~`#$&*()|[]{}:;<>?!'/\"\\",
                generate_string_key="password",
                password_length=32,
                secret_string_template='{"username": "admin"}',
            ),
        )

        # Create Aurora cluster
        self.aurora_cluster = rds.DatabaseCluster(
            self,
            "AuroraCluster",
            engine=rds.DatabaseClusterEngine.aurora_mysql(
                version=rds.AuroraMysqlEngineVersion.VER_8_0_35
            ),
            credentials=rds.Credentials.from_secret(
                self.aurora_password, username="admin"
            ),
            default_database_name="migrationdb",
            instance_props=rds.InstanceProps(
                instance_type=ec2.InstanceType.of(
                    ec2.InstanceClass.R6G, ec2.InstanceSize.LARGE
                ),
                vpc_subnets=ec2.SubnetSelection(
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS
                ),
                security_groups=[self.aurora_sg],
                parameter_group=self.db_parameter_group,
            ),
            instances=2,  # Primary + 1 read replica
            parameter_group=self.cluster_parameter_group,
            subnet_group=self.db_subnet_group,
            backup=rds.BackupProps(
                retention=Duration.days(7),
                preferred_window="03:00-04:00",
            ),
            preferred_maintenance_window="sun:04:00-sun:05:00",
            cloudwatch_logs_exports=["error", "general", "slowquery"],
            monitoring_interval=Duration.minutes(1),
            deletion_protection=False,  # Set to True for production
            removal_policy=RemovalPolicy.DESTROY,  # Change for production
        )

        # Add additional read replica for load distribution
        self.aurora_cluster.add_instance(
            "ReaderInstance",
            instance_type=ec2.InstanceType.of(
                ec2.InstanceClass.R6G, ec2.InstanceSize.LARGE
            ),
            parameter_group=self.db_parameter_group,
        )

    def _create_dms_infrastructure(self) -> None:
        """Create DMS replication instance, endpoints, and migration task."""
        # Create IAM role for DMS VPC access
        self.dms_vpc_role = iam.Role(
            self,
            "DmsVpcRole",
            assumed_by=iam.ServicePrincipal("dms.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AmazonDMSVPCManagementRole"
                ),
            ],
            role_name="dms-vpc-role",
        )

        # Create CloudWatch log group for DMS
        self.dms_log_group = logs.LogGroup(
            self,
            "DmsLogGroup",
            log_group_name="/aws/dms/migration-task",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )

        # Create DMS replication instance
        self.replication_instance = dms.CfnReplicationInstance(
            self,
            "DmsReplicationInstance",
            replication_instance_class="dms.t3.medium",
            replication_instance_identifier="dms-migration-instance",
            allocated_storage=100,
            auto_minor_version_upgrade=True,
            multi_az=True,
            publicly_accessible=False,
            replication_subnet_group_identifier=self.dms_subnet_group.ref,
            vpc_security_group_ids=[self.dms_sg.security_group_id],
            tags=[
                cdk.CfnTag(key="Name", value="dms-migration-instance"),
                cdk.CfnTag(key="Purpose", value="database-migration"),
            ],
        )

        # Create source database password secret
        self.source_db_password = secretsmanager.Secret(
            self,
            "SourceDbPassword",
            description="Password for source database connection",
            generate_secret_string=secretsmanager.SecretStringGenerator(
                exclude_characters=" %+~`#$&*()|[]{}:;<>?!'/\"\\",
                generate_string_key="password",
                password_length=32,
                secret_string_template=f'{{"username": "{self.source_db_username}"}}',
            ),
        )

        # Create source endpoint
        self.source_endpoint = dms.CfnEndpoint(
            self,
            "SourceEndpoint",
            endpoint_type="source",
            engine_name="mysql",
            endpoint_identifier="source-mysql-endpoint",
            server_name=self.source_db_host,
            port=self.source_db_port,
            username=self.source_db_username,
            password=self.source_db_password.secret_value_from_json("password").unsafe_unwrap(),
            database_name=self.source_db_name,
            extra_connection_attributes="heartbeatEnable=true;heartbeatFrequency=1;initstmt=SET foreign_key_checks=0",
            tags=[
                cdk.CfnTag(key="Name", value="source-mysql-endpoint"),
                cdk.CfnTag(key="Purpose", value="database-migration"),
            ],
        )

        # Create target endpoint for Aurora
        self.target_endpoint = dms.CfnEndpoint(
            self,
            "TargetEndpoint",
            endpoint_type="target",
            engine_name="aurora-mysql",
            endpoint_identifier="target-aurora-endpoint",
            server_name=self.aurora_cluster.cluster_endpoint.hostname,
            port=self.aurora_cluster.cluster_endpoint.port,
            username="admin",
            password=self.aurora_password.secret_value_from_json("password").unsafe_unwrap(),
            database_name="migrationdb",
            extra_connection_attributes="parallelLoadThreads=8;maxFileSize=512000;initstmt=SET foreign_key_checks=0",
            tags=[
                cdk.CfnTag(key="Name", value="target-aurora-endpoint"),
                cdk.CfnTag(key="Purpose", value="database-migration"),
            ],
        )

        # Create migration task
        self.migration_task = dms.CfnReplicationTask(
            self,
            "MigrationTask",
            replication_task_identifier="aurora-migration-task",
            migration_type="full-load-and-cdc",
            replication_instance_arn=self.replication_instance.ref,
            source_endpoint_arn=self.source_endpoint.ref,
            target_endpoint_arn=self.target_endpoint.ref,
            table_mappings='''{
                "rules": [
                    {
                        "rule-type": "selection",
                        "rule-id": "1",
                        "rule-name": "1",
                        "object-locator": {
                            "schema-name": "%",
                            "table-name": "%"
                        },
                        "rule-action": "include"
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
                        "value": "migrationdb"
                    }
                ]
            }''',
            replication_task_settings='''{
                "TargetMetadata": {
                    "TargetSchema": "",
                    "SupportLobs": true,
                    "FullLobMode": false,
                    "LobChunkSize": 0,
                    "LimitedSizeLobMode": true,
                    "LobMaxSize": 32,
                    "InlineLobMaxSize": 0,
                    "LoadMaxFileSize": 0,
                    "ParallelLoadThreads": 0,
                    "ParallelLoadBufferSize": 0,
                    "BatchApplyEnabled": true,
                    "TaskRecoveryTableEnabled": false,
                    "ParallelApplyThreads": 8,
                    "ParallelApplyBufferSize": 1000,
                    "ParallelApplyQueuesPerThread": 4
                },
                "FullLoadSettings": {
                    "TargetTablePrepMode": "DROP_AND_CREATE",
                    "CreatePkAfterFullLoad": false,
                    "StopTaskCachedChangesApplied": false,
                    "StopTaskCachedChangesNotApplied": false,
                    "MaxFullLoadSubTasks": 8,
                    "TransactionConsistencyTimeout": 600,
                    "CommitRate": 10000
                },
                "Logging": {
                    "EnableLogging": true,
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
                        },
                        {
                            "Id": "TASK_MANAGER",
                            "Severity": "LOGGER_SEVERITY_DEFAULT"
                        }
                    ],
                    "CloudWatchLogGroup": "''' + self.dms_log_group.log_group_name + '''"
                },
                "ValidationSettings": {
                    "EnableValidation": true,
                    "ValidationMode": "ROW_LEVEL",
                    "ThreadCount": 5,
                    "PartitionSize": 10000,
                    "FailureMaxCount": 10000,
                    "RecordFailureDelayLimitInMinutes": 0,
                    "RecordSuspendDelayInMinutes": 30,
                    "MaxKeyColumnSize": 8096,
                    "TableFailureMaxCount": 1000,
                    "ValidationOnly": false,
                    "HandleCollationDiff": false,
                    "RecordFailureDelayInMinutes": 5,
                    "SkipLobColumns": false,
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
                    "RecoverableErrorThrottling": true,
                    "RecoverableErrorThrottlingMax": 1800,
                    "ApplyErrorDeletePolicy": "IGNORE_RECORD",
                    "ApplyErrorInsertPolicy": "LOG_ERROR",
                    "ApplyErrorUpdatePolicy": "LOG_ERROR",
                    "ApplyErrorEscalationPolicy": "LOG_ERROR",
                    "ApplyErrorEscalationCount": 0,
                    "FullLoadIgnoreConflicts": true
                }
            }''',
            tags=[
                cdk.CfnTag(key="Name", value="aurora-migration-task"),
                cdk.CfnTag(key="Purpose", value="database-migration"),
            ],
        )

        # Add dependencies
        self.source_endpoint.add_dependency(self.replication_instance)
        self.target_endpoint.add_dependency(self.replication_instance)
        self.target_endpoint.add_dependency(self.aurora_cluster)
        self.migration_task.add_dependency(self.source_endpoint)
        self.migration_task.add_dependency(self.target_endpoint)

    def _create_route53_zone(self) -> None:
        """Create Route 53 hosted zone for DNS-based cutover."""
        self.hosted_zone = route53.PrivateHostedZone(
            self,
            "DatabaseHostedZone",
            zone_name="db.internal",
            vpc=self.vpc,
            comment="Private hosted zone for database migration cutover",
        )

        # Create initial DNS record pointing to Aurora (for testing)
        self.aurora_dns_record = route53.CnameRecord(
            self,
            "AuroraDnsRecord",
            zone=self.hosted_zone,
            record_name="app-db",
            domain_name=self.aurora_cluster.cluster_endpoint.hostname,
            ttl=Duration.seconds(60),
            comment="DNS record for Aurora cluster (cutover target)",
        )

    def _create_monitoring(self) -> None:
        """Create CloudWatch monitoring and alarms for the migration."""
        # S3 bucket for DMS task logs (optional)
        self.dms_logs_bucket = s3.Bucket(
            self,
            "DmsLogsBucket",
            bucket_name=f"dms-migration-logs-{self.account}-{self.region}",
            versioned=False,
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            encryption=s3.BucketEncryption.S3_MANAGED,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteOldLogs",
                    enabled=True,
                    expiration=Duration.days(30),
                )
            ],
            removal_policy=RemovalPolicy.DESTROY,
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources."""
        cdk.CfnOutput(
            self,
            "VpcId",
            value=self.vpc.vpc_id,
            description="VPC ID for database migration",
        )

        cdk.CfnOutput(
            self,
            "AuroraClusterEndpoint",
            value=self.aurora_cluster.cluster_endpoint.hostname,
            description="Aurora cluster writer endpoint",
        )

        cdk.CfnOutput(
            self,
            "AuroraClusterReadEndpoint",
            value=self.aurora_cluster.cluster_read_endpoint.hostname,
            description="Aurora cluster reader endpoint",
        )

        cdk.CfnOutput(
            self,
            "AuroraClusterPort",
            value=str(self.aurora_cluster.cluster_endpoint.port),
            description="Aurora cluster port",
        )

        cdk.CfnOutput(
            self,
            "DmsReplicationInstanceId",
            value=self.replication_instance.replication_instance_identifier,
            description="DMS replication instance identifier",
        )

        cdk.CfnOutput(
            self,
            "MigrationTaskId",
            value=self.migration_task.replication_task_identifier,
            description="DMS migration task identifier",
        )

        cdk.CfnOutput(
            self,
            "HostedZoneId",
            value=self.hosted_zone.hosted_zone_id,
            description="Route 53 hosted zone ID for DNS cutover",
        )

        cdk.CfnOutput(
            self,
            "AuroraPasswordSecretArn",
            value=self.aurora_password.secret_arn,
            description="ARN of the Aurora master password secret",
        )

        cdk.CfnOutput(
            self,
            "SourcePasswordSecretArn",
            value=self.source_db_password.secret_arn,
            description="ARN of the source database password secret",
        )


class DatabaseMigrationApp(cdk.App):
    """CDK App for database migration infrastructure."""

    def __init__(self) -> None:
        super().__init__()

        # Get configuration from environment variables or context
        source_db_host = self.node.try_get_context("source_db_host") or os.environ.get(
            "SOURCE_DB_HOST", "source-database.example.com"
        )
        source_db_port = int(
            self.node.try_get_context("source_db_port") or os.environ.get("SOURCE_DB_PORT", "3306")
        )
        source_db_username = self.node.try_get_context("source_db_username") or os.environ.get(
            "SOURCE_DB_USERNAME", "admin"
        )
        source_db_name = self.node.try_get_context("source_db_name") or os.environ.get(
            "SOURCE_DB_NAME", "sourcedb"
        )

        # Create the stack
        DatabaseMigrationStack(
            self,
            "DatabaseMigrationStack",
            source_db_host=source_db_host,
            source_db_port=source_db_port,
            source_db_username=source_db_username,
            source_db_name=source_db_name,
            env=cdk.Environment(
                account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
                region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
            ),
            description="Infrastructure for Aurora Migration with Minimal Downtime",
        )

        # Add global tags
        Tags.of(self).add("Project", "DatabaseMigration")
        Tags.of(self).add("Environment", "Migration")
        Tags.of(self).add("ManagedBy", "CDK")


# Create the app
app = DatabaseMigrationApp()
app.synth()