"""
VPC Stack for AWS Proton Infrastructure Automation

This stack creates a standardized VPC infrastructure that provides the
networking foundation for AWS Proton environments and services.
"""

from typing import List, Optional
from aws_cdk import (
    Stack,
    CfnOutput,
    aws_ec2 as ec2,
    aws_logs as logs,
    Tags,
)
from constructs import Construct


class VpcStack(Stack):
    """
    VPC Stack for AWS Proton Infrastructure
    
    Creates a production-ready VPC with public and private subnets,
    NAT gateways, and appropriate security configurations for use
    with AWS Proton templates.
    """
    
    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        env_name: str,
        vpc_cidr: str = "10.0.0.0/16",
        max_azs: int = 2,
        **kwargs
    ) -> None:
        """
        Initialize the VPC Stack
        
        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            env_name: Environment name for resource naming
            vpc_cidr: CIDR block for the VPC
            max_azs: Maximum number of availability zones to use
            **kwargs: Additional stack arguments
        """
        super().__init__(scope, construct_id, **kwargs)
        
        self.env_name = env_name
        
        # Create VPC with public and private subnets
        self.vpc = ec2.Vpc(
            self,
            "ProtonVpc",
            vpc_name=f"{env_name}-vpc",
            ip_addresses=ec2.IpAddresses.cidr(vpc_cidr),
            max_azs=max_azs,
            nat_gateways=1,  # Cost optimization: single NAT gateway
            enable_dns_hostnames=True,
            enable_dns_support=True,
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
        )
        
        # Create VPC Flow Logs for security monitoring
        self._create_flow_logs()
        
        # Create security groups
        self._create_security_groups()
        
        # Create outputs for Proton templates
        self._create_outputs()
        
        # Add tags
        self._add_tags()
    
    def _create_flow_logs(self) -> None:
        """Create VPC Flow Logs for network monitoring and security."""
        
        # Create CloudWatch Log Group for VPC Flow Logs
        flow_log_group = logs.LogGroup(
            self,
            "VpcFlowLogGroup",
            log_group_name=f"/aws/vpc/flowlogs/{self.env_name}",
            retention=logs.RetentionDays.ONE_MONTH,
        )
        
        # Create VPC Flow Logs
        self.vpc.add_flow_log(
            "FlowLogToCloudWatch",
            destination=ec2.FlowLogDestination.to_cloud_watch_logs(flow_log_group),
            traffic_type=ec2.FlowLogTrafficType.ALL,
        )
    
    def _create_security_groups(self) -> None:
        """Create common security groups for use by Proton services."""
        
        # Application Load Balancer security group
        self.alb_security_group = ec2.SecurityGroup(
            self,
            "AlbSecurityGroup",
            vpc=self.vpc,
            description="Security group for Application Load Balancer",
            security_group_name=f"{self.env_name}-alb-sg",
        )
        
        # Allow HTTP traffic from internet
        self.alb_security_group.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(80),
            description="Allow HTTP traffic from internet",
        )
        
        # Allow HTTPS traffic from internet
        self.alb_security_group.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(443),
            description="Allow HTTPS traffic from internet",
        )
        
        # ECS service security group
        self.ecs_security_group = ec2.SecurityGroup(
            self,
            "EcsSecurityGroup",
            vpc=self.vpc,
            description="Security group for ECS services",
            security_group_name=f"{self.env_name}-ecs-sg",
        )
        
        # Allow traffic from ALB to ECS services
        self.ecs_security_group.add_ingress_rule(
            peer=self.alb_security_group,
            connection=ec2.Port.all_tcp(),
            description="Allow traffic from ALB to ECS services",
        )
        
        # Database security group
        self.db_security_group = ec2.SecurityGroup(
            self,
            "DatabaseSecurityGroup",
            vpc=self.vpc,
            description="Security group for databases",
            security_group_name=f"{self.env_name}-db-sg",
        )
        
        # Allow traffic from ECS to database
        self.db_security_group.add_ingress_rule(
            peer=self.ecs_security_group,
            connection=ec2.Port.tcp(5432),  # PostgreSQL
            description="Allow PostgreSQL traffic from ECS",
        )
        
        self.db_security_group.add_ingress_rule(
            peer=self.ecs_security_group,
            connection=ec2.Port.tcp(3306),  # MySQL
            description="Allow MySQL traffic from ECS",
        )
    
    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for use by Proton templates."""
        
        # VPC outputs
        CfnOutput(
            self,
            "VpcId",
            value=self.vpc.vpc_id,
            description="VPC ID for Proton services",
            export_name=f"{self.env_name}-vpc-id",
        )
        
        CfnOutput(
            self,
            "VpcCidr",
            value=self.vpc.vpc_cidr_block,
            description="VPC CIDR block",
            export_name=f"{self.env_name}-vpc-cidr",
        )
        
        # Public subnet outputs
        public_subnet_ids = [subnet.subnet_id for subnet in self.vpc.public_subnets]
        CfnOutput(
            self,
            "PublicSubnetIds",
            value=",".join(public_subnet_ids),
            description="Public subnet IDs",
            export_name=f"{self.env_name}-public-subnet-ids",
        )
        
        # Private subnet outputs
        private_subnet_ids = [subnet.subnet_id for subnet in self.vpc.private_subnets]
        CfnOutput(
            self,
            "PrivateSubnetIds",
            value=",".join(private_subnet_ids),
            description="Private subnet IDs",
            export_name=f"{self.env_name}-private-subnet-ids",
        )
        
        # Security group outputs
        CfnOutput(
            self,
            "AlbSecurityGroupId",
            value=self.alb_security_group.security_group_id,
            description="ALB security group ID",
            export_name=f"{self.env_name}-alb-sg-id",
        )
        
        CfnOutput(
            self,
            "EcsSecurityGroupId",
            value=self.ecs_security_group.security_group_id,
            description="ECS security group ID",
            export_name=f"{self.env_name}-ecs-sg-id",
        )
        
        CfnOutput(
            self,
            "DatabaseSecurityGroupId",
            value=self.db_security_group.security_group_id,
            description="Database security group ID",
            export_name=f"{self.env_name}-db-sg-id",
        )
    
    def _add_tags(self) -> None:
        """Add tags to VPC resources."""
        Tags.of(self.vpc).add("Name", f"{self.env_name}-vpc")
        Tags.of(self.vpc).add("Purpose", "ProtonEnvironment")
        Tags.of(self.vpc).add("Component", "Networking")
        
        # Tag subnets
        for i, subnet in enumerate(self.vpc.public_subnets):
            Tags.of(subnet).add("Name", f"{self.env_name}-public-subnet-{i+1}")
            Tags.of(subnet).add("Type", "Public")
        
        for i, subnet in enumerate(self.vpc.private_subnets):
            Tags.of(subnet).add("Name", f"{self.env_name}-private-subnet-{i+1}")
            Tags.of(subnet).add("Type", "Private")
    
    @property
    def public_subnets(self) -> List[ec2.ISubnet]:
        """Get public subnets."""
        return self.vpc.public_subnets
    
    @property
    def private_subnets(self) -> List[ec2.ISubnet]:
        """Get private subnets."""
        return self.vpc.private_subnets