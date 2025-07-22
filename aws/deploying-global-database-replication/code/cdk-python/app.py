#!/usr/bin/env python3
"""
Aurora Global Database CDK Application

This CDK application deploys an Aurora Global Database with write forwarding
across multiple AWS regions, enabling multi-master-like functionality
while maintaining strong consistency.

Recipe: Deploying Global Database Replication with Aurora Global Database
"""

import os
from typing import Dict, List, Optional
import aws_cdk as cdk
from aws_cdk import (
    Duration,
    Environment,
    Stack,
    StackProps,
    aws_rds as rds,
    aws_ec2 as ec2,
    aws_logs as logs,
    aws_cloudwatch as cloudwatch,
    aws_secretsmanager as secretsmanager,
    aws_ssm as ssm,
    aws_iam as iam,
    RemovalPolicy,
    Tags,
)
from constructs import Construct


class AuroraGlobalDatabaseStack(Stack):
    """
    Stack for Aurora Global Database with multi-region replication
    and write forwarding capabilities.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        is_primary: bool,
        global_cluster_identifier: str,
        vpc: Optional[ec2.Vpc] = None,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        self.is_primary = is_primary
        self.global_cluster_identifier = global_cluster_identifier
        self.region = self.region
        
        # Create VPC if not provided
        if vpc is None:
            self.vpc = self._create_vpc()
        else:
            self.vpc = vpc

        # Create database subnet group
        self.db_subnet_group = self._create_subnet_group()

        # Create security group
        self.security_group = self._create_security_group()

        # Create cluster parameter group
        self.cluster_parameter_group = self._create_cluster_parameter_group()

        # Create DB parameter group
        self.db_parameter_group = self._create_db_parameter_group()

        # Create master credentials secret (only for primary)
        if self.is_primary:
            self.master_secret = self._create_master_secret()
            
            # Create global cluster
            self.global_cluster = self._create_global_cluster()
            
            # Create primary cluster
            self.primary_cluster = self._create_primary_cluster()
        else:
            # Import master secret from primary region
            self.master_secret = self._import_master_secret()
            
            # Create secondary cluster
            self.secondary_cluster = self._create_secondary_cluster()

        # Create database instances
        self.writer_instance = self._create_writer_instance()
        self.reader_instance = self._create_reader_instance()

        # Create CloudWatch log groups
        self.error_log_group = self._create_log_group("error")
        self.general_log_group = self._create_log_group("general")
        self.slow_query_log_group = self._create_log_group("slowquery")

        # Create monitoring dashboard
        self.dashboard = self._create_monitoring_dashboard()

        # Create SSM parameters for connection information
        self._create_ssm_parameters()

        # Add tags
        self._add_tags()

        # Create outputs
        self._create_outputs()

    def _create_vpc(self) -> ec2.Vpc:
        """Create VPC with public and private subnets."""
        return ec2.Vpc(
            self,
            "AuroraGlobalVPC",
            max_azs=3,
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

    def _create_subnet_group(self) -> rds.SubnetGroup:
        """Create database subnet group."""
        return rds.SubnetGroup(
            self,
            "DatabaseSubnetGroup",
            description="Subnet group for Aurora Global Database",
            vpc=self.vpc,
            subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PRIVATE_ISOLATED
            ),
            removal_policy=RemovalPolicy.DESTROY,
        )

    def _create_security_group(self) -> ec2.SecurityGroup:
        """Create security group for Aurora cluster."""
        sg = ec2.SecurityGroup(
            self,
            "AuroraSecurityGroup",
            vpc=self.vpc,
            description="Security group for Aurora Global Database",
            allow_all_outbound=True,
        )

        # Allow MySQL/Aurora access from VPC
        sg.add_ingress_rule(
            peer=ec2.Peer.ipv4(self.vpc.vpc_cidr_block),
            connection=ec2.Port.tcp(3306),
            description="MySQL/Aurora access from VPC",
        )

        # Allow connections from other regions (for global database)
        sg.add_ingress_rule(
            peer=ec2.Peer.ipv4("10.0.0.0/8"),
            connection=ec2.Port.tcp(3306),
            description="Aurora Global Database cross-region access",
        )

        return sg

    def _create_cluster_parameter_group(self) -> rds.ParameterGroup:
        """Create Aurora cluster parameter group."""
        return rds.ParameterGroup(
            self,
            "AuroraClusterParameterGroup",
            engine=rds.DatabaseClusterEngine.aurora_mysql(
                version=rds.AuroraMysqlEngineVersion.VER_8_0_36
            ),
            parameters={
                "innodb_buffer_pool_size": "{DBInstanceClassMemory*3/4}",
                "innodb_flush_log_at_trx_commit": "1",
                "binlog_format": "ROW",
                "log_bin_trust_function_creators": "1",
                "general_log": "1",
                "slow_query_log": "1",
                "long_query_time": "2",
                "log_queries_not_using_indexes": "1",
            },
            description="Aurora Global Database cluster parameter group",
        )

    def _create_db_parameter_group(self) -> rds.ParameterGroup:
        """Create Aurora DB parameter group."""
        return rds.ParameterGroup(
            self,
            "AuroraDBParameterGroup",
            engine=rds.DatabaseInstanceEngine.mysql(
                version=rds.MysqlEngineVersion.VER_8_0_36
            ),
            parameters={
                "max_connections": "1000",
                "innodb_lock_wait_timeout": "50",
                "wait_timeout": "28800",
                "interactive_timeout": "28800",
            },
            description="Aurora Global Database DB parameter group",
        )

    def _create_master_secret(self) -> secretsmanager.Secret:
        """Create secret for master database credentials."""
        return secretsmanager.Secret(
            self,
            "AuroraMasterSecret",
            description="Master credentials for Aurora Global Database",
            generate_secret_string=secretsmanager.SecretStringGenerator(
                secret_string_template='{"username": "globaladmin"}',
                generate_string_key="password",
                exclude_characters=' "%@/\\\'',
                password_length=32,
                require_each_included_type=True,
            ),
            removal_policy=RemovalPolicy.DESTROY,
        )

    def _import_master_secret(self) -> secretsmanager.ISecret:
        """Import master secret from primary region."""
        return secretsmanager.Secret.from_secret_name_v2(
            self,
            "ImportedMasterSecret",
            f"aurora-global-master-secret-{self.global_cluster_identifier}",
        )

    def _create_global_cluster(self) -> rds.GlobalCluster:
        """Create Aurora Global Database cluster."""
        return rds.GlobalCluster(
            self,
            "AuroraGlobalCluster",
            global_cluster_identifier=self.global_cluster_identifier,
            engine=rds.DatabaseClusterEngine.aurora_mysql(
                version=rds.AuroraMysqlEngineVersion.VER_8_0_36
            ),
            removal_policy=RemovalPolicy.DESTROY,
        )

    def _create_primary_cluster(self) -> rds.DatabaseCluster:
        """Create primary Aurora cluster."""
        return rds.DatabaseCluster(
            self,
            "PrimaryAuroraCluster",
            engine=rds.DatabaseClusterEngine.aurora_mysql(
                version=rds.AuroraMysqlEngineVersion.VER_8_0_36
            ),
            credentials=rds.Credentials.from_secret(self.master_secret),
            vpc=self.vpc,
            subnet_group=self.db_subnet_group,
            security_groups=[self.security_group],
            cluster_parameter_group=self.cluster_parameter_group,
            parameter_group=self.db_parameter_group,
            backup=rds.BackupProps(
                retention=Duration.days(7),
                preferred_window="07:00-09:00",
            ),
            preferred_maintenance_window="sun:09:00-sun:11:00",
            cloudwatch_logs_exports=["error", "general", "slowquery"],
            cloudwatch_logs_retention=logs.RetentionDays.ONE_WEEK,
            monitoring_interval=Duration.minutes(1),
            monitoring_role=self._create_monitoring_role(),
            performance_insight_retention=rds.PerformanceInsightRetention.DEFAULT,
            enable_performance_insights=True,
            global_cluster_identifier=self.global_cluster.global_cluster_identifier,
            removal_policy=RemovalPolicy.DESTROY,
            deletion_protection=False,
        )

    def _create_secondary_cluster(self) -> rds.DatabaseCluster:
        """Create secondary Aurora cluster with write forwarding."""
        return rds.DatabaseCluster(
            self,
            "SecondaryAuroraCluster",
            engine=rds.DatabaseClusterEngine.aurora_mysql(
                version=rds.AuroraMysqlEngineVersion.VER_8_0_36
            ),
            vpc=self.vpc,
            subnet_group=self.db_subnet_group,
            security_groups=[self.security_group],
            cluster_parameter_group=self.cluster_parameter_group,
            parameter_group=self.db_parameter_group,
            cloudwatch_logs_exports=["error", "general", "slowquery"],
            cloudwatch_logs_retention=logs.RetentionDays.ONE_WEEK,
            monitoring_interval=Duration.minutes(1),
            monitoring_role=self._create_monitoring_role(),
            performance_insight_retention=rds.PerformanceInsightRetention.DEFAULT,
            enable_performance_insights=True,
            global_cluster_identifier=self.global_cluster_identifier,
            enable_global_write_forwarding=True,
            removal_policy=RemovalPolicy.DESTROY,
            deletion_protection=False,
        )

    def _create_writer_instance(self) -> rds.DatabaseInstance:
        """Create writer database instance."""
        cluster = self.primary_cluster if self.is_primary else self.secondary_cluster
        
        return rds.DatabaseInstance(
            self,
            "WriterInstance",
            engine=rds.DatabaseInstanceEngine.aurora_mysql(),
            instance_type=ec2.InstanceType.of(
                ec2.InstanceClass.R5, ec2.InstanceSize.LARGE
            ),
            cluster=cluster,
            enable_performance_insights=True,
            performance_insight_retention=rds.PerformanceInsightRetention.DEFAULT,
            monitoring_interval=Duration.minutes(1),
            monitoring_role=self._create_monitoring_role(),
            auto_minor_version_upgrade=True,
            allow_major_version_upgrade=False,
            delete_automated_backups=True,
            removal_policy=RemovalPolicy.DESTROY,
        )

    def _create_reader_instance(self) -> rds.DatabaseInstance:
        """Create reader database instance."""
        cluster = self.primary_cluster if self.is_primary else self.secondary_cluster
        
        return rds.DatabaseInstance(
            self,
            "ReaderInstance",
            engine=rds.DatabaseInstanceEngine.aurora_mysql(),
            instance_type=ec2.InstanceType.of(
                ec2.InstanceClass.R5, ec2.InstanceSize.LARGE
            ),
            cluster=cluster,
            enable_performance_insights=True,
            performance_insight_retention=rds.PerformanceInsightRetention.DEFAULT,
            monitoring_interval=Duration.minutes(1),
            monitoring_role=self._create_monitoring_role(),
            auto_minor_version_upgrade=True,
            allow_major_version_upgrade=False,
            delete_automated_backups=True,
            removal_policy=RemovalPolicy.DESTROY,
        )

    def _create_monitoring_role(self) -> iam.Role:
        """Create IAM role for enhanced monitoring."""
        return iam.Role(
            self,
            "AuroraMonitoringRole",
            assumed_by=iam.ServicePrincipal("monitoring.rds.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AmazonRDSEnhancedMonitoringRole"
                )
            ],
        )

    def _create_log_group(self, log_type: str) -> logs.LogGroup:
        """Create CloudWatch log group for Aurora logs."""
        cluster = self.primary_cluster if self.is_primary else self.secondary_cluster
        
        return logs.LogGroup(
            self,
            f"Aurora{log_type.capitalize()}LogGroup",
            log_group_name=f"/aws/rds/cluster/{cluster.cluster_identifier}/{log_type}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )

    def _create_monitoring_dashboard(self) -> cloudwatch.Dashboard:
        """Create CloudWatch dashboard for monitoring."""
        cluster = self.primary_cluster if self.is_primary else self.secondary_cluster
        role_type = "Primary" if self.is_primary else "Secondary"
        
        dashboard = cloudwatch.Dashboard(
            self,
            "AuroraGlobalDashboard",
            dashboard_name=f"Aurora-Global-{role_type}-{self.region}",
        )

        # Database connections widget
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Database Connections",
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/RDS",
                        metric_name="DatabaseConnections",
                        dimensions_map={
                            "DBClusterIdentifier": cluster.cluster_identifier
                        },
                        statistic="Average",
                        period=Duration.minutes(5),
                    )
                ],
                width=12,
                height=6,
            )
        )

        # CPU utilization widget
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="CPU Utilization",
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/RDS",
                        metric_name="CPUUtilization",
                        dimensions_map={
                            "DBInstanceIdentifier": self.writer_instance.instance_identifier
                        },
                        statistic="Average",
                        period=Duration.minutes(5),
                    ),
                    cloudwatch.Metric(
                        namespace="AWS/RDS",
                        metric_name="CPUUtilization",
                        dimensions_map={
                            "DBInstanceIdentifier": self.reader_instance.instance_identifier
                        },
                        statistic="Average",
                        period=Duration.minutes(5),
                    ),
                ],
                width=12,
                height=6,
            )
        )

        # Add replication lag widget for secondary clusters
        if not self.is_primary:
            dashboard.add_widgets(
                cloudwatch.GraphWidget(
                    title="Global Database Replication Lag",
                    left=[
                        cloudwatch.Metric(
                            namespace="AWS/RDS",
                            metric_name="AuroraGlobalDBReplicationLag",
                            dimensions_map={
                                "DBClusterIdentifier": cluster.cluster_identifier
                            },
                            statistic="Average",
                            period=Duration.minutes(5),
                        )
                    ],
                    width=12,
                    height=6,
                )
            )

        return dashboard

    def _create_ssm_parameters(self) -> None:
        """Create SSM parameters for connection information."""
        cluster = self.primary_cluster if self.is_primary else self.secondary_cluster
        role_type = "primary" if self.is_primary else "secondary"
        
        # Cluster endpoint
        ssm.StringParameter(
            self,
            "ClusterEndpointParameter",
            parameter_name=f"/aurora-global/{self.global_cluster_identifier}/{role_type}/cluster-endpoint",
            string_value=cluster.cluster_endpoint.hostname,
            description=f"Aurora Global Database {role_type} cluster endpoint",
        )

        # Reader endpoint
        ssm.StringParameter(
            self,
            "ReaderEndpointParameter",
            parameter_name=f"/aurora-global/{self.global_cluster_identifier}/{role_type}/reader-endpoint",
            string_value=cluster.cluster_read_endpoint.hostname,
            description=f"Aurora Global Database {role_type} reader endpoint",
        )

        # Database port
        ssm.StringParameter(
            self,
            "DatabasePortParameter",
            parameter_name=f"/aurora-global/{self.global_cluster_identifier}/{role_type}/port",
            string_value=str(cluster.cluster_endpoint.port),
            description=f"Aurora Global Database {role_type} port",
        )

        # VPC ID
        ssm.StringParameter(
            self,
            "VpcIdParameter",
            parameter_name=f"/aurora-global/{self.global_cluster_identifier}/{role_type}/vpc-id",
            string_value=self.vpc.vpc_id,
            description=f"Aurora Global Database {role_type} VPC ID",
        )

        # Security group ID
        ssm.StringParameter(
            self,
            "SecurityGroupIdParameter",
            parameter_name=f"/aurora-global/{self.global_cluster_identifier}/{role_type}/security-group-id",
            string_value=self.security_group.security_group_id,
            description=f"Aurora Global Database {role_type} security group ID",
        )

    def _add_tags(self) -> None:
        """Add tags to all resources."""
        role_type = "Primary" if self.is_primary else "Secondary"
        
        Tags.of(self).add("Project", "Aurora Global Database")
        Tags.of(self).add("Role", role_type)
        Tags.of(self).add("Environment", "Production")
        Tags.of(self).add("GlobalCluster", self.global_cluster_identifier)
        Tags.of(self).add("Region", self.region)

    def _create_outputs(self) -> None:
        """Create stack outputs."""
        cluster = self.primary_cluster if self.is_primary else self.secondary_cluster
        role_type = "Primary" if self.is_primary else "Secondary"
        
        cdk.CfnOutput(
            self,
            "ClusterEndpoint",
            value=cluster.cluster_endpoint.hostname,
            description=f"{role_type} cluster endpoint",
        )

        cdk.CfnOutput(
            self,
            "ReaderEndpoint",
            value=cluster.cluster_read_endpoint.hostname,
            description=f"{role_type} reader endpoint",
        )

        cdk.CfnOutput(
            self,
            "DatabasePort",
            value=str(cluster.cluster_endpoint.port),
            description="Database port",
        )

        cdk.CfnOutput(
            self,
            "ClusterIdentifier",
            value=cluster.cluster_identifier,
            description=f"{role_type} cluster identifier",
        )

        if self.is_primary:
            cdk.CfnOutput(
                self,
                "GlobalClusterIdentifier",
                value=self.global_cluster.global_cluster_identifier,
                description="Global cluster identifier",
            )

            cdk.CfnOutput(
                self,
                "MasterSecretArn",
                value=self.master_secret.secret_arn,
                description="Master credentials secret ARN",
            )

        cdk.CfnOutput(
            self,
            "VpcId",
            value=self.vpc.vpc_id,
            description="VPC ID",
        )

        cdk.CfnOutput(
            self,
            "SecurityGroupId",
            value=self.security_group.security_group_id,
            description="Security group ID",
        )

        cdk.CfnOutput(
            self,
            "DashboardName",
            value=self.dashboard.dashboard_name,
            description="CloudWatch dashboard name",
        )


class AuroraGlobalApp(cdk.App):
    """
    CDK Application for Aurora Global Database deployment.
    """

    def __init__(self) -> None:
        super().__init__()

        # Configuration
        self.global_cluster_identifier = self.node.try_get_context("global_cluster_identifier") or "global-ecommerce-db"
        self.regions = self.node.try_get_context("regions") or {
            "primary": "us-east-1",
            "secondary": ["eu-west-1", "ap-southeast-1"]
        }

        # Create primary stack
        self.primary_stack = AuroraGlobalDatabaseStack(
            self,
            "AuroraGlobalPrimaryStack",
            is_primary=True,
            global_cluster_identifier=self.global_cluster_identifier,
            env=Environment(region=self.regions["primary"]),
        )

        # Create secondary stacks
        self.secondary_stacks = []
        for i, region in enumerate(self.regions["secondary"]):
            secondary_stack = AuroraGlobalDatabaseStack(
                self,
                f"AuroraGlobalSecondaryStack{i+1}",
                is_primary=False,
                global_cluster_identifier=self.global_cluster_identifier,
                env=Environment(region=region),
            )
            
            # Add dependency on primary stack
            secondary_stack.add_dependency(self.primary_stack)
            self.secondary_stacks.append(secondary_stack)


# Create the application
app = AuroraGlobalApp()
app.synth()