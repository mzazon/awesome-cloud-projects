#!/usr/bin/env python3
"""
CDK Python Application for Database Scaling Strategies with Aurora Serverless

This CDK application deploys Aurora Serverless v2 cluster with automatic scaling,
monitoring, and security configurations for handling variable database workloads.
"""

import aws_cdk as cdk
from aws_cdk import (
    Duration,
    Stack,
    aws_rds as rds,
    aws_ec2 as ec2,
    aws_cloudwatch as cloudwatch,
    aws_iam as iam,
    aws_logs as logs,
    CfnOutput,
    RemovalPolicy,
)
from constructs import Construct
from typing import Optional


class AuroraServerlessStack(Stack):
    """
    CDK Stack for Aurora Serverless v2 database scaling implementation.
    
    This stack creates:
    - VPC with public/private subnets (if not provided)
    - Aurora Serverless v2 MySQL cluster
    - Security groups with least privilege access
    - CloudWatch monitoring and alarms
    - Performance Insights enabled instances
    - Custom parameter groups for optimization
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        vpc: Optional[ec2.Vpc] = None,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Configuration parameters
        self.min_capacity = 0.5
        self.max_capacity = 16.0
        self.db_name = "ecommerce"
        self.username = "admin"
        
        # Use provided VPC or create new one
        self.vpc = vpc or self._create_vpc()
        
        # Create security group for Aurora cluster
        self.security_group = self._create_security_group()
        
        # Create DB subnet group
        self.subnet_group = self._create_subnet_group()
        
        # Create custom parameter groups
        self.cluster_parameter_group = self._create_cluster_parameter_group()
        
        # Create Aurora Serverless v2 cluster
        self.cluster = self._create_aurora_cluster()
        
        # Create database instances
        self.writer_instance = self._create_writer_instance()
        self.reader_instance = self._create_reader_instance()
        
        # Create CloudWatch monitoring and alarms
        self._create_cloudwatch_alarms()
        
        # Create outputs
        self._create_outputs()

    def _create_vpc(self) -> ec2.Vpc:
        """Create VPC with public and private subnets for Aurora cluster."""
        return ec2.Vpc(
            self,
            "AuroraVpc",
            ip_protocol=ec2.IpProtocol.DUAL_STACK,
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

    def _create_security_group(self) -> ec2.SecurityGroup:
        """Create security group for Aurora cluster with least privilege access."""
        sg = ec2.SecurityGroup(
            self,
            "AuroraSecurityGroup",
            vpc=self.vpc,
            description="Security group for Aurora Serverless cluster",
            allow_all_outbound=False,
        )

        # Allow MySQL access from within VPC
        sg.add_ingress_rule(
            peer=ec2.Peer.ipv4(self.vpc.vpc_cidr_block),
            connection=ec2.Port.tcp(3306),
            description="MySQL access from VPC",
        )

        # Add egress rule for HTTPS (for AWS API calls)
        sg.add_egress_rule(
            peer=ec2.Peer.ipv4("0.0.0.0/0"),
            connection=ec2.Port.tcp(443),
            description="HTTPS outbound for AWS APIs",
        )

        return sg

    def _create_subnet_group(self) -> rds.SubnetGroup:
        """Create DB subnet group for Aurora cluster."""
        return rds.SubnetGroup(
            self,
            "AuroraSubnetGroup",
            description="Subnet group for Aurora Serverless cluster",
            vpc=self.vpc,
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PRIVATE_ISOLATED
            ),
            removal_policy=RemovalPolicy.DESTROY,
        )

    def _create_cluster_parameter_group(self) -> rds.ParameterGroup:
        """Create custom parameter group for Aurora cluster optimization."""
        return rds.ParameterGroup(
            self,
            "AuroraClusterParameterGroup",
            engine=rds.DatabaseClusterEngine.aurora_mysql(
                version=rds.AuroraMysqlEngineVersion.VER_8_0_35
            ),
            description="Custom parameter group for Aurora Serverless optimization",
            parameters={
                # Connection and session settings
                "max_connections": "1000",
                "wait_timeout": "3600",
                "interactive_timeout": "3600",
                # Performance optimization
                "innodb_buffer_pool_size": "{DBInstanceClassMemory*3/4}",
                "query_cache_type": "1",
                "query_cache_size": "33554432",
                # Logging optimization
                "slow_query_log": "1",
                "long_query_time": "2",
                "log_queries_not_using_indexes": "1",
            },
        )

    def _create_aurora_cluster(self) -> rds.DatabaseCluster:
        """Create Aurora Serverless v2 cluster with automatic scaling."""
        # Generate a secure password
        password = rds.DatabaseSecret(
            self,
            "AuroraPassword",
            username=self.username,
            description="Aurora cluster master password",
            exclude_characters=" \"@/\\",
        )

        cluster = rds.DatabaseCluster(
            self,
            "AuroraServerlessCluster",
            engine=rds.DatabaseClusterEngine.aurora_mysql(
                version=rds.AuroraMysqlEngineVersion.VER_8_0_35
            ),
            credentials=rds.Credentials.from_secret(password),
            default_database_name=self.db_name,
            vpc=self.vpc,
            subnet_group=self.subnet_group,
            security_groups=[self.security_group],
            parameter_group=self.cluster_parameter_group,
            serverless_v2_min_capacity=self.min_capacity,
            serverless_v2_max_capacity=self.max_capacity,
            cloudwatch_logs_exports=["error", "general", "slowquery"],
            cloudwatch_logs_retention=logs.RetentionDays.ONE_WEEK,
            backup=rds.BackupProps(
                retention=Duration.days(7),
                preferred_window="03:00-04:00",
            ),
            preferred_maintenance_window="sun:04:00-sun:05:00",
            deletion_protection=True,
            removal_policy=RemovalPolicy.SNAPSHOT,
            storage_encrypted=True,
        )

        return cluster

    def _create_writer_instance(self) -> rds.DatabaseInstance:
        """Create Aurora Serverless v2 writer instance."""
        return rds.DatabaseInstance(
            self,
            "AuroraWriterInstance",
            instance_type=ec2.InstanceType.of(
                ec2.InstanceClass.BURSTABLE3, ec2.InstanceSize.SMALL
            ),
            engine=rds.DatabaseInstanceEngine.AURORA_MYSQL,
            cluster=self.cluster,
            enable_performance_insights=True,
            performance_insight_retention=rds.PerformanceInsightRetention.DEFAULT,
            auto_minor_version_upgrade=True,
            allow_major_version_upgrade=False,
            deletion_protection=True,
            removal_policy=RemovalPolicy.SNAPSHOT,
        )

    def _create_reader_instance(self) -> rds.DatabaseInstance:
        """Create Aurora Serverless v2 read replica instance."""
        return rds.DatabaseInstance(
            self,
            "AuroraReaderInstance",
            instance_type=ec2.InstanceType.of(
                ec2.InstanceClass.BURSTABLE3, ec2.InstanceSize.SMALL
            ),
            engine=rds.DatabaseInstanceEngine.AURORA_MYSQL,
            cluster=self.cluster,
            enable_performance_insights=True,
            performance_insight_retention=rds.PerformanceInsightRetention.DEFAULT,
            auto_minor_version_upgrade=True,
            allow_major_version_upgrade=False,
            deletion_protection=True,
            removal_policy=RemovalPolicy.SNAPSHOT,
        )

    def _create_cloudwatch_alarms(self) -> None:
        """Create CloudWatch alarms for monitoring Aurora capacity and performance."""
        # High ACU utilization alarm
        high_acu_alarm = cloudwatch.Alarm(
            self,
            "HighACUAlarm",
            alarm_description="Alert when Aurora ACU usage is high",
            metric=cloudwatch.Metric(
                namespace="AWS/RDS",
                metric_name="ServerlessDatabaseCapacity",
                dimensions_map={"DBClusterIdentifier": self.cluster.cluster_identifier},
                statistic="Average",
                period=Duration.minutes(5),
            ),
            threshold=12.0,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

        # Low ACU utilization alarm
        low_acu_alarm = cloudwatch.Alarm(
            self,
            "LowACUAlarm",
            alarm_description="Alert when Aurora ACU usage is consistently low",
            metric=cloudwatch.Metric(
                namespace="AWS/RDS",
                metric_name="ServerlessDatabaseCapacity",
                dimensions_map={"DBClusterIdentifier": self.cluster.cluster_identifier},
                statistic="Average",
                period=Duration.minutes(15),
            ),
            threshold=1.0,
            comparison_operator=cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
            evaluation_periods=4,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

        # High CPU utilization alarm
        cpu_alarm = cloudwatch.Alarm(
            self,
            "HighCPUAlarm",
            alarm_description="Alert when Aurora CPU usage is high",
            metric=cloudwatch.Metric(
                namespace="AWS/RDS",
                metric_name="CPUUtilization",
                dimensions_map={"DBClusterIdentifier": self.cluster.cluster_identifier},
                statistic="Average",
                period=Duration.minutes(5),
            ),
            threshold=80.0,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=3,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

        # Database connections alarm
        connections_alarm = cloudwatch.Alarm(
            self,
            "HighConnectionsAlarm",
            alarm_description="Alert when database connections are high",
            metric=cloudwatch.Metric(
                namespace="AWS/RDS",
                metric_name="DatabaseConnections",
                dimensions_map={"DBClusterIdentifier": self.cluster.cluster_identifier},
                statistic="Average",
                period=Duration.minutes(5),
            ),
            threshold=800.0,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important cluster information."""
        CfnOutput(
            self,
            "ClusterIdentifier",
            value=self.cluster.cluster_identifier,
            description="Aurora cluster identifier",
        )

        CfnOutput(
            self,
            "ClusterEndpoint",
            value=self.cluster.cluster_endpoint.hostname,
            description="Aurora cluster writer endpoint",
        )

        CfnOutput(
            self,
            "ClusterReaderEndpoint",
            value=self.cluster.cluster_read_endpoint.hostname,
            description="Aurora cluster reader endpoint",
        )

        CfnOutput(
            self,
            "ClusterPort",
            value=str(self.cluster.cluster_endpoint.port),
            description="Aurora cluster port",
        )

        CfnOutput(
            self,
            "DatabaseName",
            value=self.db_name,
            description="Default database name",
        )

        CfnOutput(
            self,
            "MasterUsername",
            value=self.username,
            description="Master username for Aurora cluster",
        )

        CfnOutput(
            self,
            "SecurityGroupId",
            value=self.security_group.security_group_id,
            description="Security group ID for Aurora cluster",
        )

        CfnOutput(
            self,
            "VpcId",
            value=self.vpc.vpc_id,
            description="VPC ID where Aurora cluster is deployed",
        )


class AuroraServerlessApp(cdk.App):
    """CDK Application for Aurora Serverless database scaling."""

    def __init__(self) -> None:
        super().__init__()

        # Create the Aurora Serverless stack
        aurora_stack = AuroraServerlessStack(
            self,
            "AuroraServerlessStack",
            description="Aurora Serverless v2 cluster with automatic scaling for variable workloads",
            env=cdk.Environment(
                account=self.node.try_get_context("account"),
                region=self.node.try_get_context("region"),
            ),
        )

        # Add tags to all resources
        cdk.Tags.of(aurora_stack).add("Project", "AuroraServerlessScaling")
        cdk.Tags.of(aurora_stack).add("Environment", "Development")
        cdk.Tags.of(aurora_stack).add("Owner", "DatabaseTeam")
        cdk.Tags.of(aurora_stack).add("CostCenter", "Engineering")


# Create and run the CDK application
if __name__ == "__main__":
    app = AuroraServerlessApp()
    app.synth()