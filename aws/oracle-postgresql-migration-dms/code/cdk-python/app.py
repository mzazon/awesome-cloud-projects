#!/usr/bin/env python3
"""
AWS CDK Python Application for Oracle to PostgreSQL Database Migration

This CDK application creates the complete infrastructure for migrating Oracle databases
to Aurora PostgreSQL using AWS DMS and Schema Conversion Tool (SCT).

Infrastructure Components:
- VPC with public/private subnets across 2 AZs
- Aurora PostgreSQL cluster with enhanced monitoring
- DMS replication instance with Multi-AZ deployment
- DMS source/target endpoints for Oracle and PostgreSQL
- IAM roles and policies for DMS operations
- CloudWatch alarms for monitoring migration progress
- Security groups with least privilege access
- Secrets Manager for database credentials
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    CfnOutput,
    Duration,
    RemovalPolicy,
    aws_ec2 as ec2,
    aws_rds as rds,
    aws_dms as dms,
    aws_iam as iam,
    aws_secretsmanager as secretsmanager,
    aws_cloudwatch as cloudwatch,
    aws_sns as sns,
    aws_logs as logs,
)
from constructs import Construct


class DatabaseMigrationStack(Stack):
    """
    CDK Stack for Oracle to PostgreSQL database migration infrastructure.
    
    This stack creates all necessary AWS resources for a complete database
    migration solution using AWS DMS and Aurora PostgreSQL.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        """
        Initialize the Database Migration Stack.
        
        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)

        # Stack parameters
        self.project_name = self.node.try_get_context("project_name") or "oracle-to-postgresql"
        self.oracle_server = self.node.try_get_context("oracle_server") or "your-oracle-server.example.com"
        self.oracle_database = self.node.try_get_context("oracle_database") or "ORCL"
        
        # Create VPC and networking infrastructure
        self.vpc = self._create_vpc()
        
        # Create security groups
        self.security_groups = self._create_security_groups()
        
        # Create database credentials in Secrets Manager
        self.secrets = self._create_secrets()
        
        # Create IAM roles for DMS
        self.iam_roles = self._create_iam_roles()
        
        # Create Aurora PostgreSQL cluster
        self.aurora_cluster = self._create_aurora_cluster()
        
        # Create DMS subnet group
        self.dms_subnet_group = self._create_dms_subnet_group()
        
        # Create DMS replication instance
        self.replication_instance = self._create_replication_instance()
        
        # Create DMS endpoints
        self.dms_endpoints = self._create_dms_endpoints()
        
        # Create CloudWatch monitoring
        self.monitoring = self._create_monitoring()
        
        # Create stack outputs
        self._create_outputs()

    def _create_vpc(self) -> ec2.Vpc:
        """
        Create VPC with public and private subnets across 2 availability zones.
        
        Returns:
            ec2.Vpc: The created VPC
        """
        vpc = ec2.Vpc(
            self, "MigrationVPC",
            vpc_name=f"{self.project_name}-vpc",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=2,
            nat_gateways=1,
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
        
        # Add VPC endpoints for DMS and other services
        vpc.add_gateway_endpoint(
            "S3Endpoint",
            service=ec2.GatewayVpcEndpointAwsService.S3,
            subnets=[ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS)]
        )
        
        return vpc

    def _create_security_groups(self) -> Dict[str, ec2.SecurityGroup]:
        """
        Create security groups for different components.
        
        Returns:
            Dict[str, ec2.SecurityGroup]: Dictionary of security groups
        """
        # Aurora PostgreSQL security group
        aurora_sg = ec2.SecurityGroup(
            self, "AuroraSecurityGroup",
            vpc=self.vpc,
            description="Security group for Aurora PostgreSQL cluster",
            security_group_name=f"{self.project_name}-aurora-sg",
        )
        
        # DMS replication instance security group
        dms_sg = ec2.SecurityGroup(
            self, "DMSSecurityGroup",
            vpc=self.vpc,
            description="Security group for DMS replication instance",
            security_group_name=f"{self.project_name}-dms-sg",
        )
        
        # Allow DMS to connect to Aurora PostgreSQL
        aurora_sg.add_ingress_rule(
            peer=dms_sg,
            connection=ec2.Port.tcp(5432),
            description="Allow DMS to connect to Aurora PostgreSQL"
        )
        
        # Allow DMS outbound connections
        dms_sg.add_egress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(1521),
            description="Allow DMS to connect to Oracle database"
        )
        
        dms_sg.add_egress_rule(
            peer=aurora_sg,
            connection=ec2.Port.tcp(5432),
            description="Allow DMS to connect to Aurora PostgreSQL"
        )
        
        return {
            "aurora": aurora_sg,
            "dms": dms_sg,
        }

    def _create_secrets(self) -> Dict[str, secretsmanager.Secret]:
        """
        Create secrets for database credentials.
        
        Returns:
            Dict[str, secretsmanager.Secret]: Dictionary of secrets
        """
        # Aurora PostgreSQL master password
        aurora_secret = secretsmanager.Secret(
            self, "AuroraSecret",
            secret_name=f"{self.project_name}/aurora/credentials",
            description="Aurora PostgreSQL master user credentials",
            generate_secret_string=secretsmanager.SecretStringGenerator(
                secret_string_template='{"username": "dbadmin"}',
                generate_string_key="password",
                exclude_characters='"@/\\',
                password_length=32,
            ),
        )
        
        # Oracle database credentials (placeholder - update with actual values)
        oracle_secret = secretsmanager.Secret(
            self, "OracleSecret",
            secret_name=f"{self.project_name}/oracle/credentials",
            description="Oracle database credentials for migration",
            secret_string_value=cdk.SecretValue.unsafe_plain_text(
                '{"username": "oracle_user", "password": "oracle_password"}'
            ),
        )
        
        return {
            "aurora": aurora_secret,
            "oracle": oracle_secret,
        }

    def _create_iam_roles(self) -> Dict[str, iam.Role]:
        """
        Create IAM roles required for DMS operations.
        
        Returns:
            Dict[str, iam.Role]: Dictionary of IAM roles
        """
        # DMS VPC role
        dms_vpc_role = iam.Role(
            self, "DMSVPCRole",
            role_name=f"{self.project_name}-dms-vpc-role",
            assumed_by=iam.ServicePrincipal("dms.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AmazonDMSVPCManagementRole"
                )
            ],
        )
        
        # DMS CloudWatch logs role
        dms_cloudwatch_role = iam.Role(
            self, "DMSCloudWatchRole",
            role_name=f"{self.project_name}-dms-cloudwatch-role",
            assumed_by=iam.ServicePrincipal("dms.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AmazonDMSCloudWatchLogsRole"
                )
            ],
        )
        
        # Enhanced monitoring role for Aurora
        rds_monitoring_role = iam.Role(
            self, "RDSMonitoringRole",
            role_name=f"{self.project_name}-rds-monitoring-role",
            assumed_by=iam.ServicePrincipal("monitoring.rds.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AmazonRDSEnhancedMonitoringRole"
                )
            ],
        )
        
        return {
            "dms_vpc": dms_vpc_role,
            "dms_cloudwatch": dms_cloudwatch_role,
            "rds_monitoring": rds_monitoring_role,
        }

    def _create_aurora_cluster(self) -> rds.DatabaseCluster:
        """
        Create Aurora PostgreSQL cluster with best practices configuration.
        
        Returns:
            rds.DatabaseCluster: The created Aurora cluster
        """
        # Parameter group for Aurora PostgreSQL
        parameter_group = rds.ParameterGroup(
            self, "AuroraParameterGroup",
            engine=rds.DatabaseClusterEngine.aurora_postgres(
                version=rds.AuroraPostgresEngineVersion.VER_15_4
            ),
            description="Parameter group for Aurora PostgreSQL migration target",
            parameters={
                "log_statement": "all",
                "log_min_duration_statement": "1000",
                "shared_preload_libraries": "pg_stat_statements",
            },
        )
        
        # Subnet group for Aurora
        subnet_group = rds.SubnetGroup(
            self, "AuroraSubnetGroup",
            description="Subnet group for Aurora PostgreSQL cluster",
            vpc=self.vpc,
            vpc_subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_ISOLATED),
            subnet_group_name=f"{self.project_name}-aurora-subnet-group",
        )
        
        # Aurora PostgreSQL cluster
        cluster = rds.DatabaseCluster(
            self, "AuroraCluster",
            cluster_identifier=f"{self.project_name}-aurora-cluster",
            engine=rds.DatabaseClusterEngine.aurora_postgres(
                version=rds.AuroraPostgresEngineVersion.VER_15_4
            ),
            credentials=rds.Credentials.from_secret(self.secrets["aurora"]),
            default_database_name="postgres",
            instances=2,
            instance_props=rds.InstanceProps(
                instance_type=ec2.InstanceType.of(
                    ec2.InstanceClass.MEMORY6_GRAVITON, ec2.InstanceSize.LARGE
                ),
                vpc_subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_ISOLATED),
                security_groups=[self.security_groups["aurora"]],
                enable_performance_insights=True,
                performance_insight_retention=rds.PerformanceInsightRetention.DEFAULT,
                monitoring_interval=Duration.seconds(60),
                monitoring_role=self.iam_roles["rds_monitoring"],
            ),
            parameter_group=parameter_group,
            subnet_group=subnet_group,
            backup=rds.BackupProps(
                retention=Duration.days(7),
                preferred_window="03:00-04:00",
            ),
            preferred_maintenance_window="sun:04:00-sun:05:00",
            storage_encrypted=True,
            deletion_protection=False,  # Set to True for production
            removal_policy=RemovalPolicy.DESTROY,  # Set to RETAIN for production
        )
        
        return cluster

    def _create_dms_subnet_group(self) -> dms.CfnReplicationSubnetGroup:
        """
        Create DMS replication subnet group.
        
        Returns:
            dms.CfnReplicationSubnetGroup: The created subnet group
        """
        subnet_group = dms.CfnReplicationSubnetGroup(
            self, "DMSSubnetGroup",
            replication_subnet_group_identifier=f"{self.project_name}-dms-subnet-group",
            replication_subnet_group_description="DMS subnet group for database migration",
            subnet_ids=[
                subnet.subnet_id for subnet in 
                self.vpc.select_subnets(subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS).subnets
            ],
            tags=[
                cdk.CfnTag(key="Name", value=f"{self.project_name}-dms-subnet-group"),
                cdk.CfnTag(key="Project", value=self.project_name),
            ],
        )
        
        return subnet_group

    def _create_replication_instance(self) -> dms.CfnReplicationInstance:
        """
        Create DMS replication instance for database migration.
        
        Returns:
            dms.CfnReplicationInstance: The created replication instance
        """
        replication_instance = dms.CfnReplicationInstance(
            self, "ReplicationInstance",
            replication_instance_identifier=f"{self.project_name}-replication-instance",
            replication_instance_class="dms.c5.large",
            allocated_storage=100,
            auto_minor_version_upgrade=True,
            multi_az=True,
            engine_version="3.5.2",
            replication_subnet_group_identifier=self.dms_subnet_group.replication_subnet_group_identifier,
            vpc_security_group_ids=[self.security_groups["dms"].security_group_id],
            publicly_accessible=False,
            tags=[
                cdk.CfnTag(key="Name", value=f"{self.project_name}-replication-instance"),
                cdk.CfnTag(key="Project", value=self.project_name),
            ],
        )
        
        # Add dependency on subnet group
        replication_instance.add_dependency(self.dms_subnet_group)
        
        return replication_instance

    def _create_dms_endpoints(self) -> Dict[str, dms.CfnEndpoint]:
        """
        Create DMS source and target endpoints.
        
        Returns:
            Dict[str, dms.CfnEndpoint]: Dictionary of DMS endpoints
        """
        # Oracle source endpoint
        oracle_endpoint = dms.CfnEndpoint(
            self, "OracleSourceEndpoint",
            endpoint_identifier=f"{self.project_name}-oracle-source",
            endpoint_type="source",
            engine_name="oracle",
            server_name=self.oracle_server,
            port=1521,
            database_name=self.oracle_database,
            username="oracle_user",  # Replace with actual username
            password="oracle_password",  # Replace with reference to Secrets Manager
            oracle_settings=dms.CfnEndpoint.OracleSettingsProperty(
                security_db_encryption="NONE",
                char_length_semantics="default",
                direct_path_no_log=False,
                direct_path_parallel_load=False,
                enable_homogenous_tablespace=True,
                fail_tasks_on_lob_truncation=True,
                number_datatype_scale=0,
                parallel_asm_read_threads=0,
                read_ahead_blocks=10000,
                read_table_space_name=False,
                replace_path_prefix=False,
                retry_interval=5,
                use_alternate_folder_for_online=False,
                use_path_prefix="",
            ),
            tags=[
                cdk.CfnTag(key="Name", value=f"{self.project_name}-oracle-source"),
                cdk.CfnTag(key="Project", value=self.project_name),
            ],
        )
        
        # PostgreSQL target endpoint
        postgresql_endpoint = dms.CfnEndpoint(
            self, "PostgreSQLTargetEndpoint",
            endpoint_identifier=f"{self.project_name}-postgresql-target",
            endpoint_type="target",
            engine_name="postgres",
            server_name=self.aurora_cluster.cluster_endpoint.hostname,
            port=5432,
            database_name="postgres",
            username="dbadmin",
            password=self.secrets["aurora"].secret_value_from_json("password").unsafe_unwrap(),
            postgre_sql_settings=dms.CfnEndpoint.PostgreSqlSettingsProperty(
                heartbeat_enable=True,
                heartbeat_schema="replication",
                heartbeat_frequency=5,
                capture_ddls=True,
                max_file_size=512,
                database_mode="default",
                ddl_artifacts_schema="public",
                execute_timeout=60,
                fail_tasks_on_lob_truncation=True,
                map_boolean_as_boolean=False,
                map_jsonb_as_clob=False,
                map_long_varchar_as="wstring",
                after_connect_script="",
                batch_apply_enabled=False,
                batch_apply_preserve_transaction=True,
                batch_apply_timeout_max=30,
                batch_apply_timeout_min=1,
                batch_split_size=0,
            ),
            tags=[
                cdk.CfnTag(key="Name", value=f"{self.project_name}-postgresql-target"),
                cdk.CfnTag(key="Project", value=self.project_name),
            ],
        )
        
        # Add dependencies
        postgresql_endpoint.add_dependency(self.aurora_cluster.node.default_child)
        
        return {
            "oracle_source": oracle_endpoint,
            "postgresql_target": postgresql_endpoint,
        }

    def _create_monitoring(self) -> Dict[str, Any]:
        """
        Create CloudWatch monitoring and alerting for the migration.
        
        Returns:
            Dict[str, Any]: Dictionary of monitoring resources
        """
        # SNS topic for alerts
        alert_topic = sns.Topic(
            self, "MigrationAlerts",
            topic_name=f"{self.project_name}-migration-alerts",
            display_name="Database Migration Alerts",
        )
        
        # CloudWatch log group for DMS
        log_group = logs.LogGroup(
            self, "DMSLogGroup",
            log_group_name=f"/aws/dms/{self.project_name}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        # CloudWatch alarm for replication lag
        replication_lag_alarm = cloudwatch.Alarm(
            self, "ReplicationLagAlarm",
            alarm_name=f"{self.project_name}-replication-lag",
            alarm_description="Monitor DMS replication lag",
            metric=cloudwatch.Metric(
                namespace="AWS/DMS",
                metric_name="ReplicationLag",
                dimensions_map={
                    "ReplicationInstanceIdentifier": self.replication_instance.replication_instance_identifier,
                },
                statistic="Average",
                period=Duration.minutes(5),
            ),
            threshold=300,  # 5 minutes
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )
        
        replication_lag_alarm.add_alarm_action(
            cloudwatch.SnsAction(alert_topic)
        )
        
        # CloudWatch alarm for task failures
        task_failure_alarm = cloudwatch.Alarm(
            self, "TaskFailureAlarm",
            alarm_name=f"{self.project_name}-task-failure",
            alarm_description="Monitor DMS task failures",
            metric=cloudwatch.Metric(
                namespace="AWS/DMS",
                metric_name="ReplicationTaskFailure",
                statistic="Sum",
                period=Duration.minutes(5),
            ),
            threshold=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
            evaluation_periods=1,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )
        
        task_failure_alarm.add_alarm_action(
            cloudwatch.SnsAction(alert_topic)
        )
        
        return {
            "alert_topic": alert_topic,
            "log_group": log_group,
            "replication_lag_alarm": replication_lag_alarm,
            "task_failure_alarm": task_failure_alarm,
        }

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information."""
        CfnOutput(
            self, "VPCId",
            value=self.vpc.vpc_id,
            description="VPC ID for the migration infrastructure",
            export_name=f"{self.project_name}-vpc-id",
        )
        
        CfnOutput(
            self, "AuroraClusterEndpoint",
            value=self.aurora_cluster.cluster_endpoint.hostname,
            description="Aurora PostgreSQL cluster endpoint",
            export_name=f"{self.project_name}-aurora-endpoint",
        )
        
        CfnOutput(
            self, "AuroraClusterPort",
            value=str(self.aurora_cluster.cluster_endpoint.port),
            description="Aurora PostgreSQL cluster port",
            export_name=f"{self.project_name}-aurora-port",
        )
        
        CfnOutput(
            self, "ReplicationInstanceArn",
            value=self.replication_instance.attr_replication_instance_arn,
            description="DMS replication instance ARN",
            export_name=f"{self.project_name}-replication-instance-arn",
        )
        
        CfnOutput(
            self, "OracleEndpointArn",
            value=self.dms_endpoints["oracle_source"].attr_endpoint_arn,
            description="Oracle source endpoint ARN",
            export_name=f"{self.project_name}-oracle-endpoint-arn",
        )
        
        CfnOutput(
            self, "PostgreSQLEndpointArn",
            value=self.dms_endpoints["postgresql_target"].attr_endpoint_arn,
            description="PostgreSQL target endpoint ARN",
            export_name=f"{self.project_name}-postgresql-endpoint-arn",
        )
        
        CfnOutput(
            self, "SNSTopicArn",
            value=self.monitoring["alert_topic"].topic_arn,
            description="SNS topic ARN for migration alerts",
            export_name=f"{self.project_name}-sns-topic-arn",
        )


def main() -> None:
    """Main application entry point."""
    app = cdk.App()
    
    # Get environment configuration
    env = Environment(
        account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
        region=os.environ.get("CDK_DEFAULT_REGION"),
    )
    
    # Create the database migration stack
    DatabaseMigrationStack(
        app, "DatabaseMigrationStack",
        env=env,
        description="Oracle to PostgreSQL database migration infrastructure using AWS DMS and Aurora PostgreSQL",
        tags={
            "Project": "database-migration-oracle-postgresql",
            "Environment": "development",
            "Owner": "migration-team",
            "CostCenter": "engineering",
        },
    )
    
    app.synth()


if __name__ == "__main__":
    main()