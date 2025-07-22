#!/usr/bin/env python3
"""
CDK Application for Secure EC2 Management with Systems Manager

This CDK application creates a secure EC2 instance management solution using AWS Systems Manager.
It demonstrates how to eliminate SSH access while maintaining full management capabilities through
Session Manager and Run Command.

Author: Recipe Generator v1.3
Last Updated: 2025-07-12
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_ec2 as ec2,
    aws_iam as iam,
    aws_logs as logs,
    aws_ssm as ssm,
    RemovalPolicy,
    CfnOutput,
    Tags,
)
from constructs import Construct
from typing import Dict, List, Optional


class SecureSystemsManagerStack(Stack):
    """
    Stack for creating secure EC2 instance management with AWS Systems Manager.
    
    This stack creates:
    - VPC with public subnet for EC2 instance
    - IAM role with Systems Manager permissions
    - Security group with no inbound access
    - EC2 instance with SSM agent
    - CloudWatch log group for session logging
    - Session Manager configuration for audit logging
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        instance_type: str = "t3.micro",
        os_type: str = "amazon-linux",
        enable_session_logging: bool = True,
        **kwargs
    ) -> None:
        """
        Initialize the SecureSystemsManagerStack.

        Args:
            scope: CDK app or parent construct
            construct_id: Unique identifier for this stack
            instance_type: EC2 instance type (default: t3.micro)
            os_type: Operating system type ('amazon-linux' or 'ubuntu')
            enable_session_logging: Whether to enable session logging to CloudWatch
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)

        # Get context values for customization
        self.instance_type = instance_type
        self.os_type = os_type
        self.enable_session_logging = enable_session_logging

        # Create VPC and networking components
        self._create_vpc()
        
        # Create IAM role for EC2 instance
        self._create_iam_role()
        
        # Create security group
        self._create_security_group()
        
        # Create EC2 instance
        self._create_ec2_instance()
        
        # Configure session logging if enabled
        if self.enable_session_logging:
            self._create_session_logging()
        
        # Create outputs
        self._create_outputs()
        
        # Add tags to all resources
        self._add_tags()

    def _create_vpc(self) -> None:
        """Create VPC with public subnet for EC2 instance."""
        self.vpc = ec2.Vpc(
            self,
            "SecureVPC",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=2,
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="PublicSubnet",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24,
                )
            ],
            nat_gateways=0,  # No NAT gateway needed for this demo
            enable_dns_hostnames=True,
            enable_dns_support=True,
        )

    def _create_iam_role(self) -> None:
        """Create IAM role with Systems Manager permissions for EC2 instance."""
        # Create IAM role for EC2 instance
        self.instance_role = iam.Role(
            self,
            "SSMInstanceRole",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            description="IAM role for EC2 instance with Systems Manager access",
            managed_policies=[
                # AWS managed policy for Systems Manager core functionality
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonSSMManagedInstanceCore"),
                # Additional policy for CloudWatch Logs access (for session logging)
                iam.ManagedPolicy.from_aws_managed_policy_name("CloudWatchAgentServerPolicy"),
            ],
        )

        # Add inline policy for additional Systems Manager permissions
        self.instance_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "ssm:UpdateInstanceInformation",
                    "ssm:SendCommand",
                    "ssm:ListCommands",
                    "ssm:ListCommandInvocations",
                    "ssm:DescribeInstanceInformation",
                    "ssm:GetConnectionStatus",
                ],
                resources=["*"],
            )
        )

        # Create instance profile
        self.instance_profile = iam.CfnInstanceProfile(
            self,
            "SSMInstanceProfile",
            roles=[self.instance_role.role_name],
            instance_profile_name=f"SSMInstanceProfile-{self.stack_name}",
        )

    def _create_security_group(self) -> None:
        """Create security group that blocks all inbound traffic."""
        self.security_group = ec2.SecurityGroup(
            self,
            "SSMSecurityGroup",
            vpc=self.vpc,
            description="Security group for SSM managed instance - no inbound access",
            allow_all_outbound=True,  # Allow outbound traffic for Systems Manager communication
        )

        # Explicitly allow HTTPS outbound for Systems Manager communication
        self.security_group.add_egress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(443),
            description="HTTPS outbound for Systems Manager communication",
        )

        # Allow HTTP outbound for package updates and web server testing
        self.security_group.add_egress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(80),
            description="HTTP outbound for package updates",
        )

        # Allow DNS outbound
        self.security_group.add_egress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(53),
            description="DNS outbound",
        )
        self.security_group.add_egress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.udp(53),
            description="DNS outbound",
        )

    def _get_ami_id(self) -> ec2.IMachineImage:
        """Get the appropriate AMI based on OS type."""
        if self.os_type == "ubuntu":
            # Ubuntu 22.04 LTS
            return ec2.MachineImage.from_ssm_parameter(
                "/aws/service/canonical/ubuntu/server/22.04/stable/current/amd64/hvm/ebs-gp2/ami-id",
                os=ec2.OperatingSystemType.LINUX,
            )
        else:
            # Amazon Linux 2023 (default)
            return ec2.MachineImage.from_ssm_parameter(
                "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64",
                os=ec2.OperatingSystemType.LINUX,
            )

    def _create_ec2_instance(self) -> None:
        """Create EC2 instance with Systems Manager agent."""
        # Get AMI based on OS type
        ami = self._get_ami_id()

        # User data script to ensure SSM agent is running and install nginx
        user_data_script = ec2.UserData.for_linux()
        
        if self.os_type == "ubuntu":
            user_data_script.add_commands(
                "#!/bin/bash",
                "# Update package manager",
                "apt-get update -y",
                "",
                "# Install and start SSM agent (pre-installed on Ubuntu 22.04)",
                "systemctl enable amazon-ssm-agent",
                "systemctl start amazon-ssm-agent",
                "",
                "# Install nginx web server for testing",
                "apt-get install -y nginx",
                "systemctl enable nginx",
                "systemctl start nginx",
                "",
                "# Create custom index page",
                "cat > /var/www/html/index.html << 'EOF'",
                "<html>",
                "<head><title>Secure Systems Manager Demo</title></head>",
                "<body>",
                "<h1>Hello from AWS Systems Manager!</h1>",
                "<p>This server is managed securely without SSH access.</p>",
                "<p>Operating System: Ubuntu 22.04 LTS</p>",
                "<p>Instance managed via AWS Systems Manager Session Manager</p>",
                "</body>",
                "</html>",
                "EOF",
            )
        else:
            user_data_script.add_commands(
                "#!/bin/bash",
                "# Update package manager",
                "dnf update -y",
                "",
                "# Install and start SSM agent (pre-installed on Amazon Linux 2023)",
                "systemctl enable amazon-ssm-agent",
                "systemctl start amazon-ssm-agent",
                "",
                "# Install nginx web server for testing",
                "dnf install -y nginx",
                "systemctl enable nginx",
                "systemctl start nginx",
                "",
                "# Create custom index page",
                "cat > /usr/share/nginx/html/index.html << 'EOF'",
                "<html>",
                "<head><title>Secure Systems Manager Demo</title></head>",
                "<body>",
                "<h1>Hello from AWS Systems Manager!</h1>",
                "<p>This server is managed securely without SSH access.</p>",
                "<p>Operating System: Amazon Linux 2023</p>",
                "<p>Instance managed via AWS Systems Manager Session Manager</p>",
                "</body>",
                "</html>",
                "EOF",
            )

        # Create EC2 instance
        self.instance = ec2.Instance(
            self,
            "SecureInstance",
            instance_type=ec2.InstanceType(self.instance_type),
            machine_image=ami,
            vpc=self.vpc,
            vpc_subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PUBLIC),
            security_group=self.security_group,
            role=self.instance_role,
            user_data=user_data_script,
            detailed_monitoring=True,  # Enable detailed monitoring for better observability
        )

        # Add instance name tag
        Tags.of(self.instance).add("Name", f"SecureSSMInstance-{self.stack_name}")

    def _create_session_logging(self) -> None:
        """Create CloudWatch log group and configure session logging."""
        # Create CloudWatch log group for session logs
        self.log_group = logs.LogGroup(
            self,
            "SessionLogGroup",
            log_group_name=f"/aws/ssm/sessions/{self.stack_name}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY,
        )

        # Create Session Manager document for logging configuration
        self.session_document = ssm.CfnDocument(
            self,
            "SessionManagerDocument",
            document_type="Session",
            document_format="JSON",
            content={
                "schemaVersion": "1.0",
                "description": "Document to hold regional settings for Session Manager",
                "sessionType": "Standard_Stream",
                "inputs": {
                    "s3BucketName": "",
                    "s3KeyPrefix": "",
                    "s3EncryptionEnabled": True,
                    "cloudWatchLogGroupName": self.log_group.log_group_name,
                    "cloudWatchEncryptionEnabled": False,
                    "idleSessionTimeout": "20",
                    "maxSessionDuration": "60",
                    "runAsEnabled": False,
                    "runAsDefaultUser": "",
                    "shellProfile": {
                        "linux": "cd /home && pwd",
                        "windows": "cd C:\\Users && dir"
                    }
                }
            },
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources."""
        CfnOutput(
            self,
            "InstanceId",
            value=self.instance.instance_id,
            description="EC2 Instance ID",
            export_name=f"{self.stack_name}-InstanceId",
        )

        CfnOutput(
            self,
            "InstancePrivateIP",
            value=self.instance.instance_private_ip,
            description="EC2 Instance Private IP",
            export_name=f"{self.stack_name}-InstancePrivateIP",
        )

        CfnOutput(
            self,
            "InstancePublicIP",
            value=self.instance.instance_public_ip,
            description="EC2 Instance Public IP (for web server testing)",
            export_name=f"{self.stack_name}-InstancePublicIP",
        )

        CfnOutput(
            self,
            "SessionManagerCommand",
            value=f"aws ssm start-session --target {self.instance.instance_id}",
            description="Command to start Session Manager session",
        )

        CfnOutput(
            self,
            "SecurityGroupId",
            value=self.security_group.security_group_id,
            description="Security Group ID",
            export_name=f"{self.stack_name}-SecurityGroupId",
        )

        CfnOutput(
            self,
            "IAMRoleArn",
            value=self.instance_role.role_arn,
            description="IAM Role ARN for the EC2 instance",
            export_name=f"{self.stack_name}-IAMRoleArn",
        )

        if self.enable_session_logging:
            CfnOutput(
                self,
                "LogGroupName",
                value=self.log_group.log_group_name,
                description="CloudWatch Log Group for session logging",
                export_name=f"{self.stack_name}-LogGroupName",
            )

            CfnOutput(
                self,
                "LogGroupURL",
                value=f"https://console.aws.amazon.com/cloudwatch/home?region={self.region}#logsV2:log-groups/log-group/{self.log_group.log_group_name.replace('/', '%2F')}",
                description="URL to view session logs in CloudWatch",
            )

    def _add_tags(self) -> None:
        """Add common tags to all resources in the stack."""
        Tags.of(self).add("Project", "SecureSystemsManagerDemo")
        Tags.of(self).add("Purpose", "EC2 Instance Management without SSH")
        Tags.of(self).add("CostCenter", "Development")
        Tags.of(self).add("Environment", "Demo")


class SecureSystemsManagerApp(cdk.App):
    """CDK Application for Secure Systems Manager demo."""

    def __init__(self) -> None:
        """Initialize the CDK application."""
        super().__init__()

        # Get context values for customization
        instance_type = self.node.try_get_context("instance_type") or "t3.micro"
        os_type = self.node.try_get_context("os_type") or "amazon-linux"
        enable_session_logging = self.node.try_get_context("enable_session_logging")
        if enable_session_logging is None:
            enable_session_logging = True

        # Create the main stack
        SecureSystemsManagerStack(
            self,
            "SecureSystemsManagerStack",
            instance_type=instance_type,
            os_type=os_type,
            enable_session_logging=enable_session_logging,
            description="Secure EC2 instance management with AWS Systems Manager - no SSH required",
        )


# Create and run the application
app = SecureSystemsManagerApp()
app.synth()