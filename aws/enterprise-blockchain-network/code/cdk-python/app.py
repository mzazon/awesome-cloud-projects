#!/usr/bin/env python3
"""
CDK Application for Hyperledger Fabric on Amazon Managed Blockchain

This CDK application deploys a complete Hyperledger Fabric blockchain infrastructure
using Amazon Managed Blockchain, including VPC, networking, and client resources
for secure blockchain application development.
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    Tags,
    CfnOutput,
    CfnParameter,
    RemovalPolicy,
    Duration,
    aws_ec2 as ec2,
    aws_managedblockchain as managedblockchain,
    aws_iam as iam,
    aws_logs as logs,
    aws_ssm as ssm,
)
from constructs import Construct
import json
from typing import Optional


class HyperledgerFabricStack(Stack):
    """
    CDK Stack for Hyperledger Fabric on Amazon Managed Blockchain
    
    This stack creates:
    - VPC with public and private subnets
    - Amazon Managed Blockchain network with Hyperledger Fabric
    - Member organization and peer node
    - VPC endpoint for secure blockchain access
    - EC2 instance for blockchain client development
    - IAM roles and security groups
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Parameters for customization
        self.network_name = CfnParameter(
            self, "NetworkName",
            type="String",
            default="fabric-enterprise-network",
            description="Name for the Hyperledger Fabric blockchain network"
        )

        self.member_name = CfnParameter(
            self, "MemberName", 
            type="String",
            default="founding-member-org",
            description="Name for the founding member organization"
        )

        self.admin_username = CfnParameter(
            self, "AdminUsername",
            type="String",
            default="admin",
            description="Admin username for the blockchain member organization"
        )

        self.admin_password = CfnParameter(
            self, "AdminPassword",
            type="String",
            default="TempPassword123!",
            no_echo=True,
            description="Admin password for the blockchain member organization (min 8 chars, must include uppercase, lowercase, number, special char)"
        )

        self.key_pair_name = CfnParameter(
            self, "KeyPairName",
            type="String",
            description="EC2 Key Pair name for SSH access to client instance (must exist in your account)"
        )

        self.ssh_source_cidr = CfnParameter(
            self, "SSHSourceCIDR",
            type="String",
            default="0.0.0.0/0",
            description="CIDR block allowed to SSH to the client instance (restrict for security)"
        )

        # Create VPC for blockchain infrastructure
        self.vpc = self._create_vpc()
        
        # Create IAM roles for blockchain access
        self.blockchain_role = self._create_blockchain_iam_role()
        
        # Create the blockchain network
        self.network, self.member = self._create_blockchain_network()
        
        # Create peer node (depends on network and member)
        self.peer_node = self._create_peer_node()
        
        # Create VPC endpoint for secure blockchain access
        self.vpc_endpoint = self._create_vpc_endpoint()
        
        # Create client EC2 instance
        self.client_instance = self._create_client_instance()
        
        # Create CloudWatch Log Group for monitoring
        self.log_group = self._create_log_group()
        
        # Output important values
        self._create_outputs()

    def _create_vpc(self) -> ec2.Vpc:
        """Create VPC with public and private subnets for blockchain infrastructure."""
        vpc = ec2.Vpc(
            self, "BlockchainVPC",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=2,
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    subnet_type=ec2.SubnetType.PUBLIC,
                    name="PublicSubnet",
                    cidr_mask=24
                ),
                ec2.SubnetConfiguration(
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                    name="PrivateSubnet", 
                    cidr_mask=24
                )
            ],
            enable_dns_hostnames=True,
            enable_dns_support=True
        )

        # Add tags for identification
        Tags.of(vpc).add("Name", "blockchain-vpc")
        Tags.of(vpc).add("Purpose", "HyperledgerFabric")

        return vpc

    def _create_blockchain_iam_role(self) -> iam.Role:
        """Create IAM role for blockchain operations."""
        role = iam.Role(
            self, "BlockchainServiceRole",
            assumed_by=iam.ServicePrincipal("managedblockchain.amazonaws.com"),
            description="IAM role for Amazon Managed Blockchain operations",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonManagedBlockchainReadOnlyAccess")
            ]
        )

        # Add custom policy for blockchain operations
        blockchain_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "managedblockchain:CreateNetwork",
                "managedblockchain:CreateMember", 
                "managedblockchain:CreateNode",
                "managedblockchain:GetNetwork",
                "managedblockchain:GetMember",
                "managedblockchain:GetNode",
                "managedblockchain:ListNetworks",
                "managedblockchain:ListMembers",
                "managedblockchain:ListNodes",
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents",
                "logs:DescribeLog*"
            ],
            resources=["*"]
        )

        role.add_to_policy(blockchain_policy)
        return role

    def _create_blockchain_network(self) -> tuple[managedblockchain.CfnNetwork, managedblockchain.CfnMember]:
        """Create Hyperledger Fabric blockchain network and founding member."""
        
        # Define network framework configuration
        network_fabric_config = managedblockchain.CfnNetwork.NetworkFabricConfigurationProperty(
            edition="STARTER"  # Use STARTER edition for development/testing
        )

        # Define voting policy for network governance
        voting_policy = managedblockchain.CfnNetwork.VotingPolicyProperty(
            approval_threshold_policy=managedblockchain.CfnNetwork.ApprovalThresholdPolicyProperty(
                threshold_percentage=50,
                proposal_duration_in_hours=24,
                threshold_comparator="GREATER_THAN"
            )
        )

        # Create the blockchain network
        network = managedblockchain.CfnNetwork(
            self, "HyperledgerFabricNetwork",
            name=self.network_name.value_as_string,
            description="Enterprise Hyperledger Fabric network for secure transactions",
            framework="HYPERLEDGER_FABRIC",
            framework_version="2.2",
            framework_configuration=managedblockchain.CfnNetwork.NetworkFrameworkConfigurationProperty(
                network_fabric_configuration=network_fabric_config
            ),
            voting_policy=voting_policy
        )

        # Configure the founding member organization
        member_fabric_config = managedblockchain.CfnMember.MemberFabricConfigurationProperty(
            admin_username=self.admin_username.value_as_string,
            admin_password=self.admin_password.value_as_string
        )

        member_config = managedblockchain.CfnMember.MemberConfigurationProperty(
            name=self.member_name.value_as_string,
            description="Founding member organization for the blockchain network",
            member_framework_configuration=managedblockchain.CfnMember.MemberFrameworkConfigurationProperty(
                member_fabric_configuration=member_fabric_config
            )
        )

        # Create the member as part of network creation
        network.member_configuration = member_config

        # Create a separate member resource for easier management
        member = managedblockchain.CfnMember(
            self, "FoundingMember",
            network_id=network.attr_network_id,
            member_configuration=member_config
        )

        member.add_dependency(network)

        return network, member

    def _create_peer_node(self) -> managedblockchain.CfnNode:
        """Create peer node for the blockchain member."""
        
        # Configure node properties
        node_config = managedblockchain.CfnNode.NodeConfigurationProperty(
            instance_type="bc.t3.small",  # Cost-effective for development
            availability_zone=self.vpc.availability_zones[0]
        )

        # Create the peer node
        peer_node = managedblockchain.CfnNode(
            self, "PeerNode",
            network_id=self.network.attr_network_id,
            member_id=self.member.attr_member_id,
            node_configuration=node_config
        )

        # Ensure proper dependency order
        peer_node.add_dependency(self.member)

        return peer_node

    def _create_vpc_endpoint(self) -> ec2.InterfaceVpcEndpoint:
        """Create VPC endpoint for secure blockchain access."""
        
        # Create security group for VPC endpoint
        endpoint_sg = ec2.SecurityGroup(
            self, "BlockchainVPCEndpointSG",
            vpc=self.vpc,
            description="Security group for blockchain VPC endpoint",
            allow_all_outbound=True
        )

        # Allow HTTPS traffic for blockchain API calls
        endpoint_sg.add_ingress_rule(
            peer=ec2.Peer.ipv4(self.vpc.vpc_cidr_block),
            connection=ec2.Port.tcp(443),
            description="Allow HTTPS from VPC for blockchain API access"
        )

        # Note: The actual VPC endpoint service name will be created after the network exists
        # For now, we'll create a placeholder that would be updated post-deployment
        vpc_endpoint = ec2.InterfaceVpcEndpoint(
            self, "BlockchainVPCEndpoint",
            vpc=self.vpc,
            service=ec2.InterfaceVpcEndpointService(
                name=f"com.amazonaws.{self.region}.managedblockchain.{self.network.attr_network_id}",
                port=443
            ),
            subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS
            ),
            security_groups=[endpoint_sg],
            private_dns_enabled=True
        )

        Tags.of(vpc_endpoint).add("Name", "blockchain-vpc-endpoint")
        return vpc_endpoint

    def _create_client_instance(self) -> ec2.Instance:
        """Create EC2 instance for blockchain client development."""
        
        # Create security group for client instance
        client_sg = ec2.SecurityGroup(
            self, "BlockchainClientSG",
            vpc=self.vpc,
            description="Security group for blockchain client instance",
            allow_all_outbound=True
        )

        # Allow SSH access
        client_sg.add_ingress_rule(
            peer=ec2.Peer.ipv4(self.ssh_source_cidr.value_as_string),
            connection=ec2.Port.tcp(22),
            description="Allow SSH access"
        )

        # Create IAM role for EC2 instance
        instance_role = iam.Role(
            self, "ClientInstanceRole",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            description="IAM role for blockchain client EC2 instance",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonSSMManagedInstanceCore"),
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonManagedBlockchainReadOnlyAccess")
            ]
        )

        # Add custom permissions for blockchain operations
        instance_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "managedblockchain:CreateAccessor",
                    "managedblockchain:ListAccessors",
                    "managedblockchain:GetAccessor",
                    "managedblockchain:TagResource",
                    "ec2:CreateTags",
                    "ec2:DescribeVpcs",
                    "ec2:DescribeSubnets",
                    "ec2:DescribeVpcEndpoints"
                ],
                resources=["*"]
            )
        )

        # User data script to configure the instance
        user_data = ec2.UserData.for_linux()
        user_data.add_commands(
            "#!/bin/bash",
            "yum update -y",
            "yum install -y git docker",
            "systemctl start docker",
            "systemctl enable docker",
            "usermod -a -G docker ec2-user",
            
            # Install Node.js using Node Version Manager
            "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash",
            'export NVM_DIR="$HOME/.nvm"',
            '[ -s "$NVM_DIR/nvm.sh" ] && \\. "$NVM_DIR/nvm.sh"',
            "nvm install 18",
            "nvm use 18",
            "npm install -g yarn",
            
            # Create directory for blockchain client applications
            "mkdir -p /home/ec2-user/fabric-client-app",
            "chown ec2-user:ec2-user /home/ec2-user/fabric-client-app",
            
            # Install AWS CLI v2
            "curl 'https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip' -o 'awscliv2.zip'",
            "unzip awscliv2.zip",
            "./aws/install",
            
            # Create sample package.json for Fabric SDK
            'cat > /home/ec2-user/fabric-client-app/package.json << EOF',
            '{',
            '  "name": "fabric-blockchain-client",',
            '  "version": "1.0.0",',
            '  "description": "Hyperledger Fabric client for Amazon Managed Blockchain",',
            '  "main": "app.js",',
            '  "dependencies": {',
            '    "fabric-network": "^2.2.20",',
            '    "fabric-client": "^1.4.22",',
            '    "fabric-ca-client": "^2.2.20"',
            '  }',
            '}',
            'EOF',
            
            "chown ec2-user:ec2-user /home/ec2-user/fabric-client-app/package.json",
            
            # Signal successful completion
            "echo 'Blockchain client instance setup complete' > /home/ec2-user/setup-complete.txt"
        )

        # Get the latest Amazon Linux 2 AMI
        amazon_linux = ec2.MachineImage.latest_amazon_linux2(
            cpu_type=ec2.AmazonLinuxCpuType.X86_64
        )

        # Create the EC2 instance
        instance = ec2.Instance(
            self, "BlockchainClientInstance",
            instance_type=ec2.InstanceType.of(
                ec2.InstanceClass.T3, 
                ec2.InstanceSize.MEDIUM
            ),
            machine_image=amazon_linux,
            vpc=self.vpc,
            subnet_selection=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PUBLIC
            ),
            security_group=client_sg,
            role=instance_role,
            user_data=user_data,
            key_name=self.key_pair_name.value_as_string
        )

        Tags.of(instance).add("Name", "blockchain-client")
        Tags.of(instance).add("Purpose", "HyperledgerFabricClient")

        return instance

    def _create_log_group(self) -> logs.LogGroup:
        """Create CloudWatch Log Group for blockchain monitoring."""
        log_group = logs.LogGroup(
            self, "BlockchainLogGroup",
            log_group_name="/aws/managedblockchain/hyperledger-fabric",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY
        )

        return log_group

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information."""
        
        CfnOutput(
            self, "NetworkId",
            value=self.network.attr_network_id,
            description="Hyperledger Fabric Network ID",
            export_name=f"{self.stack_name}-NetworkId"
        )

        CfnOutput(
            self, "MemberId", 
            value=self.member.attr_member_id,
            description="Member Organization ID",
            export_name=f"{self.stack_name}-MemberId"
        )

        CfnOutput(
            self, "NodeId",
            value=self.peer_node.attr_node_id,
            description="Peer Node ID",
            export_name=f"{self.stack_name}-NodeId"
        )

        CfnOutput(
            self, "VPCId",
            value=self.vpc.vpc_id,
            description="VPC ID for blockchain infrastructure",
            export_name=f"{self.stack_name}-VPCId"
        )

        CfnOutput(
            self, "ClientInstanceId",
            value=self.client_instance.instance_id,
            description="Blockchain client EC2 instance ID",
            export_name=f"{self.stack_name}-ClientInstanceId"
        )

        CfnOutput(
            self, "ClientInstancePublicIP",
            value=self.client_instance.instance_public_ip,
            description="Public IP address of blockchain client instance",
            export_name=f"{self.stack_name}-ClientInstancePublicIP"
        )

        CfnOutput(
            self, "VPCEndpointId",
            value=self.vpc_endpoint.vpc_endpoint_id,
            description="VPC Endpoint ID for secure blockchain access",
            export_name=f"{self.stack_name}-VPCEndpointId"
        )

        CfnOutput(
            self, "LogGroupName",
            value=self.log_group.log_group_name,
            description="CloudWatch Log Group for blockchain monitoring",
            export_name=f"{self.stack_name}-LogGroupName"
        )


def main():
    """Main application entry point."""
    app = cdk.App()
    
    # Get environment from context or use default
    env = Environment(
        account=app.node.try_get_context("account") or "123456789012",
        region=app.node.try_get_context("region") or "us-east-1"
    )
    
    # Create the stack
    stack = HyperledgerFabricStack(
        app, "HyperledgerFabricStack",
        env=env,
        description="Hyperledger Fabric blockchain infrastructure on Amazon Managed Blockchain",
        termination_protection=False  # Set to True for production
    )
    
    # Add global tags
    Tags.of(app).add("Project", "HyperledgerFabric")
    Tags.of(app).add("Environment", "Development")
    Tags.of(app).add("ManagedBy", "CDK")
    
    app.synth()


if __name__ == "__main__":
    main()