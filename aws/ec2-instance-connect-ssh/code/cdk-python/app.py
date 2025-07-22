#!/usr/bin/env python3
"""
AWS CDK Python application for EC2 Instance Connect secure SSH access.

This application deploys the infrastructure needed to demonstrate EC2 Instance Connect
for secure SSH access management, including:
- VPC with public and private subnets
- EC2 instances with Instance Connect support
- Security groups for SSH access
- IAM policies and roles for Instance Connect
- EC2 Instance Connect Endpoint for private instance access
- CloudTrail for audit logging
"""

import os
from typing import Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    CfnOutput,
    Duration,
    RemovalPolicy,
    aws_ec2 as ec2,
    aws_iam as iam,
    aws_cloudtrail as cloudtrail,
    aws_s3 as s3,
)
from constructs import Construct


class EC2InstanceConnectStack(Stack):
    """Stack for EC2 Instance Connect secure SSH access demonstration."""

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        environment_name: str = "dev",
        **kwargs
    ) -> None:
        """
        Initialize the EC2 Instance Connect stack.

        Args:
            scope: The scope in which to define this stack
            construct_id: The scoped construct ID
            environment_name: Environment name for resource tagging
            **kwargs: Additional keyword arguments
        """
        super().__init__(scope, construct_id, **kwargs)

        self.environment_name = environment_name

        # Create VPC and networking components
        self._create_vpc()

        # Create security groups
        self._create_security_groups()

        # Create IAM resources
        self._create_iam_resources()

        # Create EC2 instances
        self._create_ec2_instances()

        # Create Instance Connect Endpoint
        self._create_instance_connect_endpoint()

        # Create CloudTrail for auditing
        self._create_cloudtrail()

        # Create stack outputs
        self._create_outputs()

    def _create_vpc(self) -> None:
        """Create VPC with public and private subnets."""
        # Create VPC with public and private subnets
        self.vpc = ec2.Vpc(
            self,
            "EC2ConnectVpc",
            vpc_name=f"ec2-connect-vpc-{self.environment_name}",
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
                    subnet_type=ec2.SubnetType.PRIVATE_ISOLATED,
                    cidr_mask=24,
                ),
            ],
            enable_dns_hostnames=True,
            enable_dns_support=True,
        )

        # Add tags to VPC
        cdk.Tags.of(self.vpc).add("Name", f"ec2-connect-vpc-{self.environment_name}")
        cdk.Tags.of(self.vpc).add("Environment", self.environment_name)
        cdk.Tags.of(self.vpc).add("Purpose", "EC2InstanceConnect")

    def _create_security_groups(self) -> None:
        """Create security groups for SSH access."""
        # Security group for EC2 instances with SSH access
        self.ssh_security_group = ec2.SecurityGroup(
            self,
            "SSHSecurityGroup",
            vpc=self.vpc,
            description="Security group for EC2 Instance Connect SSH access",
            security_group_name=f"ec2-connect-ssh-sg-{self.environment_name}",
            allow_all_outbound=True,
        )

        # Allow SSH access from anywhere (restrict in production)
        self.ssh_security_group.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(22),
            description="SSH access for EC2 Instance Connect",
        )

        # Add tags to security group
        cdk.Tags.of(self.ssh_security_group).add(
            "Name", f"ec2-connect-ssh-sg-{self.environment_name}"
        )
        cdk.Tags.of(self.ssh_security_group).add("Environment", self.environment_name)

    def _create_iam_resources(self) -> None:
        """Create IAM policies and roles for EC2 Instance Connect."""
        # Create IAM policy for EC2 Instance Connect
        self.instance_connect_policy = iam.ManagedPolicy(
            self,
            "EC2InstanceConnectPolicy",
            managed_policy_name=f"EC2InstanceConnectPolicy-{self.environment_name}",
            description="Policy for EC2 Instance Connect access",
            statements=[
                # Allow sending SSH public keys to instances
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=["ec2-instance-connect:SendSSHPublicKey"],
                    resources=["*"],
                    conditions={
                        "StringEquals": {
                            "ec2:osuser": "ec2-user"
                        }
                    },
                ),
                # Allow describing instances and VPCs
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "ec2:DescribeInstances",
                        "ec2:DescribeVpcs",
                        "ec2:DescribeInstanceConnectEndpoints",
                    ],
                    resources=["*"],
                ),
            ],
        )

        # Create a restrictive policy for specific instance access
        self.restrictive_instance_connect_policy = iam.ManagedPolicy(
            self,
            "RestrictiveEC2InstanceConnectPolicy",
            managed_policy_name=f"RestrictiveEC2InstanceConnectPolicy-{self.environment_name}",
            description="Restrictive policy for EC2 Instance Connect access to specific instances",
            statements=[
                # Allow describing instances and VPCs (needed for all operations)
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "ec2:DescribeInstances",
                        "ec2:DescribeVpcs",
                        "ec2:DescribeInstanceConnectEndpoints",
                    ],
                    resources=["*"],
                ),
            ],
        )

        # Create IAM user for testing Instance Connect
        self.instance_connect_user = iam.User(
            self,
            "EC2InstanceConnectUser",
            user_name=f"ec2-connect-user-{self.environment_name}",
            managed_policies=[self.instance_connect_policy],
        )

        # Create access key for the user
        self.access_key = iam.AccessKey(
            self,
            "EC2InstanceConnectAccessKey",
            user=self.instance_connect_user,
        )

        # Add tags to IAM resources
        cdk.Tags.of(self.instance_connect_policy).add("Environment", self.environment_name)
        cdk.Tags.of(self.instance_connect_user).add("Environment", self.environment_name)

    def _create_ec2_instances(self) -> None:
        """Create EC2 instances with Instance Connect support."""
        # Get the latest Amazon Linux 2023 AMI
        amazon_linux = ec2.MachineImage.latest_amazon_linux2023(
            edition=ec2.AmazonLinuxEdition.STANDARD,
            virtualization=ec2.AmazonLinuxVirt.HVM,
            storage=ec2.AmazonLinuxStorage.GENERAL_PURPOSE,
        )

        # Create public EC2 instance
        self.public_instance = ec2.Instance(
            self,
            "PublicEC2Instance",
            instance_type=ec2.InstanceType.of(
                ec2.InstanceClass.T3, ec2.InstanceSize.MICRO
            ),
            machine_image=amazon_linux,
            vpc=self.vpc,
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PUBLIC
            ),
            security_group=self.ssh_security_group,
            user_data=self._get_user_data(),
            associate_public_ip_address=True,
        )

        # Create private EC2 instance
        self.private_instance = ec2.Instance(
            self,
            "PrivateEC2Instance",
            instance_type=ec2.InstanceType.of(
                ec2.InstanceClass.T3, ec2.InstanceSize.MICRO
            ),
            machine_image=amazon_linux,
            vpc=self.vpc,
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PRIVATE_ISOLATED
            ),
            security_group=self.ssh_security_group,
            user_data=self._get_user_data(),
            associate_public_ip_address=False,
        )

        # Add tags to instances
        cdk.Tags.of(self.public_instance).add(
            "Name", f"ec2-connect-public-{self.environment_name}"
        )
        cdk.Tags.of(self.public_instance).add("Environment", self.environment_name)
        cdk.Tags.of(self.public_instance).add("Type", "Public")

        cdk.Tags.of(self.private_instance).add(
            "Name", f"ec2-connect-private-{self.environment_name}"
        )
        cdk.Tags.of(self.private_instance).add("Environment", self.environment_name)
        cdk.Tags.of(self.private_instance).add("Type", "Private")

        # Update the restrictive policy to allow access to specific instances
        self.restrictive_instance_connect_policy.add_statements(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["ec2-instance-connect:SendSSHPublicKey"],
                resources=[
                    f"arn:aws:ec2:{self.region}:{self.account}:instance/{self.public_instance.instance_id}",
                    f"arn:aws:ec2:{self.region}:{self.account}:instance/{self.private_instance.instance_id}",
                ],
                conditions={
                    "StringEquals": {
                        "ec2:osuser": "ec2-user"
                    }
                },
            )
        )

    def _get_user_data(self) -> ec2.UserData:
        """
        Get user data script for EC2 instances.

        Returns:
            UserData object with initialization commands
        """
        user_data = ec2.UserData.for_linux()
        
        # Update the system and ensure EC2 Instance Connect is installed
        user_data.add_commands(
            "yum update -y",
            "yum install -y ec2-instance-connect",
            "systemctl enable ec2-instance-connect",
            "systemctl start ec2-instance-connect",
            "echo 'EC2 Instance Connect setup completed' > /var/log/instance-connect-setup.log",
        )
        
        return user_data

    def _create_instance_connect_endpoint(self) -> None:
        """Create EC2 Instance Connect Endpoint for private instance access."""
        # Get the first private subnet
        private_subnets = self.vpc.select_subnets(
            subnet_type=ec2.SubnetType.PRIVATE_ISOLATED
        ).subnets

        if private_subnets:
            # Create Instance Connect Endpoint
            self.instance_connect_endpoint = ec2.CfnInstanceConnectEndpoint(
                self,
                "InstanceConnectEndpoint",
                subnet_id=private_subnets[0].subnet_id,
                security_group_ids=[self.ssh_security_group.security_group_id],
            )

            # Add tags to the endpoint
            cdk.Tags.of(self.instance_connect_endpoint).add(
                "Name", f"ec2-connect-endpoint-{self.environment_name}"
            )
            cdk.Tags.of(self.instance_connect_endpoint).add(
                "Environment", self.environment_name
            )

    def _create_cloudtrail(self) -> None:
        """Create CloudTrail for auditing EC2 Instance Connect activities."""
        # Create S3 bucket for CloudTrail logs
        self.cloudtrail_bucket = s3.Bucket(
            self,
            "CloudTrailBucket",
            bucket_name=f"ec2-connect-cloudtrail-{self.environment_name}-{self.account}",
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteOldLogs",
                    enabled=True,
                    expiration=Duration.days(90),
                )
            ],
        )

        # Create CloudTrail
        self.trail = cloudtrail.Trail(
            self,
            "EC2ConnectCloudTrail",
            trail_name=f"ec2-connect-trail-{self.environment_name}",
            bucket=self.cloudtrail_bucket,
            include_global_service_events=True,
            is_multi_region_trail=True,
            enable_file_validation=True,
        )

        # Add event selectors for EC2 Instance Connect API calls
        self.trail.add_event_selector(
            read_write_type=cloudtrail.ReadWriteType.ALL,
            include_management_events=True,
            data_resource_type=cloudtrail.DataResourceType.S3_OBJECT,
            data_resource_values=["arn:aws:s3:::*/*"],
        )

        # Add tags to CloudTrail resources
        cdk.Tags.of(self.cloudtrail_bucket).add("Environment", self.environment_name)
        cdk.Tags.of(self.trail).add("Environment", self.environment_name)

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs."""
        # VPC and networking outputs
        CfnOutput(
            self,
            "VpcId",
            value=self.vpc.vpc_id,
            description="VPC ID for EC2 Instance Connect demonstration",
        )

        CfnOutput(
            self,
            "SecurityGroupId",
            value=self.ssh_security_group.security_group_id,
            description="Security Group ID for SSH access",
        )

        # EC2 instance outputs
        CfnOutput(
            self,
            "PublicInstanceId",
            value=self.public_instance.instance_id,
            description="Public EC2 Instance ID",
        )

        CfnOutput(
            self,
            "PublicInstancePublicIp",
            value=self.public_instance.instance_public_ip,
            description="Public EC2 Instance Public IP",
        )

        CfnOutput(
            self,
            "PrivateInstanceId",
            value=self.private_instance.instance_id,
            description="Private EC2 Instance ID",
        )

        CfnOutput(
            self,
            "PrivateInstancePrivateIp",
            value=self.private_instance.instance_private_ip,
            description="Private EC2 Instance Private IP",
        )

        # Instance Connect Endpoint output
        if hasattr(self, "instance_connect_endpoint"):
            CfnOutput(
                self,
                "InstanceConnectEndpointId",
                value=self.instance_connect_endpoint.attr_id,
                description="EC2 Instance Connect Endpoint ID",
            )

        # IAM outputs
        CfnOutput(
            self,
            "InstanceConnectPolicyArn",
            value=self.instance_connect_policy.managed_policy_arn,
            description="EC2 Instance Connect IAM Policy ARN",
        )

        CfnOutput(
            self,
            "InstanceConnectUserName",
            value=self.instance_connect_user.user_name,
            description="EC2 Instance Connect IAM User Name",
        )

        CfnOutput(
            self,
            "AccessKeyId",
            value=self.access_key.access_key_id,
            description="Access Key ID for EC2 Instance Connect User",
        )

        CfnOutput(
            self,
            "SecretAccessKey",
            value=self.access_key.secret_access_key.unsafe_unwrap(),
            description="Secret Access Key for EC2 Instance Connect User (Keep Secure!)",
        )

        # CloudTrail outputs
        CfnOutput(
            self,
            "CloudTrailBucketName",
            value=self.cloudtrail_bucket.bucket_name,
            description="S3 Bucket for CloudTrail logs",
        )

        CfnOutput(
            self,
            "CloudTrailArn",
            value=self.trail.trail_arn,
            description="CloudTrail ARN for audit logging",
        )

        # Connection commands
        CfnOutput(
            self,
            "ConnectToPublicInstanceCommand",
            value=f"aws ec2-instance-connect ssh --instance-id {self.public_instance.instance_id} --os-user ec2-user",
            description="Command to connect to public instance via Instance Connect",
        )

        CfnOutput(
            self,
            "ConnectToPrivateInstanceCommand",
            value=f"aws ec2-instance-connect ssh --instance-id {self.private_instance.instance_id} --os-user ec2-user --connection-type eice",
            description="Command to connect to private instance via Instance Connect Endpoint",
        )


# CDK App
app = cdk.App()

# Get environment configuration
environment_name = app.node.try_get_context("environment") or "dev"
aws_account = os.environ.get("CDK_DEFAULT_ACCOUNT")
aws_region = os.environ.get("CDK_DEFAULT_REGION")

# Create the stack
stack = EC2InstanceConnectStack(
    app,
    f"EC2InstanceConnectStack-{environment_name}",
    environment_name=environment_name,
    env=Environment(account=aws_account, region=aws_region),
    description="EC2 Instance Connect secure SSH access demonstration stack",
    tags={
        "Environment": environment_name,
        "Project": "EC2InstanceConnect",
        "ManagedBy": "AWS-CDK",
        "Recipe": "ec2-instance-connect-secure-ssh-access",
    },
)

# Synthesize the app
app.synth()