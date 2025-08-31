#!/usr/bin/env python3
"""
AWS CDK application for TCP Resource Connectivity with VPC Lattice and CloudWatch.

This application creates a complete infrastructure setup demonstrating secure TCP connectivity 
to RDS databases across VPCs using Amazon VPC Lattice service networking. The solution includes:
- VPC Lattice service network for cross-VPC connectivity
- RDS MySQL instance with private subnet deployment
- TCP target groups and listeners for database connections
- CloudWatch monitoring and alerting for observability
- IAM roles and security groups for proper access control

Author: AWS CDK Generator
Version: 1.0
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    CfnOutput,
    RemovalPolicy,
    Duration,
    aws_ec2 as ec2,
    aws_rds as rds,
    aws_vpclattice as lattice,
    aws_iam as iam,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
)
from constructs import Construct
import json


class TcpResourceConnectivityStack(Stack):
    """
    CDK Stack for TCP Resource Connectivity with VPC Lattice and CloudWatch.
    
    This stack creates a comprehensive solution for secure database connectivity
    across VPCs using Amazon VPC Lattice service mesh networking with full
    observability through CloudWatch integration.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Stack parameters that can be customized
        self.db_username = "admin"
        self.db_name = "latticedb"
        self.service_network_name = f"database-service-network-{self.node.addr}"
        self.database_service_name = f"rds-database-service-{self.node.addr}"

        # Create VPC for database deployment
        self.vpc = self._create_vpc()
        
        # Create security groups for database and VPC Lattice
        self.db_security_group = self._create_database_security_group()
        self.lattice_security_group = self._create_lattice_security_group()
        
        # Create RDS database instance
        self.database = self._create_rds_database()
        
        # Create VPC Lattice service network
        self.service_network = self._create_service_network()
        
        # Create target group for RDS database
        self.target_group = self._create_target_group()
        
        # Create VPC Lattice service for database access
        self.database_service = self._create_database_service()
        
        # Create TCP listener for MySQL connections
        self.listener = self._create_tcp_listener()
        
        # Associate service with service network
        self._create_service_association()
        
        # Associate VPC with service network
        self._create_vpc_association()
        
        # Create CloudWatch monitoring and alerting
        self._create_monitoring()
        
        # Create stack outputs
        self._create_outputs()

    def _create_vpc(self) -> ec2.Vpc:
        """
        Create VPC with public and private subnets for database deployment.
        
        Returns:
            ec2.Vpc: The created VPC with appropriate subnet configuration
        """
        vpc = ec2.Vpc(
            self, "DatabaseVPC",
            vpc_name="vpc-lattice-database-vpc",
            max_azs=2,
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="public",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24
                ),
                ec2.SubnetConfiguration(
                    name="private-db",
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                    cidr_mask=24
                )
            ],
            enable_dns_hostnames=True,
            enable_dns_support=True
        )
        
        # Add tags to VPC for better organization
        cdk.Tags.of(vpc).add("Project", "VPCLatticeDemo")
        cdk.Tags.of(vpc).add("Component", "NetworkInfrastructure")
        
        return vpc

    def _create_database_security_group(self) -> ec2.SecurityGroup:
        """
        Create security group for RDS database with MySQL port access.
        
        Returns:
            ec2.SecurityGroup: Security group configured for MySQL access
        """
        sg = ec2.SecurityGroup(
            self, "DatabaseSecurityGroup",
            vpc=self.vpc,
            description="Security group for RDS database allowing MySQL access from VPC Lattice",
            security_group_name="vpc-lattice-database-sg"
        )
        
        # Allow MySQL access from within VPC
        sg.add_ingress_rule(
            peer=ec2.Peer.ipv4(self.vpc.vpc_cidr_block),
            connection=ec2.Port.tcp(3306),
            description="MySQL access from VPC CIDR"
        )
        
        return sg

    def _create_lattice_security_group(self) -> ec2.SecurityGroup:
        """
        Create security group for VPC Lattice service network.
        
        Returns:
            ec2.SecurityGroup: Security group for VPC Lattice operations
        """
        sg = ec2.SecurityGroup(
            self, "LatticeSecurityGroup",
            vpc=self.vpc,
            description="Security group for VPC Lattice service network operations",
            security_group_name="vpc-lattice-service-sg"
        )
        
        # Allow all outbound traffic for VPC Lattice operations
        sg.add_egress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.all_traffic(),
            description="Allow all outbound traffic for VPC Lattice"
        )
        
        return sg

    def _create_rds_database(self) -> rds.DatabaseInstance:
        """
        Create RDS MySQL database instance in private subnets.
        
        Returns:
            rds.DatabaseInstance: The created RDS database instance
        """
        # Create subnet group for RDS deployment
        subnet_group = rds.SubnetGroup(
            self, "DatabaseSubnetGroup",
            description="Subnet group for VPC Lattice demo database",
            vpc=self.vpc,
            vpc_subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS)
        )
        
        # Create parameter group for MySQL 8.0
        parameter_group = rds.ParameterGroup(
            self, "DatabaseParameterGroup",
            engine=rds.DatabaseInstanceEngine.mysql(
                version=rds.MysqlEngineVersion.VER_8_0_35
            ),
            description="Parameter group for VPC Lattice demo database"
        )
        
        # Create the RDS database instance
        database = rds.DatabaseInstance(
            self, "Database",
            engine=rds.DatabaseInstanceEngine.mysql(
                version=rds.MysqlEngineVersion.VER_8_0_35
            ),
            instance_type=ec2.InstanceType.of(
                ec2.InstanceClass.T3,
                ec2.InstanceSize.MICRO
            ),
            credentials=rds.Credentials.from_generated_secret(
                username=self.db_username,
                secret_name=f"vpc-lattice-db-credentials-{self.node.addr}"
            ),
            database_name=self.db_name,
            vpc=self.vpc,
            subnet_group=subnet_group,
            security_groups=[self.db_security_group],
            parameter_group=parameter_group,
            allocated_storage=20,
            storage_type=rds.StorageType.GP2,
            backup_retention=Duration.days(1),
            delete_automated_backups=True,
            deletion_protection=False,
            publicly_accessible=False,
            port=3306,
            removal_policy=RemovalPolicy.DESTROY,
            auto_minor_version_upgrade=True,
            multi_az=False,  # Single AZ for cost optimization in demo
            storage_encrypted=True
        )
        
        # Add tags for resource organization
        cdk.Tags.of(database).add("Project", "VPCLatticeDemo")
        cdk.Tags.of(database).add("Component", "Database")
        
        return database

    def _create_service_network(self) -> lattice.CfnServiceNetwork:
        """
        Create VPC Lattice service network for cross-VPC connectivity.
        
        Returns:
            lattice.CfnServiceNetwork: The created service network
        """
        service_network = lattice.CfnServiceNetwork(
            self, "ServiceNetwork",
            name=self.service_network_name,
            auth_type="AWS_IAM"
        )
        
        # Add tags for resource organization
        cdk.Tags.of(service_network).add("Project", "VPCLatticeDemo")
        cdk.Tags.of(service_network).add("Component", "ServiceMesh")
        
        return service_network

    def _create_target_group(self) -> lattice.CfnTargetGroup:
        """
        Create TCP target group for RDS database connections.
        
        Returns:
            lattice.CfnTargetGroup: The created target group
        """
        target_group = lattice.CfnTargetGroup(
            self, "DatabaseTargetGroup",
            name=f"rds-tcp-targets-{self.node.addr}",
            type="IP",
            config=lattice.CfnTargetGroup.TargetGroupConfigProperty(
                port=3306,
                protocol="TCP",
                vpc_identifier=self.vpc.vpc_id,
                health_check=lattice.CfnTargetGroup.HealthCheckConfigProperty(
                    enabled=True,
                    protocol="TCP",
                    port=3306,
                    health_check_interval_seconds=30,
                    health_check_timeout_seconds=5,
                    healthy_threshold_count=2,
                    unhealthy_threshold_count=2
                )
            ),
            targets=[
                lattice.CfnTargetGroup.TargetProperty(
                    id=self.database.instance_endpoint.hostname,
                    port=3306
                )
            ]
        )
        
        # Ensure target group is created after database
        target_group.node.add_dependency(self.database)
        
        return target_group

    def _create_database_service(self) -> lattice.CfnService:
        """
        Create VPC Lattice service for database access.
        
        Returns:
            lattice.CfnService: The created database service
        """
        service = lattice.CfnService(
            self, "DatabaseService",
            name=self.database_service_name,
            auth_type="AWS_IAM"
        )
        
        # Add tags for resource organization
        cdk.Tags.of(service).add("Project", "VPCLatticeDemo")
        cdk.Tags.of(service).add("Component", "DatabaseService")
        
        return service

    def _create_tcp_listener(self) -> lattice.CfnListener:
        """
        Create TCP listener for MySQL connections on port 3306.
        
        Returns:
            lattice.CfnListener: The created TCP listener
        """
        listener = lattice.CfnListener(
            self, "MySQLListener",
            name="mysql-tcp-listener",
            service_identifier=self.database_service.attr_id,
            protocol="TCP",
            port=3306,
            default_action=lattice.CfnListener.DefaultActionProperty(
                forward=lattice.CfnListener.ForwardProperty(
                    target_groups=[
                        lattice.CfnListener.WeightedTargetGroupProperty(
                            target_group_identifier=self.target_group.attr_id,
                            weight=100
                        )
                    ]
                )
            )
        )
        
        # Ensure listener is created after target group
        listener.node.add_dependency(self.target_group)
        
        return listener

    def _create_service_association(self) -> lattice.CfnServiceNetworkServiceAssociation:
        """
        Associate database service with service network.
        
        Returns:
            lattice.CfnServiceNetworkServiceAssociation: The service association
        """
        association = lattice.CfnServiceNetworkServiceAssociation(
            self, "ServiceAssociation",
            service_identifier=self.database_service.attr_id,
            service_network_identifier=self.service_network.attr_id
        )
        
        # Ensure association is created after service and network
        association.node.add_dependency(self.database_service)
        association.node.add_dependency(self.service_network)
        
        return association

    def _create_vpc_association(self) -> lattice.CfnServiceNetworkVpcAssociation:
        """
        Associate VPC with service network for connectivity.
        
        Returns:
            lattice.CfnServiceNetworkVpcAssociation: The VPC association
        """
        association = lattice.CfnServiceNetworkVpcAssociation(
            self, "VPCAssociation",
            service_network_identifier=self.service_network.attr_id,
            vpc_identifier=self.vpc.vpc_id,
            security_group_ids=[self.lattice_security_group.security_group_id]
        )
        
        # Ensure association is created after service network
        association.node.add_dependency(self.service_network)
        
        return association

    def _create_monitoring(self) -> None:
        """Create CloudWatch monitoring and alerting for VPC Lattice service."""
        
        # Create CloudWatch dashboard for VPC Lattice metrics
        dashboard = cloudwatch.Dashboard(
            self, "VPCLatticeDashboard",
            dashboard_name=f"VPCLattice-Database-Monitoring-{self.node.addr}"
        )
        
        # Connection metrics widget
        connection_widget = cloudwatch.GraphWidget(
            title="Database Connection Metrics",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/VpcLattice",
                    metric_name="NewConnectionCount",
                    dimensions_map={
                        "TargetGroup": self.target_group.attr_id
                    },
                    statistic="Sum",
                    period=Duration.minutes(5)
                ),
                cloudwatch.Metric(
                    namespace="AWS/VpcLattice",
                    metric_name="ActiveConnectionCount",
                    dimensions_map={
                        "TargetGroup": self.target_group.attr_id
                    },
                    statistic="Sum",
                    period=Duration.minutes(5)
                ),
                cloudwatch.Metric(
                    namespace="AWS/VpcLattice",
                    metric_name="ConnectionErrorCount",
                    dimensions_map={
                        "TargetGroup": self.target_group.attr_id
                    },
                    statistic="Sum",
                    period=Duration.minutes(5)
                )
            ],
            width=12,
            height=6
        )
        
        # Traffic volume widget
        traffic_widget = cloudwatch.GraphWidget(
            title="Database Traffic Volume",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/VpcLattice",
                    metric_name="ProcessedBytes",
                    dimensions_map={
                        "TargetGroup": self.target_group.attr_id
                    },
                    statistic="Sum",
                    period=Duration.minutes(5)
                )
            ],
            width=12,
            height=6
        )
        
        # Add widgets to dashboard
        dashboard.add_widgets(connection_widget)
        dashboard.add_widgets(traffic_widget)
        
        # Create CloudWatch alarm for connection errors
        connection_error_alarm = cloudwatch.Alarm(
            self, "ConnectionErrorAlarm",
            alarm_name=f"VPCLattice-Database-Connection-Errors-{self.node.addr}",
            alarm_description="Alert on database connection errors through VPC Lattice",
            metric=cloudwatch.Metric(
                namespace="AWS/VpcLattice",
                metric_name="ConnectionErrorCount",
                dimensions_map={
                    "TargetGroup": self.target_group.attr_id
                },
                statistic="Sum",
                period=Duration.minutes(5)
            ),
            threshold=5,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information."""
        
        CfnOutput(
            self, "VPCId",
            value=self.vpc.vpc_id,
            description="VPC ID for the database deployment"
        )
        
        CfnOutput(
            self, "DatabaseEndpoint",
            value=self.database.instance_endpoint.hostname,
            description="RDS database endpoint hostname"
        )
        
        CfnOutput(
            self, "DatabasePort",
            value=str(self.database.instance_endpoint.port),
            description="RDS database port number"
        )
        
        CfnOutput(
            self, "ServiceNetworkId",
            value=self.service_network.attr_id,
            description="VPC Lattice service network identifier"
        )
        
        CfnOutput(
            self, "DatabaseServiceId",
            value=self.database_service.attr_id,
            description="VPC Lattice database service identifier"
        )
        
        CfnOutput(
            self, "TargetGroupId",
            value=self.target_group.attr_id,
            description="VPC Lattice target group identifier"
        )
        
        CfnOutput(
            self, "ServiceEndpoint",
            value=f"{self.database_service_name}.{self.service_network.attr_id}.vpc-lattice-svcs.{self.region}.on.aws",
            description="VPC Lattice service endpoint for database connections"
        )
        
        CfnOutput(
            self, "DatabaseCredentialsSecret",
            value=self.database.secret.secret_name if self.database.secret else "N/A",
            description="AWS Secrets Manager secret name for database credentials"
        )


# CDK Application
app = cdk.App()

# Create the main stack
tcp_connectivity_stack = TcpResourceConnectivityStack(
    app, 
    "TcpResourceConnectivityStack",
    description="TCP Resource Connectivity with VPC Lattice and CloudWatch",
    env=cdk.Environment(
        account=app.node.try_get_context("account") or "123456789012",
        region=app.node.try_get_context("region") or "us-east-1"
    )
)

# Add stack-level tags
cdk.Tags.of(tcp_connectivity_stack).add("Project", "VPCLatticeDemo")
cdk.Tags.of(tcp_connectivity_stack).add("Environment", "Demo")
cdk.Tags.of(tcp_connectivity_stack).add("ManagedBy", "CDK")

app.synth()