#!/usr/bin/env python3
"""
AWS CDK application for Hybrid Identity Management with AWS Directory Service.

This application creates a complete hybrid identity management solution using:
- AWS Managed Microsoft AD
- Amazon WorkSpaces integration
- Amazon RDS SQL Server with Windows Authentication
- VPC infrastructure with proper networking
- Security groups and IAM roles

Author: AWS CDK Generator
Version: 1.0
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Environment,
    Stack,
    StackProps,
    Tags,
    CfnOutput,
    Duration,
    RemovalPolicy
)
from aws_cdk import aws_ec2 as ec2
from aws_cdk import aws_directoryservice as ds
from aws_cdk import aws_rds as rds
from aws_cdk import aws_workspaces as workspaces
from aws_cdk import aws_iam as iam
from aws_cdk import aws_secretsmanager as secretsmanager
from constructs import Construct


class HybridIdentityStack(Stack):
    """
    Stack for Hybrid Identity Management infrastructure using AWS Directory Service.
    
    This stack creates:
    - VPC with public and private subnets
    - AWS Managed Microsoft AD
    - Security groups for directory and services
    - IAM role for RDS Directory Service integration
    - RDS SQL Server instance with Windows Authentication
    - WorkSpaces directory registration
    - CloudFormation outputs for verification
    """

    def __init__(
        self, 
        scope: Construct, 
        construct_id: str, 
        directory_name: str = None,
        directory_password: str = None,
        **kwargs: Any
    ) -> None:
        """
        Initialize the Hybrid Identity Stack.
        
        Args:
            scope: CDK construct scope
            construct_id: Unique identifier for this stack
            directory_name: Name for the managed directory (optional)
            directory_password: Password for directory admin (optional)
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        unique_suffix = self.node.addr[-8:].lower()
        
        # Set default values if not provided
        self.directory_name = directory_name or f"corp-hybrid-ad-{unique_suffix}"
        self.directory_password = directory_password or "TempPassword123!"

        # Create VPC infrastructure
        self._create_vpc()
        
        # Create security groups
        self._create_security_groups()
        
        # Create directory service password in Secrets Manager
        self._create_directory_secret()
        
        # Create AWS Managed Microsoft AD
        self._create_managed_directory()
        
        # Create IAM role for RDS integration
        self._create_rds_iam_role()
        
        # Create RDS subnet group
        self._create_rds_subnet_group()
        
        # Create RDS SQL Server instance
        self._create_rds_instance()
        
        # Register directory with WorkSpaces
        self._register_workspaces_directory()
        
        # Create outputs
        self._create_outputs()

    def _create_vpc(self) -> None:
        """Create VPC with public and private subnets for directory services."""
        self.vpc = ec2.Vpc(
            self, "HybridIdentityVPC",
            vpc_name=f"hybrid-identity-vpc-{self.node.addr[-8:].lower()}",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=2,
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                    name="DirectorySubnet",
                    cidr_mask=24
                ),
                ec2.SubnetConfiguration(
                    subnet_type=ec2.SubnetType.PUBLIC,
                    name="PublicSubnet",
                    cidr_mask=24
                )
            ],
            enable_dns_hostnames=True,
            enable_dns_support=True
        )

        # Tag VPC for identification
        Tags.of(self.vpc).add("Purpose", "HybridIdentity")
        Tags.of(self.vpc).add("Component", "Networking")

    def _create_security_groups(self) -> None:
        """Create security groups for directory services and applications."""
        
        # Security group for WorkSpaces
        self.workspaces_sg = ec2.SecurityGroup(
            self, "WorkSpacesSecurityGroup",
            vpc=self.vpc,
            description="Security group for Amazon WorkSpaces",
            security_group_name=f"workspaces-sg-{self.node.addr[-8:].lower()}",
            allow_all_outbound=True
        )

        # Security group for RDS
        self.rds_sg = ec2.SecurityGroup(
            self, "RDSSecurityGroup",
            vpc=self.vpc,
            description="Security group for RDS SQL Server",
            security_group_name=f"rds-sg-{self.node.addr[-8:].lower()}",
            allow_all_outbound=False
        )

        # Allow RDS SQL Server port from WorkSpaces
        self.rds_sg.add_ingress_rule(
            peer=self.workspaces_sg,
            connection=ec2.Port.tcp(1433),
            description="Allow SQL Server access from WorkSpaces"
        )

        # Allow RDS SQL Server port from private subnets
        self.rds_sg.add_ingress_rule(
            peer=ec2.Peer.ipv4(self.vpc.vpc_cidr_block),
            connection=ec2.Port.tcp(1433),
            description="Allow SQL Server access from VPC"
        )

        # Tag security groups
        Tags.of(self.workspaces_sg).add("Purpose", "HybridIdentity")
        Tags.of(self.rds_sg).add("Purpose", "HybridIdentity")

    def _create_directory_secret(self) -> None:
        """Create secret for directory service password."""
        self.directory_secret = secretsmanager.Secret(
            self, "DirectorySecret",
            secret_name=f"hybrid-identity/directory-password-{self.node.addr[-8:].lower()}",
            description="Password for AWS Managed Microsoft AD",
            generate_secret_string=secretsmanager.SecretStringGenerator(
                secret_string_template='{"username":"Admin"}',
                generate_string_key="password",
                exclude_characters='"@/\\'
            ),
            removal_policy=RemovalPolicy.DESTROY
        )

    def _create_managed_directory(self) -> None:
        """Create AWS Managed Microsoft AD directory."""
        
        # Get private subnet IDs for directory placement
        private_subnets = self.vpc.select_subnets(
            subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS
        ).subnet_ids

        if len(private_subnets) < 2:
            raise ValueError("Directory Service requires at least 2 private subnets in different AZs")

        self.directory = ds.CfnMicrosoftAD(
            self, "ManagedDirectory",
            name=f"{self.directory_name}.corp.local",
            password=self.directory_secret.secret_value_from_json("password").unsafe_unwrap(),
            vpc_settings=ds.CfnMicrosoftAD.VpcSettingsProperty(
                vpc_id=self.vpc.vpc_id,
                subnet_ids=private_subnets[:2]  # Use first two subnets
            ),
            edition="Standard",
            short_name=self.directory_name.upper(),
            enable_sso=False,
            create_alias=True
        )

        # Tag directory
        Tags.of(self.directory).add("Purpose", "HybridIdentity")
        Tags.of(self.directory).add("Component", "DirectoryService")

    def _create_rds_iam_role(self) -> None:
        """Create IAM role for RDS Directory Service integration."""
        
        self.rds_directory_role = iam.Role(
            self, "RDSDirectoryServiceRole",
            role_name=f"rds-directoryservice-role-{self.node.addr[-8:].lower()}",
            assumed_by=iam.ServicePrincipal("rds.amazonaws.com"),
            description="IAM role for RDS Directory Service integration",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AmazonRDSDirectoryServiceAccess"
                )
            ]
        )

        # Tag IAM role
        Tags.of(self.rds_directory_role).add("Purpose", "HybridIdentity")

    def _create_rds_subnet_group(self) -> None:
        """Create RDS subnet group using private subnets."""
        
        private_subnets = self.vpc.select_subnets(
            subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS
        )

        self.rds_subnet_group = rds.SubnetGroup(
            self, "RDSSubnetGroup",
            description="Subnet group for hybrid identity RDS instance",
            subnet_group_name=f"hybrid-db-subnet-group-{self.node.addr[-8:].lower()}",
            vpc=self.vpc,
            subnets=private_subnets,
            removal_policy=RemovalPolicy.DESTROY
        )

        # Tag subnet group
        Tags.of(self.rds_subnet_group).add("Purpose", "HybridIdentity")

    def _create_rds_instance(self) -> None:
        """Create RDS SQL Server instance with Directory Service integration."""
        
        # Create parameter group for SQL Server
        parameter_group = rds.ParameterGroup(
            self, "SQLServerParameterGroup",
            engine=rds.DatabaseInstanceEngine.sql_server_se(
                version=rds.SqlServerEngineVersion.VER_15_00_4236_7_V1
            ),
            description="Parameter group for SQL Server with Directory Service"
        )

        # Create RDS instance
        self.rds_instance = rds.DatabaseInstance(
            self, "SQLServerInstance",
            instance_identifier=f"hybrid-sql-{self.node.addr[-8:].lower()}",
            engine=rds.DatabaseInstanceEngine.sql_server_se(
                version=rds.SqlServerEngineVersion.VER_15_00_4236_7_V1
            ),
            instance_type=ec2.InstanceType.of(
                ec2.InstanceClass.BURSTABLE3, 
                ec2.InstanceSize.MEDIUM
            ),
            allocated_storage=200,
            storage_type=rds.StorageType.GP2,
            vpc=self.vpc,
            subnet_group=self.rds_subnet_group,
            security_groups=[self.rds_sg],
            domain=self.directory.ref,
            domain_role=self.rds_directory_role,
            parameter_group=parameter_group,
            backup_retention=Duration.days(7),
            delete_automated_backups=True,
            deletion_protection=False,
            removal_policy=RemovalPolicy.DESTROY,
            auto_minor_version_upgrade=True,
            multi_az=False,
            storage_encrypted=True
        )

        # Add dependency on directory
        self.rds_instance.node.add_dependency(self.directory)

        # Tag RDS instance
        Tags.of(self.rds_instance).add("Purpose", "HybridIdentity")
        Tags.of(self.rds_instance).add("Component", "Database")

    def _register_workspaces_directory(self) -> None:
        """Register directory with Amazon WorkSpaces."""
        
        # Get private subnet IDs for WorkSpaces
        private_subnets = self.vpc.select_subnets(
            subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS
        ).subnet_ids

        self.workspaces_directory = workspaces.CfnWorkspaceDirectory(
            self, "WorkSpacesDirectory",
            directory_id=self.directory.ref,
            subnet_ids=private_subnets[:2],  # Use first two private subnets
            enable_work_docs=True,
            enable_self_service=True,
            enable_internet_access=True,
            default_ou="CN=Computers,DC=corp,DC=local"
        )

        # Add dependency on directory
        self.workspaces_directory.node.add_dependency(self.directory)

        # Tag WorkSpaces directory
        Tags.of(self.workspaces_directory).add("Purpose", "HybridIdentity")

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for verification and integration."""
        
        CfnOutput(
            self, "VPCId",
            description="ID of the VPC created for hybrid identity",
            value=self.vpc.vpc_id,
            export_name=f"{self.stack_name}-VPCId"
        )

        CfnOutput(
            self, "DirectoryId",
            description="ID of the AWS Managed Microsoft AD",
            value=self.directory.ref,
            export_name=f"{self.stack_name}-DirectoryId"
        )

        CfnOutput(
            self, "DirectoryName",
            description="Fully qualified domain name of the directory",
            value=self.directory.name,
            export_name=f"{self.stack_name}-DirectoryName"
        )

        CfnOutput(
            self, "RDSInstanceId",
            description="ID of the RDS SQL Server instance",
            value=self.rds_instance.instance_identifier,
            export_name=f"{self.stack_name}-RDSInstanceId"
        )

        CfnOutput(
            self, "RDSInstanceEndpoint",
            description="Endpoint of the RDS SQL Server instance",
            value=self.rds_instance.instance_endpoint.hostname,
            export_name=f"{self.stack_name}-RDSInstanceEndpoint"
        )

        CfnOutput(
            self, "WorkSpacesDirectoryId",
            description="WorkSpaces directory registration ID",
            value=self.workspaces_directory.directory_id,
            export_name=f"{self.stack_name}-WorkSpacesDirectoryId"
        )

        CfnOutput(
            self, "DirectorySecretArn",
            description="ARN of the secret containing directory password",
            value=self.directory_secret.secret_arn,
            export_name=f"{self.stack_name}-DirectorySecretArn"
        )


class HybridIdentityApp(cdk.App):
    """CDK Application for Hybrid Identity Management."""
    
    def __init__(self) -> None:
        """Initialize the CDK application."""
        super().__init__()
        
        # Get environment configuration
        account = os.environ.get('CDK_DEFAULT_ACCOUNT')
        region = os.environ.get('CDK_DEFAULT_REGION', 'us-east-1')
        
        env = Environment(account=account, region=region)
        
        # Create the main stack
        stack = HybridIdentityStack(
            self, 
            "HybridIdentityStack",
            env=env,
            description="Hybrid Identity Management with AWS Directory Service, WorkSpaces, and RDS",
            stack_name="hybrid-identity-management",
            tags={
                "Project": "HybridIdentityManagement",
                "Environment": "Development",
                "Owner": "CloudTeam",
                "CostCenter": "IT",
                "AutoDelete": "true"
            }
        )


# Create and run the application
app = HybridIdentityApp()
app.synth()