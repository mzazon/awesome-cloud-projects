#!/usr/bin/env python3
"""
AWS CDK Python application for Establishing Private Blockchain Networks with Amazon Managed Blockchain.

This application creates a complete blockchain infrastructure including:
- Amazon Managed Blockchain network with Hyperledger Fabric
- VPC endpoint for secure blockchain access
- EC2 instance with blockchain client tools
- IAM roles and security groups
- Monitoring and logging configuration
"""

import aws_cdk as cdk
from aws_cdk import (
    App,
    Environment,
    Stack,
    CfnOutput,
    RemovalPolicy,
    Duration,
    aws_managedblockchain as managedblockchain,
    aws_ec2 as ec2,
    aws_iam as iam,
    aws_logs as logs,
    aws_ssm as ssm,
)
from constructs import Construct
import json


class ManagedBlockchainStack(Stack):
    """
    CDK Stack for Amazon Managed Blockchain private network infrastructure.
    
    This stack creates a complete blockchain solution with:
    - Hyperledger Fabric network and initial member
    - VPC with security groups for blockchain communication
    - EC2 instance configured as blockchain client
    - IAM roles with appropriate permissions
    - CloudWatch logging and monitoring
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Environment variables and parameters
        self.network_name = "SupplyChainNetwork"
        self.member_name = "OrganizationA"
        self.admin_username = "admin"
        self.admin_password = "TempPassword123!"

        # Create VPC for blockchain infrastructure
        self.vpc = self._create_vpc()
        
        # Create security groups
        self.security_group = self._create_security_groups()
        
        # Create IAM roles
        self.blockchain_role = self._create_iam_roles()
        
        # Create CloudWatch log group
        self.log_group = self._create_logging()
        
        # Create Managed Blockchain network
        self.network = self._create_blockchain_network()
        
        # Create blockchain member
        self.member = self._create_blockchain_member()
        
        # Create peer node
        self.peer_node = self._create_peer_node()
        
        # Create VPC endpoint
        self.vpc_endpoint = self._create_vpc_endpoint()
        
        # Create EC2 client instance
        self.client_instance = self._create_client_instance()
        
        # Store network configuration in SSM
        self._store_network_configuration()
        
        # Create stack outputs
        self._create_outputs()

    def _create_vpc(self) -> ec2.Vpc:
        """Create VPC with public and private subnets for blockchain infrastructure."""
        vpc = ec2.Vpc(
            self,
            "BlockchainVpc",
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

        # Add tags for better resource management
        cdk.Tags.of(vpc).add("Project", "PrivateBlockchain")
        cdk.Tags.of(vpc).add("Environment", "Production")

        return vpc

    def _create_security_groups(self) -> ec2.SecurityGroup:
        """Create security groups for blockchain network communication."""
        # Main security group for blockchain components
        security_group = ec2.SecurityGroup(
            self,
            "BlockchainSecurityGroup",
            vpc=self.vpc,
            description="Security group for Amazon Managed Blockchain access",
            allow_all_outbound=True,
        )

        # Allow HTTPS for VPC endpoint access
        security_group.add_ingress_rule(
            peer=ec2.Peer.ipv4("10.0.0.0/8"),
            connection=ec2.Port.tcp(443),
            description="HTTPS for VPC endpoint access",
        )

        # Allow Hyperledger Fabric peer communication ports
        security_group.add_ingress_rule(
            peer=ec2.Peer.ipv4("10.0.0.0/8"),
            connection=ec2.Port.tcp(30001),
            description="Hyperledger Fabric peer endpoint",
        )

        security_group.add_ingress_rule(
            peer=ec2.Peer.ipv4("10.0.0.0/8"),
            connection=ec2.Port.tcp(30002),
            description="Hyperledger Fabric peer event endpoint",
        )

        # Allow peer-to-peer communication
        security_group.add_ingress_rule(
            peer=security_group,
            connection=ec2.Port.tcp(7051),
            description="Peer-to-peer communication",
        )

        security_group.add_ingress_rule(
            peer=security_group,
            connection=ec2.Port.tcp(7053),
            description="Peer event service",
        )

        # Allow SSH access for client instance
        security_group.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(22),
            description="SSH access to client instance",
        )

        return security_group

    def _create_iam_roles(self) -> iam.Role:
        """Create IAM roles for blockchain operations."""
        # Role for Managed Blockchain service
        blockchain_role = iam.Role(
            self,
            "ManagedBlockchainRole",
            assumed_by=iam.ServicePrincipal("managedblockchain.amazonaws.com"),
            description="IAM role for Amazon Managed Blockchain service",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonManagedBlockchainFullAccess")
            ],
        )

        # Role for EC2 blockchain client
        client_role = iam.Role(
            self,
            "BlockchainClientRole",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            description="IAM role for blockchain client EC2 instance",
        )

        # Policy for chaincode execution and blockchain operations
        chaincode_policy = iam.PolicyDocument(
            statements=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "managedblockchain:*",
                        "logs:CreateLogGroup",
                        "logs:CreateLogStream",
                        "logs:PutLogEvents",
                        "logs:DescribeLogGroups",
                        "logs:DescribeLogStreams",
                        "ssm:GetParameter",
                        "ssm:GetParameters",
                        "ssm:PutParameter",
                    ],
                    resources=["*"],
                ),
            ]
        )

        client_role.attach_inline_policy(
            iam.Policy(
                self,
                "BlockchainChaincodePolicy",
                document=chaincode_policy,
            )
        )

        # Create instance profile for EC2
        iam.CfnInstanceProfile(
            self,
            "BlockchainClientInstanceProfile",
            roles=[client_role.role_name],
            instance_profile_name="BlockchainClientInstanceProfile",
        )

        return blockchain_role

    def _create_logging(self) -> logs.LogGroup:
        """Create CloudWatch log group for blockchain monitoring."""
        log_group = logs.LogGroup(
            self,
            "BlockchainLogGroup",
            log_group_name=f"/aws/managedblockchain/{self.network_name}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY,
        )

        return log_group

    def _create_blockchain_network(self) -> managedblockchain.CfnNetwork:
        """Create Amazon Managed Blockchain network with Hyperledger Fabric."""
        # Network configuration
        network_configuration = managedblockchain.CfnNetwork.NetworkConfigurationProperty(
            name=self.network_name,
            description="Private blockchain network for supply chain tracking",
            framework="HYPERLEDGER_FABRIC",
            framework_version="2.2",
            network_framework_configuration=managedblockchain.CfnNetwork.NetworkFrameworkConfigurationProperty(
                network_fabric_configuration=managedblockchain.CfnNetwork.NetworkFabricConfigurationProperty(
                    edition="STANDARD"
                )
            ),
            voting_policy=managedblockchain.CfnNetwork.VotingPolicyProperty(
                approval_threshold_policy=managedblockchain.CfnNetwork.ApprovalThresholdPolicyProperty(
                    threshold_percentage=50,
                    proposal_duration_in_hours=24,
                    threshold_comparator="GREATER_THAN",
                )
            ),
        )

        # Create the network
        network = managedblockchain.CfnNetwork(
            self,
            "BlockchainNetwork",
            network_configuration=network_configuration,
        )

        # Add tags
        cdk.Tags.of(network).add("Environment", "Production")
        cdk.Tags.of(network).add("Project", "SupplyChain")

        return network

    def _create_blockchain_member(self) -> managedblockchain.CfnMember:
        """Create blockchain network member."""
        member_configuration = managedblockchain.CfnMember.MemberConfigurationProperty(
            name=self.member_name,
            description="Founding member of supply chain network",
            member_framework_configuration=managedblockchain.CfnMember.MemberFrameworkConfigurationProperty(
                member_fabric_configuration=managedblockchain.CfnMember.MemberFabricConfigurationProperty(
                    admin_username=self.admin_username,
                    admin_password=self.admin_password,
                )
            ),
        )

        member = managedblockchain.CfnMember(
            self,
            "BlockchainMember",
            network_id=self.network.attr_network_id,
            member_configuration=member_configuration,
        )

        member.add_dependency(self.network)

        return member

    def _create_peer_node(self) -> managedblockchain.CfnNode:
        """Create peer node for blockchain member."""
        node_configuration = managedblockchain.CfnNode.NodeConfigurationProperty(
            availability_zone=f"{self.region}a",
            instance_type="bc.t3.small",
        )

        peer_node = managedblockchain.CfnNode(
            self,
            "BlockchainPeerNode",
            network_id=self.network.attr_network_id,
            member_id=self.member.attr_member_id,
            node_configuration=node_configuration,
        )

        peer_node.add_dependency(self.member)

        # Add tags
        cdk.Tags.of(peer_node).add("Environment", "Production")
        cdk.Tags.of(peer_node).add("NodeType", "Peer")

        return peer_node

    def _create_vpc_endpoint(self) -> ec2.VpcEndpoint:
        """Create VPC endpoint for secure blockchain access."""
        vpc_endpoint = ec2.VpcEndpoint(
            self,
            "BlockchainVpcEndpoint",
            vpc=self.vpc,
            service=ec2.InterfaceVpcEndpointAwsService.MANAGED_BLOCKCHAIN,
            subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
            ),
            security_groups=[self.security_group],
            private_dns_enabled=True,
        )

        return vpc_endpoint

    def _create_client_instance(self) -> ec2.Instance:
        """Create EC2 instance configured as blockchain client."""
        # User data script for blockchain client setup
        user_data = ec2.UserData.for_linux()
        user_data.add_commands(
            "#!/bin/bash",
            "yum update -y",
            "yum install -y docker git",
            "systemctl start docker",
            "systemctl enable docker",
            "usermod -a -G docker ec2-user",
            "",
            "# Install Docker Compose",
            'curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose',
            "chmod +x /usr/local/bin/docker-compose",
            "",
            "# Install Node.js via NVM",
            "sudo -u ec2-user bash -c 'curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash'",
            "sudo -u ec2-user bash -c 'export NVM_DIR=\"$HOME/.nvm\" && [ -s \"$NVM_DIR/nvm.sh\" ] && . \"$NVM_DIR/nvm.sh\" && nvm install 16 && nvm use 16'",
            "",
            "# Download Hyperledger Fabric binaries",
            "cd /home/ec2-user",
            "sudo -u ec2-user bash -c 'curl -sSL https://bit.ly/2ysbOFE | bash -s -- 2.2.0 1.4.9'",
            "",
            "# Set up directory structure",
            "sudo -u ec2-user mkdir -p /home/ec2-user/blockchain-client/{crypto-config,channel-artifacts}",
            "",
            "# Add Fabric binaries to PATH",
            "echo 'export PATH=/home/ec2-user/fabric-samples/bin:$PATH' >> /home/ec2-user/.bashrc",
            "",
            "# Create sample chaincode directory",
            "sudo -u ec2-user mkdir -p /home/ec2-user/chaincode/asset-management",
            "",
            "# Signal completion",
            "echo 'Blockchain client setup completed' > /tmp/setup-complete.log",
        )

        # Create key pair
        key_pair = ec2.KeyPair(
            self,
            "BlockchainClientKeyPair",
            key_pair_name="blockchain-client-key",
            type=ec2.KeyPairType.RSA,
        )

        # Create the EC2 instance
        client_instance = ec2.Instance(
            self,
            "BlockchainClientInstance",
            instance_type=ec2.InstanceType.of(
                ec2.InstanceClass.T3, ec2.InstanceSize.MEDIUM
            ),
            machine_image=ec2.MachineImage.latest_amazon_linux2(),
            vpc=self.vpc,
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PUBLIC,
            ),
            security_group=self.security_group,
            key_pair=key_pair,
            user_data=user_data,
            role=iam.Role.from_role_name(
                self, "ExistingClientRole", "BlockchainClientRole"
            ) if self.node.try_get_context("existing_role") else None,
        )

        # Add tags
        cdk.Tags.of(client_instance).add("Name", "blockchain-client")
        cdk.Tags.of(client_instance).add("Project", "PrivateBlockchain")

        return client_instance

    def _store_network_configuration(self) -> None:
        """Store network configuration in SSM Parameter Store."""
        # Store network configuration for future reference
        network_config = {
            "NetworkId": self.network.attr_network_id,
            "NetworkName": self.network_name,
            "MemberId": self.member.attr_member_id,
            "MemberName": self.member_name,
            "NodeId": self.peer_node.attr_node_id,
            "Region": self.region,
            "VpcId": self.vpc.vpc_id,
            "VpcEndpointId": self.vpc_endpoint.vpc_endpoint_id,
        }

        ssm.StringParameter(
            self,
            "NetworkConfiguration",
            parameter_name="/blockchain/network-configuration",
            string_value=json.dumps(network_config, indent=2),
            description="Amazon Managed Blockchain network configuration",
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources."""
        CfnOutput(
            self,
            "NetworkId",
            value=self.network.attr_network_id,
            description="Amazon Managed Blockchain Network ID",
        )

        CfnOutput(
            self,
            "MemberId",
            value=self.member.attr_member_id,
            description="Blockchain Network Member ID",
        )

        CfnOutput(
            self,
            "NodeId",
            value=self.peer_node.attr_node_id,
            description="Blockchain Peer Node ID",
        )

        CfnOutput(
            self,
            "CAEndpoint",
            value=self.member.attr_ca_endpoint,
            description="Certificate Authority Endpoint",
        )

        CfnOutput(
            self,
            "PeerEndpoint",
            value=self.peer_node.attr_peer_endpoint,
            description="Peer Node Endpoint",
        )

        CfnOutput(
            self,
            "VpcEndpointId",
            value=self.vpc_endpoint.vpc_endpoint_id,
            description="VPC Endpoint ID for Managed Blockchain",
        )

        CfnOutput(
            self,
            "ClientInstanceId",
            value=self.client_instance.instance_id,
            description="EC2 Client Instance ID",
        )

        CfnOutput(
            self,
            "ClientPublicIp",
            value=self.client_instance.instance_public_ip,
            description="EC2 Client Instance Public IP",
        )

        CfnOutput(
            self,
            "SSHCommand",
            value=f"ssh -i blockchain-client-key.pem ec2-user@{self.client_instance.instance_public_ip}",
            description="SSH command to connect to client instance",
        )


def main():
    """Main application entry point."""
    app = App()
    
    # Get environment configuration
    env = Environment(
        account=app.node.try_get_context("account") or None,
        region=app.node.try_get_context("region") or "us-east-1",
    )
    
    # Create the blockchain stack
    ManagedBlockchainStack(
        app,
        "ManagedBlockchainStack",
        env=env,
        description="Amazon Managed Blockchain private network infrastructure",
    )
    
    app.synth()


if __name__ == "__main__":
    main()