#!/usr/bin/env python3
"""
Cross-Account Database Sharing with VPC Lattice and RDS
CDK Python Application

This CDK application implements a secure cross-account database sharing solution
using VPC Lattice resource configurations to provide governed access to RDS
databases without complex networking requirements.

Author: AWS CDK Generator
Version: 1.0
"""

from typing import Optional, Dict, Any
import aws_cdk as cdk
from aws_cdk import (
    Stack,
    App,
    Environment,
    aws_ec2 as ec2,
    aws_rds as rds,
    aws_iam as iam,
    aws_vpclattice as vpclattice,
    aws_ram as ram,
    aws_logs as logs,
    aws_cloudwatch as cloudwatch,
    aws_secretsmanager as secretsmanager,
    RemovalPolicy,
    Duration,
    CfnOutput,
    Tags,
)
from constructs import Construct


class DatabaseSharingStack(Stack):
    """
    Stack implementing cross-account database sharing with VPC Lattice and RDS.
    
    This stack creates:
    - VPC with public and private subnets across multiple AZs
    - RDS MySQL database with encryption and security best practices
    - VPC Lattice resource gateway and service network
    - Resource configuration for cross-account database access
    - IAM roles and policies for secure cross-account access
    - CloudWatch monitoring and dashboards
    - AWS RAM resource sharing configuration
    """

    def __init__(
        self, 
        scope: Construct, 
        construct_id: str, 
        *,
        consumer_account_id: str,
        external_id: str = "unique-external-id-12345",
        db_instance_class: str = "db.t3.micro",
        db_allocated_storage: int = 20,
        **kwargs
    ) -> None:
        """
        Initialize the Database Sharing Stack.
        
        Args:
            scope: CDK construct scope
            construct_id: Unique identifier for this construct
            consumer_account_id: AWS account ID that will consume the shared database
            external_id: External ID for cross-account role assumption security
            db_instance_class: RDS instance class for the database
            db_allocated_storage: Storage allocation for the database in GB
            **kwargs: Additional keyword arguments passed to Stack
        """
        super().__init__(scope, construct_id, **kwargs)
        
        # Store configuration parameters
        self.consumer_account_id = consumer_account_id
        self.external_id = external_id
        self.db_instance_class = db_instance_class
        self.db_allocated_storage = db_allocated_storage
        
        # Create VPC and networking infrastructure
        self.vpc = self._create_vpc()
        
        # Create database secret for secure credential management
        self.db_secret = self._create_database_secret()
        
        # Create RDS database
        self.database = self._create_rds_database()
        
        # Create VPC Lattice components
        self.resource_gateway = self._create_resource_gateway()
        self.service_network = self._create_service_network()
        self.resource_configuration = self._create_resource_configuration()
        
        # Associate resource configuration with service network
        self._associate_resource_configuration()
        
        # Create cross-account IAM role
        self.cross_account_role = self._create_cross_account_role()
        
        # Configure service network authentication policy
        self._configure_auth_policy()
        
        # Create AWS RAM resource share
        self.resource_share = self._create_resource_share()
        
        # Set up CloudWatch monitoring
        self._setup_cloudwatch_monitoring()
        
        # Create outputs for stack references
        self._create_outputs()
        
        # Apply tags to all resources
        self._apply_tags()

    def _create_vpc(self) -> ec2.Vpc:
        """
        Create VPC with public and private subnets across multiple AZs.
        
        Returns:
            ec2.Vpc: The created VPC
        """
        vpc = ec2.Vpc(
            self, "DatabaseOwnerVpc",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=2,
            enable_dns_hostnames=True,
            enable_dns_support=True,
            subnet_configuration=[
                # Public subnets for NAT gateways and internet access
                ec2.SubnetConfiguration(
                    subnet_type=ec2.SubnetType.PUBLIC,
                    name="Public",
                    cidr_mask=24,
                ),
                # Private subnets for RDS database
                ec2.SubnetConfiguration(
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                    name="Database",
                    cidr_mask=24,
                ),
                # Isolated subnet for VPC Lattice resource gateway
                ec2.SubnetConfiguration(
                    subnet_type=ec2.SubnetType.PRIVATE_ISOLATED,
                    name="ResourceGateway",
                    cidr_mask=28,  # /28 required for resource gateway
                ),
            ],
        )
        
        # Add VPC flow logs for security monitoring
        vpc.add_flow_log(
            "VpcFlowLogs",
            destination=ec2.FlowLogDestination.to_cloud_watch_logs(
                logs.LogGroup(
                    self, "VpcFlowLogsGroup",
                    retention=logs.RetentionDays.ONE_MONTH,
                    removal_policy=RemovalPolicy.DESTROY,
                )
            ),
            traffic_type=ec2.FlowLogTrafficType.ALL,
        )
        
        return vpc

    def _create_database_secret(self) -> secretsmanager.Secret:
        """
        Create a Secrets Manager secret for database credentials.
        
        Returns:
            secretsmanager.Secret: The created secret
        """
        return secretsmanager.Secret(
            self, "DatabaseSecret",
            description="Credentials for the shared RDS database",
            generate_secret_string=secretsmanager.SecretStringGenerator(
                secret_string_template='{"username": "admin"}',
                generate_string_key="password",
                exclude_characters='"@/\\',
                password_length=32,
                require_each_included_type=True,
            ),
            removal_policy=RemovalPolicy.DESTROY,
        )

    def _create_rds_database(self) -> rds.DatabaseInstance:
        """
        Create RDS MySQL database with security best practices.
        
        Returns:
            rds.DatabaseInstance: The created database instance
        """
        # Create security group for RDS
        db_security_group = ec2.SecurityGroup(
            self, "DatabaseSecurityGroup",
            vpc=self.vpc,
            description="Security group for shared RDS database",
            allow_all_outbound=False,
        )
        
        # Allow inbound MySQL traffic from VPC CIDR
        db_security_group.add_ingress_rule(
            peer=ec2.Peer.ipv4(self.vpc.vpc_cidr_block),
            connection=ec2.Port.tcp(3306),
            description="Allow MySQL access from VPC",
        )
        
        # Create subnet group for RDS spanning multiple AZs
        subnet_group = rds.SubnetGroup(
            self, "DatabaseSubnetGroup",
            description="Subnet group for shared database",
            vpc=self.vpc,
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS
            ),
        )
        
        # Create the RDS database instance
        database = rds.DatabaseInstance(
            self, "SharedDatabase",
            engine=rds.DatabaseInstanceEngine.mysql(
                version=rds.MysqlEngineVersion.VER_8_0
            ),
            instance_type=ec2.InstanceType(self.db_instance_class),
            credentials=rds.Credentials.from_secret(self.db_secret),
            allocated_storage=self.db_allocated_storage,
            storage_type=rds.StorageType.GP3,
            storage_encrypted=True,
            vpc=self.vpc,
            subnet_group=subnet_group,
            security_groups=[db_security_group],
            backup_retention=Duration.days(7),
            delete_automated_backups=True,
            deletion_protection=False,  # Set to True for production
            removal_policy=RemovalPolicy.DESTROY,
            enable_performance_insights=True,
            performance_insight_retention=rds.PerformanceInsightRetention.DEFAULT,
        )
        
        return database

    def _create_resource_gateway(self) -> vpclattice.CfnResourceGateway:
        """
        Create VPC Lattice resource gateway for database access.
        
        Returns:
            vpclattice.CfnResourceGateway: The created resource gateway
        """
        # Create security group for resource gateway
        gateway_security_group = ec2.SecurityGroup(
            self, "ResourceGatewaySecurityGroup",
            vpc=self.vpc,
            description="Security group for VPC Lattice resource gateway",
            allow_all_outbound=True,
        )
        
        # Allow all traffic within VPC for resource gateway
        gateway_security_group.add_ingress_rule(
            peer=ec2.Peer.ipv4(self.vpc.vpc_cidr_block),
            connection=ec2.Port.all_traffic(),
            description="Allow all traffic from VPC",
        )
        
        # Get isolated subnet for resource gateway
        gateway_subnets = self.vpc.select_subnets(
            subnet_type=ec2.SubnetType.PRIVATE_ISOLATED
        )
        
        # Create the resource gateway
        resource_gateway = vpclattice.CfnResourceGateway(
            self, "ResourceGateway",
            name="rds-gateway",
            vpc_identifier=self.vpc.vpc_id,
            subnet_ids=[gateway_subnets.subnet_ids[0]],  # Use first isolated subnet
            security_group_ids=[gateway_security_group.security_group_id],
            tags=[
                cdk.CfnTag(key="Name", value="RDS Resource Gateway"),
                cdk.CfnTag(key="Purpose", value="Cross-account database sharing"),
            ],
        )
        
        return resource_gateway

    def _create_service_network(self) -> vpclattice.CfnServiceNetwork:
        """
        Create VPC Lattice service network with IAM authentication.
        
        Returns:
            vpclattice.CfnServiceNetwork: The created service network
        """
        # Create the service network
        service_network = vpclattice.CfnServiceNetwork(
            self, "ServiceNetwork",
            name="database-sharing-network",
            auth_type="AWS_IAM",
            tags=[
                cdk.CfnTag(key="Name", value="Database Sharing Service Network"),
                cdk.CfnTag(key="Purpose", value="Cross-account database governance"),
            ],
        )
        
        # Associate VPC with service network
        vpclattice.CfnServiceNetworkVpcAssociation(
            self, "ServiceNetworkVpcAssociation",
            service_network_identifier=service_network.ref,
            vpc_identifier=self.vpc.vpc_id,
            tags=[
                cdk.CfnTag(key="Name", value="Database VPC Association"),
            ],
        )
        
        return service_network

    def _create_resource_configuration(self) -> vpclattice.CfnResourceConfiguration:
        """
        Create VPC Lattice resource configuration for the RDS database.
        
        Returns:
            vpclattice.CfnResourceConfiguration: The created resource configuration
        """
        resource_configuration = vpclattice.CfnResourceConfiguration(
            self, "ResourceConfiguration",
            name="rds-resource-config",
            type="SINGLE",
            resource_gateway_identifier=self.resource_gateway.ref,
            resource_configuration_definition={
                "ipResource": {
                    "ipAddress": self.database.instance_endpoint.hostname
                }
            },
            protocol="TCP",
            port_ranges=["3306"],
            allow_association_to_shareable_service_network=True,
            tags=[
                cdk.CfnTag(key="Name", value="RDS Resource Configuration"),
                cdk.CfnTag(key="Database", value=self.database.instance_identifier),
            ],
        )
        
        # Add dependency to ensure database is created first
        resource_configuration.add_dependency(self.database.node.default_child)
        
        return resource_configuration

    def _associate_resource_configuration(self) -> None:
        """Associate the resource configuration with the service network."""
        vpclattice.CfnResourceConfigurationAssociation(
            self, "ResourceConfigurationAssociation",
            resource_configuration_identifier=self.resource_configuration.ref,
            service_network_identifier=self.service_network.ref,
            tags=[
                cdk.CfnTag(key="Name", value="Database Resource Association"),
            ],
        )

    def _create_cross_account_role(self) -> iam.Role:
        """
        Create IAM role for cross-account database access.
        
        Returns:
            iam.Role: The created cross-account role
        """
        # Create trust policy for cross-account access
        trust_policy = {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": {
                        "AWS": f"arn:aws:iam::{self.consumer_account_id}:root"
                    },
                    "Action": "sts:AssumeRole",
                    "Condition": {
                        "StringEquals": {
                            "sts:ExternalId": self.external_id
                        }
                    }
                }
            ]
        }
        
        # Create the cross-account role
        role = iam.Role(
            self, "DatabaseAccessRole",
            assumed_by=iam.AccountPrincipal(self.consumer_account_id),
            role_name="DatabaseAccessRole",
            description="Cross-account role for VPC Lattice database access",
            external_ids=[self.external_id],
            inline_policies={
                "DatabaseAccessPolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=["vpc-lattice:Invoke"],
                            resources=["*"],
                        )
                    ]
                )
            },
        )
        
        return role

    def _configure_auth_policy(self) -> None:
        """Configure authentication policy for the service network."""
        auth_policy = {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": {
                        "AWS": self.cross_account_role.role_arn
                    },
                    "Action": "vpc-lattice:Invoke",
                    "Resource": "*"
                }
            ]
        }
        
        # Apply auth policy to service network
        vpclattice.CfnAuthPolicy(
            self, "ServiceNetworkAuthPolicy",
            resource_identifier=self.service_network.ref,
            policy=auth_policy,
        )

    def _create_resource_share(self) -> ram.CfnResourceShare:
        """
        Create AWS RAM resource share for cross-account sharing.
        
        Returns:
            ram.CfnResourceShare: The created resource share
        """
        # Construct resource ARN for the resource configuration
        resource_arn = (
            f"arn:aws:vpc-lattice:{self.region}:{self.account}:"
            f"resourceconfiguration/{self.resource_configuration.ref}"
        )
        
        resource_share = ram.CfnResourceShare(
            self, "DatabaseResourceShare",
            name="DatabaseResourceShare",
            principals=[self.consumer_account_id],
            resource_arns=[resource_arn],
            tags=[
                cdk.CfnTag(key="Name", value="Database Resource Share"),
                cdk.CfnTag(key="Purpose", value="Cross-account database sharing"),
            ],
        )
        
        return resource_share

    def _setup_cloudwatch_monitoring(self) -> None:
        """Set up comprehensive CloudWatch monitoring and dashboards."""
        # Create log group for VPC Lattice
        log_group = logs.LogGroup(
            self, "VpcLatticeLogGroup",
            log_group_name=f"/aws/vpc-lattice/servicenetwork/{self.service_network.ref}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        # Create CloudWatch dashboard
        dashboard = cloudwatch.Dashboard(
            self, "DatabaseSharingDashboard",
            dashboard_name="DatabaseSharingMonitoring",
        )
        
        # Add VPC Lattice metrics widget
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Database Access Metrics",
                width=12,
                height=6,
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/VpcLattice",
                        metric_name="RequestCount",
                        dimensions_map={
                            "ServiceNetwork": self.service_network.ref
                        },
                        statistic="Sum",
                        period=Duration.minutes(5),
                    ),
                    cloudwatch.Metric(
                        namespace="AWS/VpcLattice",
                        metric_name="ResponseTime",
                        dimensions_map={
                            "ServiceNetwork": self.service_network.ref
                        },
                        statistic="Average",
                        period=Duration.minutes(5),
                    ),
                    cloudwatch.Metric(
                        namespace="AWS/VpcLattice",
                        metric_name="ActiveConnectionCount",
                        dimensions_map={
                            "ServiceNetwork": self.service_network.ref
                        },
                        statistic="Average",
                        period=Duration.minutes(5),
                    ),
                ],
            )
        )
        
        # Add RDS metrics widget
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="RDS Database Metrics",
                width=12,
                height=6,
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/RDS",
                        metric_name="DatabaseConnections",
                        dimensions_map={
                            "DBInstanceIdentifier": self.database.instance_identifier
                        },
                        statistic="Average",
                        period=Duration.minutes(5),
                    ),
                    cloudwatch.Metric(
                        namespace="AWS/RDS",
                        metric_name="CPUUtilization",
                        dimensions_map={
                            "DBInstanceIdentifier": self.database.instance_identifier
                        },
                        statistic="Average",
                        period=Duration.minutes(5),
                    ),
                ],
            )
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource references."""
        CfnOutput(
            self, "VpcId",
            description="VPC ID for the database owner account",
            value=self.vpc.vpc_id,
            export_name=f"{self.stack_name}-VpcId",
        )
        
        CfnOutput(
            self, "DatabaseEndpoint",
            description="RDS database endpoint",
            value=self.database.instance_endpoint.hostname,
            export_name=f"{self.stack_name}-DatabaseEndpoint",
        )
        
        CfnOutput(
            self, "DatabasePort",
            description="RDS database port",
            value=str(self.database.instance_endpoint.port),
            export_name=f"{self.stack_name}-DatabasePort",
        )
        
        CfnOutput(
            self, "ResourceGatewayId",
            description="VPC Lattice resource gateway ID",
            value=self.resource_gateway.ref,
            export_name=f"{self.stack_name}-ResourceGatewayId",
        )
        
        CfnOutput(
            self, "ServiceNetworkId",
            description="VPC Lattice service network ID",
            value=self.service_network.ref,
            export_name=f"{self.stack_name}-ServiceNetworkId",
        )
        
        CfnOutput(
            self, "ResourceConfigurationId",
            description="VPC Lattice resource configuration ID",
            value=self.resource_configuration.ref,
            export_name=f"{self.stack_name}-ResourceConfigurationId",
        )
        
        CfnOutput(
            self, "CrossAccountRoleArn",
            description="ARN of the cross-account access role",
            value=self.cross_account_role.role_arn,
            export_name=f"{self.stack_name}-CrossAccountRoleArn",
        )
        
        CfnOutput(
            self, "ResourceShareArn",
            description="ARN of the AWS RAM resource share",
            value=self.resource_share.ref,
            export_name=f"{self.stack_name}-ResourceShareArn",
        )
        
        CfnOutput(
            self, "DatabaseSecretArn",
            description="ARN of the database credentials secret",
            value=self.db_secret.secret_arn,
            export_name=f"{self.stack_name}-DatabaseSecretArn",
        )

    def _apply_tags(self) -> None:
        """Apply consistent tags to all resources in the stack."""
        Tags.of(self).add("Project", "CrossAccountDatabaseSharing")
        Tags.of(self).add("Environment", "Demo")
        Tags.of(self).add("ManagedBy", "CDK")
        Tags.of(self).add("Recipe", "cross-account-database-sharing-lattice-rds")


def main() -> None:
    """Main application entry point."""
    app = App()
    
    # Get configuration from CDK context or environment variables
    consumer_account_id = app.node.try_get_context("consumer_account_id")
    if not consumer_account_id:
        raise ValueError(
            "Consumer account ID must be provided via CDK context: "
            "cdk deploy -c consumer_account_id=123456789012"
        )
    
    # Optional configuration parameters
    external_id = app.node.try_get_context("external_id") or "unique-external-id-12345"
    db_instance_class = app.node.try_get_context("db_instance_class") or "db.t3.micro"
    db_allocated_storage = int(app.node.try_get_context("db_allocated_storage") or 20)
    
    # Environment configuration
    env = Environment(
        account=app.node.try_get_context("aws_account_id"),
        region=app.node.try_get_context("aws_region") or "us-east-1",
    )
    
    # Create the main stack
    DatabaseSharingStack(
        app, "DatabaseSharingStack",
        consumer_account_id=consumer_account_id,
        external_id=external_id,
        db_instance_class=db_instance_class,
        db_allocated_storage=db_allocated_storage,
        env=env,
        description="Cross-Account Database Sharing with VPC Lattice and RDS",
    )
    
    app.synth()


if __name__ == "__main__":
    main()