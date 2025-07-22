#!/usr/bin/env python3
"""
Multi-AZ Database Deployments for High Availability
AWS CDK Python Application

This application creates a production-ready Aurora PostgreSQL Multi-AZ cluster
with comprehensive monitoring, security, and high availability features.

Author: AWS CDK Recipe Generator
Version: 1.0
"""

import os
from typing import Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    CfnOutput,
    Duration,
    RemovalPolicy,
    Tags,
    aws_ec2 as ec2,
    aws_rds as rds,
    aws_kms as kms,
    aws_logs as logs,
    aws_cloudwatch as cloudwatch,
    aws_ssm as ssm,
    aws_secretsmanager as secretsmanager,
    aws_iam as iam,
)
from constructs import Construct


class MultiAzDatabaseStack(Stack):
    """
    AWS CDK Stack for Multi-AZ Aurora PostgreSQL Database deployment.
    
    Creates a highly available Aurora PostgreSQL cluster with:
    - Multi-AZ deployment across 3 availability zones
    - Enhanced monitoring and Performance Insights
    - CloudWatch alarms and monitoring
    - Encryption at rest and in transit
    - Automated backups and point-in-time recovery
    - Systems Manager parameter storage for connection details
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        environment_name: str = "production",
        database_name: str = "testdb",
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Store configuration
        self.environment_name = environment_name
        self.database_name = database_name
        
        # Generate unique suffix for resources
        self.resource_suffix = f"{environment_name}-{self.node.addr[-6:]}"

        # Create VPC and networking components
        self.vpc = self._create_vpc()
        
        # Create security resources
        self.kms_key = self._create_kms_key()
        self.security_group = self._create_security_group()
        
        # Create database credentials
        self.db_credentials = self._create_database_credentials()
        
        # Create parameter group
        self.parameter_group = self._create_parameter_group()
        
        # Create Aurora cluster
        self.aurora_cluster = self._create_aurora_cluster()
        
        # Create CloudWatch monitoring
        self._create_cloudwatch_alarms()
        
        # Store connection information
        self._create_parameter_store_entries()
        
        # Add resource tags
        self._add_resource_tags()

    def _create_vpc(self) -> ec2.Vpc:
        """Create VPC with Multi-AZ subnets for high availability."""
        vpc = ec2.Vpc(
            self,
            "MultiAzVpc",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=3,  # Ensure 3 AZs for Multi-AZ cluster
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="Public",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24,
                ),
                ec2.SubnetConfiguration(
                    name="Private",
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                    cidr_mask=24,
                ),
                ec2.SubnetConfiguration(
                    name="Database",
                    subnet_type=ec2.SubnetType.PRIVATE_ISOLATED,
                    cidr_mask=24,
                ),
            ],
            enable_dns_hostnames=True,
            enable_dns_support=True,
        )

        # Add flow logs for security monitoring
        vpc.add_flow_log(
            "VpcFlowLogs",
            destination=ec2.FlowLogDestination.to_cloud_watch_logs(
                logs.LogGroup(
                    self,
                    "VpcFlowLogsGroup",
                    log_group_name=f"/aws/vpc/flowlogs/{self.resource_suffix}",
                    retention=logs.RetentionDays.ONE_MONTH,
                    removal_policy=RemovalPolicy.DESTROY,
                )
            ),
            traffic_type=ec2.FlowLogTrafficType.REJECT,
        )

        return vpc

    def _create_kms_key(self) -> kms.Key:
        """Create KMS key for database encryption."""
        key = kms.Key(
            self,
            "DatabaseKmsKey",
            description=f"KMS key for Multi-AZ Aurora cluster encryption - {self.resource_suffix}",
            enable_key_rotation=True,
            removal_policy=RemovalPolicy.DESTROY,
            policy=iam.PolicyDocument(
                statements=[
                    iam.PolicyStatement(
                        sid="Enable IAM User Permissions",
                        effect=iam.Effect.ALLOW,
                        principals=[
                            iam.AccountRootPrincipal()
                        ],
                        actions=["kms:*"],
                        resources=["*"],
                    ),
                    iam.PolicyStatement(
                        sid="Allow RDS Service",
                        effect=iam.Effect.ALLOW,
                        principals=[
                            iam.ServicePrincipal("rds.amazonaws.com")
                        ],
                        actions=[
                            "kms:Decrypt",
                            "kms:GenerateDataKey",
                            "kms:CreateGrant",
                            "kms:DescribeKey",
                        ],
                        resources=["*"],
                    ),
                ]
            ),
        )

        # Create alias for easier identification
        kms.Alias(
            self,
            "DatabaseKmsKeyAlias",
            alias_name=f"alias/aurora-multiaz-{self.resource_suffix}",
            target_key=key,
        )

        return key

    def _create_security_group(self) -> ec2.SecurityGroup:
        """Create security group for Aurora cluster access."""
        security_group = ec2.SecurityGroup(
            self,
            "AuroraSecurityGroup",
            vpc=self.vpc,
            description=f"Security group for Multi-AZ Aurora cluster - {self.resource_suffix}",
            allow_all_outbound=False,
        )

        # Allow PostgreSQL access from within VPC
        security_group.add_ingress_rule(
            peer=ec2.Peer.ipv4(self.vpc.vpc_cidr_block),
            connection=ec2.Port.tcp(5432),
            description="PostgreSQL access from VPC",
        )

        # Allow HTTPS outbound for monitoring and updates
        security_group.add_egress_rule(
            peer=ec2.Peer.ipv4("0.0.0.0/0"),
            connection=ec2.Port.tcp(443),
            description="HTTPS outbound for AWS services",
        )

        return security_group

    def _create_database_credentials(self) -> secretsmanager.Secret:
        """Create database credentials in Secrets Manager."""
        credentials = secretsmanager.Secret(
            self,
            "DatabaseCredentials",
            description=f"Aurora cluster credentials - {self.resource_suffix}",
            generate_secret_string=secretsmanager.SecretStringGenerator(
                secret_string_template='{"username": "dbadmin"}',
                generate_string_key="password",
                exclude_characters='"@/\\',
                password_length=32,
                require_each_included_type=True,
            ),
            removal_policy=RemovalPolicy.DESTROY,
        )

        return credentials

    def _create_parameter_group(self) -> rds.ParameterGroup:
        """Create optimized parameter group for PostgreSQL."""
        parameter_group = rds.ParameterGroup(
            self,
            "AuroraParameterGroup",
            engine=rds.DatabaseClusterEngine.aurora_postgres(
                version=rds.AuroraPostgresEngineVersion.VER_15_4
            ),
            description=f"Parameter group for Multi-AZ Aurora PostgreSQL - {self.resource_suffix}",
            parameters={
                # Enable query logging for monitoring
                "log_statement": "all",
                "log_min_duration_statement": "1000",
                "shared_preload_libraries": "pg_stat_statements",
                # Connection and memory settings
                "max_connections": "LEAST({DBInstanceClassMemory/9531392},5000)",
                "shared_buffers": "GREATEST({DBInstanceClassMemory*1/4},65536)",
                # Logging and monitoring
                "log_checkpoints": "1",
                "log_connections": "1",
                "log_disconnections": "1",
                "log_lock_waits": "1",
                # Performance settings
                "effective_cache_size": "GREATEST({DBInstanceClassMemory*3/4},524288)",
                "maintenance_work_mem": "GREATEST({DBInstanceClassMemory*1/16},65536)",
            },
        )

        return parameter_group

    def _create_aurora_cluster(self) -> rds.DatabaseCluster:
        """Create Multi-AZ Aurora PostgreSQL cluster."""
        # Create enhanced monitoring role
        monitoring_role = iam.Role(
            self,
            "AuroraMonitoringRole",
            assumed_by=iam.ServicePrincipal("monitoring.rds.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AmazonRDSEnhancedMonitoringRole"
                )
            ],
        )

        # Create Aurora cluster
        aurora_cluster = rds.DatabaseCluster(
            self,
            "AuroraCluster",
            engine=rds.DatabaseClusterEngine.aurora_postgres(
                version=rds.AuroraPostgresEngineVersion.VER_15_4
            ),
            credentials=rds.Credentials.from_secret(self.db_credentials),
            writer=rds.ClusterInstance.provisioned(
                "writer",
                instance_type=ec2.InstanceType.of(
                    ec2.InstanceClass.R6G, ec2.InstanceSize.LARGE
                ),
                promotion_tier=0,
                performance_insight_retention=rds.PerformanceInsightRetention.MONTHS_1,
                enable_performance_insights=True,
                performance_insight_encryption_key=self.kms_key,
                monitoring_interval=Duration.minutes(1),
                monitoring_role=monitoring_role,
            ),
            readers=[
                rds.ClusterInstance.provisioned(
                    "reader1",
                    instance_type=ec2.InstanceType.of(
                        ec2.InstanceClass.R6G, ec2.InstanceSize.LARGE
                    ),
                    promotion_tier=1,
                    performance_insight_retention=rds.PerformanceInsightRetention.MONTHS_1,
                    enable_performance_insights=True,
                    performance_insight_encryption_key=self.kms_key,
                    monitoring_interval=Duration.minutes(1),
                    monitoring_role=monitoring_role,
                ),
                rds.ClusterInstance.provisioned(
                    "reader2",
                    instance_type=ec2.InstanceType.of(
                        ec2.InstanceClass.R6G, ec2.InstanceSize.LARGE
                    ),
                    promotion_tier=2,
                    performance_insight_retention=rds.PerformanceInsightRetention.MONTHS_1,
                    enable_performance_insights=True,
                    performance_insight_encryption_key=self.kms_key,
                    monitoring_interval=Duration.minutes(1),
                    monitoring_role=monitoring_role,
                ),
            ],
            vpc=self.vpc,
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PRIVATE_ISOLATED
            ),
            security_groups=[self.security_group],
            parameter_group=self.parameter_group,
            storage_encryption_key=self.kms_key,
            backup=rds.BackupProps(
                retention=Duration.days(14),
                preferred_window="03:00-04:00",
            ),
            preferred_maintenance_window="sun:04:00-sun:05:00",
            cloudwatch_logs_exports=["postgresql"],
            cloudwatch_logs_retention=logs.RetentionDays.ONE_MONTH,
            deletion_protection=True,
            default_database_name=self.database_name,
            removal_policy=RemovalPolicy.DESTROY,
        )

        return aurora_cluster

    def _create_cloudwatch_alarms(self) -> None:
        """Create CloudWatch alarms for monitoring."""
        cluster_identifier = self.aurora_cluster.cluster_identifier

        # CPU Utilization alarm
        cloudwatch.Alarm(
            self,
            "HighCpuAlarm",
            alarm_name=f"{cluster_identifier}-high-cpu",
            alarm_description="High CPU utilization on Aurora cluster",
            metric=cloudwatch.Metric(
                namespace="AWS/RDS",
                metric_name="CPUUtilization",
                dimensions_map={
                    "DBClusterIdentifier": cluster_identifier,
                },
                statistic="Average",
                period=Duration.minutes(5),
            ),
            threshold=80,
            evaluation_periods=3,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

        # Database connections alarm
        cloudwatch.Alarm(
            self,
            "HighConnectionsAlarm",
            alarm_name=f"{cluster_identifier}-high-connections",
            alarm_description="High database connections on Aurora cluster",
            metric=cloudwatch.Metric(
                namespace="AWS/RDS",
                metric_name="DatabaseConnections",
                dimensions_map={
                    "DBClusterIdentifier": cluster_identifier,
                },
                statistic="Maximum",
                period=Duration.minutes(5),
            ),
            threshold=800,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        )

        # Read latency alarm
        cloudwatch.Alarm(
            self,
            "HighReadLatencyAlarm",
            alarm_name=f"{cluster_identifier}-high-read-latency",
            alarm_description="High read latency on Aurora cluster",
            metric=cloudwatch.Metric(
                namespace="AWS/RDS",
                metric_name="ReadLatency",
                dimensions_map={
                    "DBClusterIdentifier": cluster_identifier,
                },
                statistic="Average",
                period=Duration.minutes(5),
            ),
            threshold=0.05,  # 50ms
            evaluation_periods=3,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        )

        # Write latency alarm
        cloudwatch.Alarm(
            self,
            "HighWriteLatencyAlarm",
            alarm_name=f"{cluster_identifier}-high-write-latency",
            alarm_description="High write latency on Aurora cluster",
            metric=cloudwatch.Metric(
                namespace="AWS/RDS",
                metric_name="WriteLatency",
                dimensions_map={
                    "DBClusterIdentifier": cluster_identifier,
                },
                statistic="Average",
                period=Duration.minutes(5),
            ),
            threshold=0.1,  # 100ms
            evaluation_periods=3,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        )

    def _create_parameter_store_entries(self) -> None:
        """Store database connection information in Systems Manager Parameter Store."""
        base_path = f"/rds/multiaz/{self.resource_suffix}"

        # Store cluster endpoints
        ssm.StringParameter(
            self,
            "WriterEndpointParameter",
            parameter_name=f"{base_path}/writer-endpoint",
            string_value=self.aurora_cluster.cluster_endpoint.hostname,
            description="Aurora cluster writer endpoint",
            tier=ssm.ParameterTier.STANDARD,
        )

        ssm.StringParameter(
            self,
            "ReaderEndpointParameter",
            parameter_name=f"{base_path}/reader-endpoint",
            string_value=self.aurora_cluster.cluster_read_endpoint.hostname,
            description="Aurora cluster reader endpoint",
            tier=ssm.ParameterTier.STANDARD,
        )

        # Store database configuration
        ssm.StringParameter(
            self,
            "DatabaseNameParameter",
            parameter_name=f"{base_path}/database-name",
            string_value=self.database_name,
            description="Aurora cluster default database name",
            tier=ssm.ParameterTier.STANDARD,
        )

        ssm.StringParameter(
            self,
            "DatabasePortParameter",
            parameter_name=f"{base_path}/port",
            string_value=str(self.aurora_cluster.cluster_endpoint.port),
            description="Aurora cluster port number",
            tier=ssm.ParameterTier.STANDARD,
        )

        # Store credentials secret ARN
        ssm.StringParameter(
            self,
            "CredentialsSecretParameter",
            parameter_name=f"{base_path}/credentials-secret-arn",
            string_value=self.db_credentials.secret_arn,
            description="Aurora cluster credentials secret ARN",
            tier=ssm.ParameterTier.STANDARD,
        )

    def _add_resource_tags(self) -> None:
        """Add consistent tags to all resources."""
        tags_to_add = {
            "Environment": self.environment_name,
            "Application": "MultiAzDatabase",
            "HighAvailability": "true",
            "Backup": "automated",
            "Monitoring": "enhanced",
        }

        for key, value in tags_to_add.items():
            Tags.of(self).add(key, value)

    # Output properties for external access
    @property
    def cluster_identifier(self) -> str:
        """Return the Aurora cluster identifier."""
        return self.aurora_cluster.cluster_identifier

    @property
    def writer_endpoint(self) -> str:
        """Return the Aurora cluster writer endpoint."""
        return self.aurora_cluster.cluster_endpoint.hostname

    @property
    def reader_endpoint(self) -> str:
        """Return the Aurora cluster reader endpoint."""
        return self.aurora_cluster.cluster_read_endpoint.hostname

    @property
    def secret_arn(self) -> str:
        """Return the database credentials secret ARN."""
        return self.db_credentials.secret_arn


class MultiAzDatabaseApp(cdk.App):
    """CDK Application for Multi-AZ Database deployments."""

    def __init__(self) -> None:
        super().__init__()

        # Get configuration from environment or use defaults
        environment_name = self.node.try_get_context("environment") or "production"
        database_name = self.node.try_get_context("database_name") or "testdb"

        # Create the main stack
        multi_az_stack = MultiAzDatabaseStack(
            self,
            "MultiAzDatabaseStack",
            environment_name=environment_name,
            database_name=database_name,
            description="Multi-AZ Aurora PostgreSQL cluster for high availability",
            env=cdk.Environment(
                account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
                region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
            ),
        )

        # Stack outputs
        CfnOutput(
            multi_az_stack,
            "ClusterIdentifier",
            value=multi_az_stack.cluster_identifier,
            description="Aurora cluster identifier",
            export_name="MultiAzClusterIdentifier",
        )

        CfnOutput(
            multi_az_stack,
            "WriterEndpoint",
            value=multi_az_stack.writer_endpoint,
            description="Aurora cluster writer endpoint",
            export_name="MultiAzWriterEndpoint",
        )

        CfnOutput(
            multi_az_stack,
            "ReaderEndpoint",
            value=multi_az_stack.reader_endpoint,
            description="Aurora cluster reader endpoint",
            export_name="MultiAzReaderEndpoint",
        )

        CfnOutput(
            multi_az_stack,
            "SecretArn",
            value=multi_az_stack.secret_arn,
            description="Database credentials secret ARN",
            export_name="MultiAzSecretArn",
        )


# Entry point for CDK CLI
app = MultiAzDatabaseApp()
app.synth()