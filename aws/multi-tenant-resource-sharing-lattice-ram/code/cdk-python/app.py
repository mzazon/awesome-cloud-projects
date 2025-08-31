#!/usr/bin/env python3
"""
CDK Python application for Multi-Tenant Resource Sharing with VPC Lattice and AWS RAM.

This application deploys a comprehensive multi-tenant architecture using:
- Amazon VPC Lattice for application networking and service discovery
- AWS Resource Access Manager (RAM) for cross-account resource sharing
- Amazon RDS for shared database resources
- IAM roles with team-based tags for fine-grained access control
- CloudTrail for comprehensive audit logging

The solution enables secure resource sharing across AWS accounts while maintaining
strict access controls and audit capabilities.
"""

import aws_cdk as cdk
import aws_cdk.aws_vpclattice as lattice
import aws_cdk.aws_ram as ram
import aws_cdk.aws_rds as rds
import aws_cdk.aws_ec2 as ec2
import aws_cdk.aws_iam as iam
import aws_cdk.aws_cloudtrail as cloudtrail
import aws_cdk.aws_s3 as s3
import aws_cdk.aws_logs as logs
from constructs import Construct
from typing import Dict, List, Optional
import json


class MultiTenantLatticeRAMStack(cdk.Stack):
    """
    CDK Stack implementing multi-tenant resource sharing with VPC Lattice and AWS RAM.
    
    This stack creates:
    1. VPC Lattice Service Network with IAM authentication
    2. RDS database instance as a shared resource  
    3. VPC Lattice Resource Configuration for the database
    4. AWS RAM resource share for cross-account access
    5. IAM roles with team-based tags for multi-tenant access
    6. CloudTrail for comprehensive audit logging
    7. Authentication policies for fine-grained access control
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        vpc: Optional[ec2.IVpc] = None,
        enable_cross_account_sharing: bool = True,
        shared_principals: Optional[List[str]] = None,
        **kwargs
    ) -> None:
        """
        Initialize the Multi-Tenant Lattice RAM Stack.
        
        Args:
            scope: CDK scope (usually the App)
            construct_id: Unique identifier for this stack
            vpc: Existing VPC to use (creates new one if not provided)
            enable_cross_account_sharing: Whether to enable cross-account sharing via RAM
            shared_principals: List of AWS account IDs or organizational units to share with
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)

        # Store configuration
        self.enable_cross_account_sharing = enable_cross_account_sharing
        self.shared_principals = shared_principals or []

        # Create or use existing VPC
        self.vpc = vpc or self._create_vpc()
        
        # Create core networking and security components
        self.service_network = self._create_service_network()
        self.vpc_association = self._create_vpc_association()
        
        # Create shared database resource
        self.database_security_group = self._create_database_security_group()
        self.db_subnet_group = self._create_db_subnet_group()
        self.database = self._create_database()
        
        # Create VPC Lattice resource configuration
        self.resource_configuration = self._create_resource_configuration()
        self.resource_association = self._create_resource_association()
        
        # Create IAM roles for different tenant teams
        self.team_roles = self._create_team_roles()
        
        # Create authentication policies
        self._create_auth_policy()
        
        # Set up AWS RAM resource sharing (if enabled)
        if self.enable_cross_account_sharing:
            self.resource_share = self._create_ram_resource_share()
        
        # Set up CloudTrail for audit logging
        self.audit_trail = self._create_cloudtrail()
        
        # Create stack outputs
        self._create_outputs()

    def _create_vpc(self) -> ec2.Vpc:
        """
        Create a VPC with public and private subnets across multiple AZs.
        
        Returns:
            ec2.Vpc: The created VPC instance
        """
        return ec2.Vpc(
            self,
            "MultiTenantVpc",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=3,
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="Public",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24
                ),
                ec2.SubnetConfiguration(
                    name="Private",
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                    cidr_mask=24
                ),
                ec2.SubnetConfiguration(
                    name="Database",
                    subnet_type=ec2.SubnetType.PRIVATE_ISOLATED,
                    cidr_mask=28
                )
            ],
            enable_dns_hostnames=True,
            enable_dns_support=True,
        )

    def _create_service_network(self) -> lattice.CfnServiceNetwork:
        """
        Create VPC Lattice Service Network with IAM authentication.
        
        Returns:
            lattice.CfnServiceNetwork: The created service network
        """
        return lattice.CfnServiceNetwork(
            self,
            "MultiTenantServiceNetwork",
            name=f"multitenant-network-{cdk.Aws.STACK_NAME}",
            auth_type="AWS_IAM"
        )

    def _create_vpc_association(self) -> lattice.CfnServiceNetworkVpcAssociation:
        """
        Associate the VPC with the VPC Lattice Service Network.
        
        Returns:
            lattice.CfnServiceNetworkVpcAssociation: The VPC association
        """
        return lattice.CfnServiceNetworkVpcAssociation(
            self,
            "VpcAssociation",
            service_network_identifier=self.service_network.attr_arn,
            vpc_identifier=self.vpc.vpc_id
        )

    def _create_database_security_group(self) -> ec2.SecurityGroup:
        """
        Create security group for the RDS database with least privilege access.
        
        Returns:
            ec2.SecurityGroup: The database security group
        """
        security_group = ec2.SecurityGroup(
            self,
            "DatabaseSecurityGroup",
            vpc=self.vpc,
            description="Security group for shared database with VPC Lattice access",
            allow_all_outbound=False
        )

        # Allow MySQL access from within the VPC
        security_group.add_ingress_rule(
            peer=ec2.Peer.ipv4(self.vpc.vpc_cidr_block),
            connection=ec2.Port.tcp(3306),
            description="MySQL access from VPC"
        )

        return security_group

    def _create_db_subnet_group(self) -> rds.SubnetGroup:
        """
        Create DB subnet group for multi-AZ deployment.
        
        Returns:
            rds.SubnetGroup: The database subnet group
        """
        return rds.SubnetGroup(
            self,
            "DatabaseSubnetGroup",
            vpc=self.vpc,
            description="Subnet group for shared database",
            subnet_group_name=f"shared-db-subnet-{cdk.Aws.STACK_NAME}",
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PRIVATE_ISOLATED
            )
        )

    def _create_database(self) -> rds.DatabaseInstance:
        """
        Create RDS MySQL database instance with encryption and security best practices.
        
        Returns:
            rds.DatabaseInstance: The created database instance
        """
        return rds.DatabaseInstance(
            self,
            "SharedDatabase",
            instance_identifier=f"shared-db-{cdk.Aws.STACK_NAME}",
            engine=rds.DatabaseInstanceEngine.mysql(
                version=rds.MysqlEngineVersion.VER_8_0
            ),
            instance_type=ec2.InstanceType.of(
                ec2.InstanceClass.BURSTABLE3,
                ec2.InstanceSize.MICRO
            ),
            vpc=self.vpc,
            subnet_group=self.db_subnet_group,
            security_groups=[self.database_security_group],
            credentials=rds.Credentials.from_generated_secret(
                username="admin",
                secret_name=f"shared-db-credentials-{cdk.Aws.STACK_NAME}"
            ),
            allocated_storage=20,
            storage_encrypted=True,
            backup_retention=cdk.Duration.days(7),
            publicly_accessible=False,
            deletion_protection=False,  # Set to True for production
            remove_from_secret_manager_on_destroy=True,
            cloudwatch_logs_exports=["error", "general", "slowquery"],
            monitoring_interval=cdk.Duration.seconds(60),
            enable_performance_insights=True,
            performance_insight_retention=rds.PerformanceInsightRetention.DEFAULT,
        )

    def _create_resource_configuration(self) -> lattice.CfnResourceConfiguration:
        """
        Create VPC Lattice Resource Configuration for the RDS database.
        
        Returns:
            lattice.CfnResourceConfiguration: The resource configuration
        """
        return lattice.CfnResourceConfiguration(
            self,
            "DatabaseResourceConfig",
            name=f"shared-database-{cdk.Aws.STACK_NAME}",
            type="SINGLE",
            resource_gateway_identifier=self.vpc.vpc_id,
            resource_configuration_definition={
                "ipResource": {
                    "ipAddress": self.database.instance_endpoint.hostname
                }
            },
            port_ranges=["3306"],
            protocol="TCP",
            allow_association_to_shareable_service_network=True
        )

    def _create_resource_association(self) -> lattice.CfnResourceConfigurationAssociation:
        """
        Associate the resource configuration with the service network.
        
        Returns:
            lattice.CfnResourceConfigurationAssociation: The resource association
        """
        return lattice.CfnResourceConfigurationAssociation(
            self,
            "ResourceAssociation",
            resource_configuration_identifier=self.resource_configuration.attr_arn,
            service_network_identifier=self.service_network.attr_arn
        )

    def _create_team_roles(self) -> Dict[str, iam.Role]:
        """
        Create IAM roles for different tenant teams with appropriate tags.
        
        Returns:
            Dict[str, iam.Role]: Dictionary of team roles
        """
        teams = ["TeamA", "TeamB", "TeamC"]
        roles = {}

        for team in teams:
            role = iam.Role(
                self,
                f"{team}DatabaseAccessRole",
                role_name=f"{team}-DatabaseAccess-{cdk.Aws.STACK_NAME}",
                assumed_by=iam.AccountRootPrincipal(),
                description=f"IAM role for {team} database access",
                external_ids=[f"{team}-Access"],
                managed_policies=[
                    iam.ManagedPolicy.from_aws_managed_policy_name(
                        "VPCLatticeServicesInvokeAccess"
                    )
                ]
            )

            # Add team-specific tags required by auth policy
            cdk.Tags.of(role).add("Team", team)
            cdk.Tags.of(role).add("Purpose", "DatabaseAccess")
            cdk.Tags.of(role).add("Environment", "MultiTenant")

            roles[team] = role

        return roles

    def _create_auth_policy(self) -> None:
        """
        Create authentication policy for VPC Lattice service network with team-based access control.
        """
        auth_policy = {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": "*",
                    "Action": "vpc-lattice-svcs:Invoke",
                    "Resource": "*",
                    "Condition": {
                        "StringEquals": {
                            "aws:PrincipalTag/Team": ["TeamA", "TeamB", "TeamC"]
                        },
                        "DateGreaterThan": {
                            "aws:CurrentTime": "2025-01-01T00:00:00Z"
                        },
                        "IpAddress": {
                            "aws:SourceIp": ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
                        }
                    }
                },
                {
                    "Effect": "Allow",
                    "Principal": {
                        "AWS": f"arn:aws:iam::{cdk.Aws.ACCOUNT_ID}:root"
                    },
                    "Action": "vpc-lattice-svcs:Invoke",
                    "Resource": "*"
                }
            ]
        }

        lattice.CfnAuthPolicy(
            self,
            "ServiceNetworkAuthPolicy",
            resource_identifier=self.service_network.attr_arn,
            policy=auth_policy
        )

    def _create_ram_resource_share(self) -> ram.CfnResourceShare:
        """
        Create AWS RAM resource share for cross-account sharing.
        
        Returns:
            ram.CfnResourceShare: The created resource share
        """
        principals = self.shared_principals if self.shared_principals else [cdk.Aws.ACCOUNT_ID]
        
        return ram.CfnResourceShare(
            self,
            "ServiceNetworkShare",
            name=f"database-share-{cdk.Aws.STACK_NAME}",
            resource_arns=[self.service_network.attr_arn],
            principals=principals,
            allow_external_principals=True,
            tags=[
                cdk.CfnTag(key="Purpose", value="MultiTenantSharing"),
                cdk.CfnTag(key="Environment", value="Production")
            ]
        )

    def _create_cloudtrail(self) -> cloudtrail.Trail:
        """
        Create CloudTrail for comprehensive audit logging.
        
        Returns:
            cloudtrail.Trail: The created CloudTrail
        """
        # Create S3 bucket for CloudTrail logs
        trail_bucket = s3.Bucket(
            self,
            "CloudTrailBucket",
            bucket_name=f"lattice-audit-logs-{cdk.Aws.ACCOUNT_ID}-{cdk.Aws.REGION}",
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=cdk.RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    enabled=True,
                    expiration=cdk.Duration.days(90),
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=cdk.Duration.days(30)
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=cdk.Duration.days(60)
                        )
                    ]
                )
            ]
        )

        # Create CloudWatch log group for CloudTrail
        log_group = logs.LogGroup(
            self,
            "CloudTrailLogGroup",
            log_group_name=f"/aws/cloudtrail/vpc-lattice-audit-{cdk.Aws.STACK_NAME}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=cdk.RemovalPolicy.DESTROY
        )

        # Create CloudTrail
        trail = cloudtrail.Trail(
            self,
            "VPCLatticeAuditTrail",
            trail_name=f"VPCLatticeAuditTrail-{cdk.Aws.STACK_NAME}",
            bucket=trail_bucket,
            cloud_watch_log_group=log_group,
            include_global_service_events=True,
            is_multi_region_trail=True,
            enable_file_validation=True,
            send_to_cloud_watch_logs=True
        )

        # Add data events for VPC Lattice operations
        trail.add_event_selector(
            read_write_type=cloudtrail.ReadWriteType.ALL,
            include_management_events=True,
            data_resources=[
                cloudtrail.DataResource(
                    type="AWS::VpcLattice::Service",
                    values=["*"]
                ),
                cloudtrail.DataResource(
                    type="AWS::VpcLattice::ServiceNetwork",
                    values=["*"]
                )
            ]
        )

        return trail

    def _create_outputs(self) -> None:
        """Create CloudFormation stack outputs for key resources."""
        
        cdk.CfnOutput(
            self,
            "ServiceNetworkArn",
            value=self.service_network.attr_arn,
            description="ARN of the VPC Lattice Service Network",
            export_name=f"{cdk.Aws.STACK_NAME}-ServiceNetworkArn"
        )

        cdk.CfnOutput(
            self,
            "ServiceNetworkId",
            value=self.service_network.attr_id,
            description="ID of the VPC Lattice Service Network",
            export_name=f"{cdk.Aws.STACK_NAME}-ServiceNetworkId"
        )

        cdk.CfnOutput(
            self,
            "DatabaseEndpoint",
            value=self.database.instance_endpoint.hostname,
            description="RDS database endpoint hostname",
            export_name=f"{cdk.Aws.STACK_NAME}-DatabaseEndpoint"
        )

        cdk.CfnOutput(
            self,
            "DatabasePort",
            value=str(self.database.instance_endpoint.port),
            description="RDS database port",
            export_name=f"{cdk.Aws.STACK_NAME}-DatabasePort"
        )

        cdk.CfnOutput(
            self,
            "ResourceConfigurationArn",
            value=self.resource_configuration.attr_arn,
            description="ARN of the VPC Lattice Resource Configuration",
            export_name=f"{cdk.Aws.STACK_NAME}-ResourceConfigArn"
        )

        cdk.CfnOutput(
            self,
            "VpcId",
            value=self.vpc.vpc_id,
            description="ID of the VPC",
            export_name=f"{cdk.Aws.STACK_NAME}-VpcId"
        )

        # Output team role ARNs
        for team, role in self.team_roles.items():
            cdk.CfnOutput(
                self,
                f"{team}RoleArn",
                value=role.role_arn,
                description=f"ARN of the {team} IAM role",
                export_name=f"{cdk.Aws.STACK_NAME}-{team}RoleArn"
            )

        if hasattr(self, 'resource_share'):
            cdk.CfnOutput(
                self,
                "ResourceShareArn",
                value=self.resource_share.attr_arn,
                description="ARN of the AWS RAM resource share",
                export_name=f"{cdk.Aws.STACK_NAME}-ResourceShareArn"
            )

        cdk.CfnOutput(
            self,
            "CloudTrailArn",
            value=self.audit_trail.trail_arn,
            description="ARN of the CloudTrail for audit logging",
            export_name=f"{cdk.Aws.STACK_NAME}-CloudTrailArn"
        )


class MultiTenantLatticeRAMApp(cdk.App):
    """
    CDK Application for Multi-Tenant Resource Sharing with VPC Lattice and AWS RAM.
    """

    def __init__(self, **kwargs):
        super().__init__(**kwargs)

        # Get configuration from context or environment variables
        env = cdk.Environment(
            account=self.node.try_get_context("account") or cdk.Aws.ACCOUNT_ID,
            region=self.node.try_get_context("region") or cdk.Aws.REGION
        )

        # Get shared principals from context (for cross-account sharing)
        shared_principals = self.node.try_get_context("sharedPrincipals")
        enable_cross_account_sharing = self.node.try_get_context("enableCrossAccountSharing") or False

        # Create the main stack
        MultiTenantLatticeRAMStack(
            self,
            "MultiTenantLatticeRAMStack",
            env=env,
            shared_principals=shared_principals,
            enable_cross_account_sharing=enable_cross_account_sharing,
            description="Multi-Tenant Resource Sharing with VPC Lattice and AWS RAM"
        )


# Application entry point
if __name__ == "__main__":
    app = MultiTenantLatticeRAMApp()
    app.synth()