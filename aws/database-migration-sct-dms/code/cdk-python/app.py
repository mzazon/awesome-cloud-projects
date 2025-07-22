#!/usr/bin/env python3
"""
CDK Python Application for Database Migration with AWS DMS and Schema Conversion Tool

This application creates the complete infrastructure needed for database migration
using AWS Database Migration Service (DMS) and supports integration with the
AWS Schema Conversion Tool (SCT).

Architecture Components:
- VPC with public and private subnets across multiple AZs
- DMS Replication Instance with appropriate security groups
- RDS PostgreSQL target database with security configurations
- DMS Subnet Groups for replication instance placement
- CloudWatch monitoring and logging configuration
- IAM roles and policies for DMS operations
- Security groups with least privilege access

Usage:
    cdk deploy --all
    cdk destroy --all
"""

import os
from typing import Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    App,
    Environment,
    Stack,
    StackProps,
    Tags,
    aws_ec2 as ec2,
    aws_dms as dms,
    aws_rds as rds,
    aws_iam as iam,
    aws_logs as logs,
    aws_secretsmanager as secretsmanager,
    aws_cloudwatch as cloudwatch,
)
from constructs import Construct


class DatabaseMigrationStack(Stack):
    """
    Main stack for database migration infrastructure using AWS DMS.
    
    Creates all necessary resources for a complete database migration solution
    including networking, security, monitoring, and the DMS replication infrastructure.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        source_db_config: Dict[str, str],
        **kwargs
    ) -> None:
        """
        Initialize the Database Migration Stack.
        
        Args:
            scope: The parent construct
            construct_id: Unique identifier for this stack
            source_db_config: Configuration for source database connection
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)
        
        self.source_db_config = source_db_config
        
        # Create VPC and networking infrastructure
        self.vpc = self._create_vpc()
        
        # Create security groups
        self.security_groups = self._create_security_groups()
        
        # Create IAM roles for DMS
        self.dms_roles = self._create_dms_iam_roles()
        
        # Create target RDS database
        self.target_database = self._create_target_database()
        
        # Create DMS subnet group
        self.dms_subnet_group = self._create_dms_subnet_group()
        
        # Create DMS replication instance
        self.replication_instance = self._create_dms_replication_instance()
        
        # Create DMS endpoints
        self.endpoints = self._create_dms_endpoints()
        
        # Create CloudWatch monitoring
        self.monitoring = self._create_cloudwatch_monitoring()
        
        # Create stack outputs
        self._create_outputs()

    def _create_vpc(self) -> ec2.Vpc:
        """
        Create VPC with public and private subnets for DMS infrastructure.
        
        Returns:
            ec2.Vpc: The created VPC with appropriate subnet configuration
        """
        vpc = ec2.Vpc(
            self,
            "DatabaseMigrationVpc",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=2,
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
        
        # Add tags for identification
        Tags.of(vpc).add("Name", "DatabaseMigrationVpc")
        Tags.of(vpc).add("Project", "DatabaseMigration")
        
        return vpc

    def _create_security_groups(self) -> Dict[str, ec2.SecurityGroup]:
        """
        Create security groups for DMS and RDS components.
        
        Returns:
            Dict[str, ec2.SecurityGroup]: Dictionary of security groups by name
        """
        # Security group for DMS replication instance
        dms_sg = ec2.SecurityGroup(
            self,
            "DmsReplicationInstanceSg",
            vpc=self.vpc,
            description="Security group for DMS replication instance",
            allow_all_outbound=True,
        )
        
        # Security group for RDS target database
        rds_sg = ec2.SecurityGroup(
            self,
            "RdsTargetDatabaseSg",
            vpc=self.vpc,
            description="Security group for RDS target database",
            allow_all_outbound=False,
        )
        
        # Allow DMS to connect to RDS on PostgreSQL port
        rds_sg.add_ingress_rule(
            peer=dms_sg,
            connection=ec2.Port.tcp(5432),
            description="Allow DMS replication instance to connect to PostgreSQL",
        )
        
        # Allow connection from source database (adjust port as needed)
        if self.source_db_config.get("engine") == "oracle":
            dms_sg.add_ingress_rule(
                peer=ec2.Peer.any_ipv4(),
                connection=ec2.Port.tcp(1521),
                description="Allow connection from Oracle source database",
            )
        elif self.source_db_config.get("engine") == "sqlserver":
            dms_sg.add_ingress_rule(
                peer=ec2.Peer.any_ipv4(),
                connection=ec2.Port.tcp(1433),
                description="Allow connection from SQL Server source database",
            )
        
        return {
            "dms": dms_sg,
            "rds": rds_sg,
        }

    def _create_dms_iam_roles(self) -> Dict[str, iam.Role]:
        """
        Create IAM roles required for DMS operations.
        
        Returns:
            Dict[str, iam.Role]: Dictionary of IAM roles for DMS services
        """
        # DMS VPC Role
        dms_vpc_role = iam.Role(
            self,
            "DmsVpcRole",
            role_name="dms-vpc-role",
            assumed_by=iam.ServicePrincipal("dms.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AmazonDMSVPCManagementRole")
            ],
        )
        
        # DMS CloudWatch Logs Role
        dms_cloudwatch_role = iam.Role(
            self,
            "DmsCloudWatchRole",
            role_name="dms-cloudwatch-logs-role",
            assumed_by=iam.ServicePrincipal("dms.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AmazonDMSCloudWatchLogsRole")
            ],
        )
        
        # DMS Access for Endpoints Role
        dms_access_role = iam.Role(
            self,
            "DmsAccessRole",
            role_name="dms-access-for-endpoint",
            assumed_by=iam.ServicePrincipal("dms.amazonaws.com"),
            inline_policies={
                "DmsEndpointAccess": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "secretsmanager:GetSecretValue",
                                "secretsmanager:DescribeSecret",
                            ],
                            resources=["*"],
                        )
                    ]
                )
            },
        )
        
        return {
            "vpc": dms_vpc_role,
            "cloudwatch": dms_cloudwatch_role,
            "access": dms_access_role,
        }

    def _create_target_database(self) -> rds.DatabaseInstance:
        """
        Create RDS PostgreSQL database as migration target.
        
        Returns:
            rds.DatabaseInstance: The created RDS instance
        """
        # Create secret for database credentials
        db_secret = secretsmanager.Secret(
            self,
            "TargetDatabaseSecret",
            description="Credentials for target PostgreSQL database",
            generate_secret_string=secretsmanager.SecretStringGenerator(
                secret_string_template='{"username": "dbadmin"}',
                generate_string_key="password",
                exclude_characters='"@/\\',
                password_length=16,
            ),
        )
        
        # Create RDS subnet group
        rds_subnet_group = rds.SubnetGroup(
            self,
            "TargetDatabaseSubnetGroup",
            description="Subnet group for target RDS database",
            vpc=self.vpc,
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS
            ),
        )
        
        # Create RDS instance
        target_db = rds.DatabaseInstance(
            self,
            "TargetDatabase",
            engine=rds.DatabaseInstanceEngine.postgres(
                version=rds.PostgresEngineVersion.VER_14_9
            ),
            instance_type=ec2.InstanceType.of(
                ec2.InstanceClass.BURSTABLE3, ec2.InstanceSize.MEDIUM
            ),
            allocated_storage=100,
            storage_type=rds.StorageType.GP2,
            credentials=rds.Credentials.from_secret(db_secret),
            vpc=self.vpc,
            subnet_group=rds_subnet_group,
            security_groups=[self.security_groups["rds"]],
            backup_retention=cdk.Duration.days(7),
            delete_automated_backups=True,
            deletion_protection=False,
            publicly_accessible=False,
            multi_az=False,
            auto_minor_version_upgrade=True,
            enable_performance_insights=True,
            cloudwatch_logs_exports=["postgresql"],
        )
        
        # Add tags
        Tags.of(target_db).add("Name", "DatabaseMigrationTarget")
        Tags.of(target_db).add("Project", "DatabaseMigration")
        
        return target_db

    def _create_dms_subnet_group(self) -> dms.CfnReplicationSubnetGroup:
        """
        Create DMS subnet group for replication instance placement.
        
        Returns:
            dms.CfnReplicationSubnetGroup: The created DMS subnet group
        """
        subnet_group = dms.CfnReplicationSubnetGroup(
            self,
            "DmsReplicationSubnetGroup",
            replication_subnet_group_description="Subnet group for DMS replication instance",
            replication_subnet_group_identifier="dms-migration-subnet-group",
            subnet_ids=[
                subnet.subnet_id
                for subnet in self.vpc.private_subnets
            ],
            tags=[
                cdk.CfnTag(key="Name", value="DmsReplicationSubnetGroup"),
                cdk.CfnTag(key="Project", value="DatabaseMigration"),
            ],
        )
        
        return subnet_group

    def _create_dms_replication_instance(self) -> dms.CfnReplicationInstance:
        """
        Create DMS replication instance for data migration.
        
        Returns:
            dms.CfnReplicationInstance: The created DMS replication instance
        """
        replication_instance = dms.CfnReplicationInstance(
            self,
            "DmsReplicationInstance",
            replication_instance_class="dms.t3.medium",
            replication_instance_identifier="dms-migration-instance",
            allocated_storage=100,
            replication_subnet_group_identifier=self.dms_subnet_group.replication_subnet_group_identifier,
            vpc_security_group_ids=[self.security_groups["dms"].security_group_id],
            publicly_accessible=False,
            multi_az=False,
            engine_version="3.5.2",
            tags=[
                cdk.CfnTag(key="Name", value="DmsReplicationInstance"),
                cdk.CfnTag(key="Project", value="DatabaseMigration"),
            ],
        )
        
        # Add dependency on subnet group
        replication_instance.add_depends_on(self.dms_subnet_group)
        
        return replication_instance

    def _create_dms_endpoints(self) -> Dict[str, dms.CfnEndpoint]:
        """
        Create DMS endpoints for source and target databases.
        
        Returns:
            Dict[str, dms.CfnEndpoint]: Dictionary of DMS endpoints
        """
        # Source database endpoint
        source_endpoint = dms.CfnEndpoint(
            self,
            "SourceDatabaseEndpoint",
            endpoint_type="source",
            engine_name=self.source_db_config.get("engine", "oracle"),
            endpoint_identifier="source-database-endpoint",
            server_name=self.source_db_config.get("host", "source-db-host"),
            port=int(self.source_db_config.get("port", "1521")),
            username=self.source_db_config.get("username", "source-username"),
            password=self.source_db_config.get("password", "source-password"),
            database_name=self.source_db_config.get("database", "source-database"),
            tags=[
                cdk.CfnTag(key="Name", value="SourceDatabaseEndpoint"),
                cdk.CfnTag(key="Project", value="DatabaseMigration"),
                cdk.CfnTag(key="EndpointType", value="Source"),
            ],
        )
        
        # Target database endpoint
        target_endpoint = dms.CfnEndpoint(
            self,
            "TargetDatabaseEndpoint",
            endpoint_type="target",
            engine_name="postgres",
            endpoint_identifier="target-database-endpoint",
            server_name=self.target_database.instance_endpoint.hostname,
            port=5432,
            username="dbadmin",
            password=self.target_database.secret.secret_value_from_json("password").to_string(),
            database_name="postgres",
            tags=[
                cdk.CfnTag(key="Name", value="TargetDatabaseEndpoint"),
                cdk.CfnTag(key="Project", value="DatabaseMigration"),
                cdk.CfnTag(key="EndpointType", value="Target"),
            ],
        )
        
        return {
            "source": source_endpoint,
            "target": target_endpoint,
        }

    def _create_cloudwatch_monitoring(self) -> Dict[str, cloudwatch.Dashboard]:
        """
        Create CloudWatch dashboard for monitoring DMS migration.
        
        Returns:
            Dict[str, cloudwatch.Dashboard]: Dictionary of CloudWatch resources
        """
        # Create CloudWatch log group for DMS
        log_group = logs.LogGroup(
            self,
            "DmsLogGroup",
            log_group_name="/aws/dms/tasks",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=cdk.RemovalPolicy.DESTROY,
        )
        
        # Create CloudWatch dashboard
        dashboard = cloudwatch.Dashboard(
            self,
            "DmsMigrationDashboard",
            dashboard_name="DMS-Migration-Dashboard",
            widgets=[
                [
                    cloudwatch.GraphWidget(
                        title="DMS Replication Instance Metrics",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/DMS",
                                metric_name="FreeableMemory",
                                dimensions_map={
                                    "ReplicationInstanceIdentifier": self.replication_instance.replication_instance_identifier
                                },
                                statistic="Average",
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/DMS",
                                metric_name="CPUUtilization",
                                dimensions_map={
                                    "ReplicationInstanceIdentifier": self.replication_instance.replication_instance_identifier
                                },
                                statistic="Average",
                            ),
                        ],
                        right=[
                            cloudwatch.Metric(
                                namespace="AWS/DMS",
                                metric_name="NetworkTransmitThroughput",
                                dimensions_map={
                                    "ReplicationInstanceIdentifier": self.replication_instance.replication_instance_identifier
                                },
                                statistic="Average",
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/DMS",
                                metric_name="NetworkReceiveThroughput",
                                dimensions_map={
                                    "ReplicationInstanceIdentifier": self.replication_instance.replication_instance_identifier
                                },
                                statistic="Average",
                            ),
                        ],
                        width=12,
                        height=6,
                    ),
                ],
                [
                    cloudwatch.GraphWidget(
                        title="Migration Task Throughput",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/DMS",
                                metric_name="FullLoadThroughputBandwidthTarget",
                                statistic="Average",
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/DMS",
                                metric_name="FullLoadThroughputRowsTarget",
                                statistic="Average",
                            ),
                        ],
                        right=[
                            cloudwatch.Metric(
                                namespace="AWS/DMS",
                                metric_name="CDCThroughputBandwidthTarget",
                                statistic="Average",
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/DMS",
                                metric_name="CDCThroughputRowsTarget",
                                statistic="Average",
                            ),
                        ],
                        width=12,
                        height=6,
                    ),
                ],
            ],
        )
        
        return {
            "dashboard": dashboard,
            "log_group": log_group,
        }

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information."""
        # VPC outputs
        cdk.CfnOutput(
            self,
            "VpcId",
            value=self.vpc.vpc_id,
            description="VPC ID for database migration infrastructure",
        )
        
        # DMS outputs
        cdk.CfnOutput(
            self,
            "DmsReplicationInstanceId",
            value=self.replication_instance.replication_instance_identifier,
            description="DMS replication instance identifier",
        )
        
        cdk.CfnOutput(
            self,
            "DmsSubnetGroupId",
            value=self.dms_subnet_group.replication_subnet_group_identifier,
            description="DMS subnet group identifier",
        )
        
        # RDS outputs
        cdk.CfnOutput(
            self,
            "TargetDatabaseEndpoint",
            value=self.target_database.instance_endpoint.hostname,
            description="Target PostgreSQL database endpoint",
        )
        
        cdk.CfnOutput(
            self,
            "TargetDatabasePort",
            value=str(self.target_database.instance_endpoint.port),
            description="Target PostgreSQL database port",
        )
        
        # Endpoint outputs
        cdk.CfnOutput(
            self,
            "SourceEndpointId",
            value=self.endpoints["source"].endpoint_identifier,
            description="Source database endpoint identifier",
        )
        
        cdk.CfnOutput(
            self,
            "TargetEndpointId",
            value=self.endpoints["target"].endpoint_identifier,
            description="Target database endpoint identifier",
        )
        
        # Monitoring outputs
        cdk.CfnOutput(
            self,
            "CloudWatchDashboardUrl",
            value=f"https://console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.monitoring['dashboard'].dashboard_name}",
            description="CloudWatch dashboard URL for monitoring migration",
        )


def main() -> None:
    """
    Main function to create and deploy the CDK application.
    """
    app = App()
    
    # Get configuration from environment variables or use defaults
    source_db_config = {
        "engine": os.getenv("SOURCE_DB_ENGINE", "oracle"),
        "host": os.getenv("SOURCE_DB_HOST", "source-db-host"),
        "port": os.getenv("SOURCE_DB_PORT", "1521"),
        "username": os.getenv("SOURCE_DB_USERNAME", "source-username"),
        "password": os.getenv("SOURCE_DB_PASSWORD", "source-password"),
        "database": os.getenv("SOURCE_DB_DATABASE", "source-database"),
    }
    
    # Create the stack
    migration_stack = DatabaseMigrationStack(
        app,
        "DatabaseMigrationStack",
        source_db_config=source_db_config,
        env=Environment(
            account=os.getenv("CDK_DEFAULT_ACCOUNT"),
            region=os.getenv("CDK_DEFAULT_REGION", "us-east-1"),
        ),
        description="Complete infrastructure for database migration using AWS DMS and Schema Conversion Tool",
    )
    
    # Add stack-level tags
    Tags.of(migration_stack).add("Project", "DatabaseMigration")
    Tags.of(migration_stack).add("Environment", "Migration")
    Tags.of(migration_stack).add("ManagedBy", "CDK")
    
    app.synth()


if __name__ == "__main__":
    main()