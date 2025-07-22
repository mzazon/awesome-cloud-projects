"""
Networking Stack for Neptune Graph Database

This stack creates the VPC infrastructure required for Neptune deployment:
- VPC with public and private subnets across multiple AZs
- Internet Gateway and NAT Gateway for connectivity
- Security groups for Neptune and EC2 access
- Neptune subnet group spanning multiple AZs
"""

from aws_cdk import (
    Stack,
    aws_ec2 as ec2,
    aws_neptune as neptune,
    CfnOutput,
)
from constructs import Construct
from typing import Optional


class NetworkingStack(Stack):
    """
    Creates VPC and networking infrastructure for Neptune cluster.
    
    This stack provides the foundation for secure Neptune deployment
    with proper network isolation and multi-AZ availability.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Create VPC with public and private subnets across multiple AZs
        self.vpc = ec2.Vpc(
            self, "NeptuneVPC",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=3,  # Use 3 AZs for high availability
            subnet_configuration=[
                # Public subnet for EC2 client instance
                ec2.SubnetConfiguration(
                    name="PublicSubnet",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24,
                ),
                # Private subnets for Neptune cluster
                ec2.SubnetConfiguration(
                    name="PrivateSubnet",
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                    cidr_mask=24,
                ),
            ],
            enable_dns_hostnames=True,
            enable_dns_support=True,
        )

        # Create security group for Neptune cluster
        self.neptune_security_group = ec2.SecurityGroup(
            self, "NeptuneSecurityGroup",
            vpc=self.vpc,
            description="Security group for Neptune cluster",
            allow_all_outbound=False,
        )

        # Allow Neptune port access from within the security group (self-referencing)
        self.neptune_security_group.add_ingress_rule(
            peer=self.neptune_security_group,
            connection=ec2.Port.tcp(8182),
            description="Allow Neptune Gremlin access from within security group"
        )

        # Allow HTTPS outbound for Neptune management
        self.neptune_security_group.add_egress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(443),
            description="Allow HTTPS outbound for Neptune management"
        )

        # Create Neptune subnet group spanning multiple AZs
        private_subnet_ids = [subnet.subnet_id for subnet in self.vpc.private_subnets]
        
        self.subnet_group = neptune.CfnDBSubnetGroup(
            self, "NeptuneSubnetGroup",
            db_subnet_group_description="Subnet group for Neptune cluster",
            subnet_ids=private_subnet_ids,
            db_subnet_group_name="neptune-subnet-group",
        )

        # Store public subnet for EC2 instance
        self.public_subnet = self.vpc.public_subnets[0]

        # Outputs for other stacks
        CfnOutput(
            self, "VpcId",
            value=self.vpc.vpc_id,
            description="VPC ID for Neptune cluster",
            export_name="NeptuneVpcId"
        )

        CfnOutput(
            self, "NeptuneSecurityGroupId",
            value=self.neptune_security_group.security_group_id,
            description="Security group ID for Neptune cluster",
            export_name="NeptuneSecurityGroupId"
        )

        CfnOutput(
            self, "SubnetGroupName",
            value=self.subnet_group.db_subnet_group_name,
            description="Neptune subnet group name",
            export_name="NeptuneSubnetGroupName"
        )

        CfnOutput(
            self, "PublicSubnetId",
            value=self.public_subnet.subnet_id,
            description="Public subnet ID for EC2 instance",
            export_name="PublicSubnetId"
        )