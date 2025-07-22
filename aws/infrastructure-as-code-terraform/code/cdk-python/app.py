#!/usr/bin/env python3
"""
AWS CDK Python Application for Infrastructure as Code Demo

This CDK application demonstrates enterprise-grade infrastructure as code practices
by creating a scalable web application architecture with VPC, Auto Scaling Groups,
Application Load Balancer, and proper security controls.

The application consists of:
- Custom VPC with public subnets across multiple AZs
- Application Load Balancer for high availability
- Auto Scaling Group with launch template
- Security groups with least privilege access
- Proper tagging strategy for resource management
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    Tags,
    aws_ec2 as ec2,
    aws_autoscaling as autoscaling,
    aws_elasticloadbalancingv2 as elbv2,
    aws_iam as iam,
    CfnOutput,
    Duration,
)
from constructs import Construct
from typing import Dict, Any
import os


class InfrastructureAsCodeStack(Stack):
    """
    Main CDK Stack for Infrastructure as Code Demo
    
    Creates a complete web application infrastructure including:
    - VPC with public subnets
    - Application Load Balancer
    - Auto Scaling Group
    - Security Groups
    - IAM roles and policies
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Configuration parameters
        self.project_name = self.node.try_get_context("project_name") or "terraform-iac-demo"
        self.environment_name = self.node.try_get_context("environment") or "dev"
        self.instance_type = self.node.try_get_context("instance_type") or "t3.micro"
        self.vpc_cidr = self.node.try_get_context("vpc_cidr") or "10.0.0.0/16"

        # Create VPC with public subnets
        self.vpc = self._create_vpc()
        
        # Create security groups
        self.web_security_group = self._create_security_groups()
        
        # Create IAM role for EC2 instances
        self.instance_role = self._create_instance_role()
        
        # Create Application Load Balancer
        self.alb = self._create_application_load_balancer()
        
        # Create Auto Scaling Group
        self.asg = self._create_auto_scaling_group()
        
        # Create CloudFormation outputs
        self._create_outputs()

    def _create_vpc(self) -> ec2.Vpc:
        """
        Create a VPC with public subnets across multiple availability zones
        
        Returns:
            ec2.Vpc: The created VPC with public subnets
        """
        vpc = ec2.Vpc(
            self, "VPC",
            vpc_name=f"{self.project_name}-vpc",
            ip_addresses=ec2.IpAddresses.cidr(self.vpc_cidr),
            max_azs=2,  # Use 2 AZs for high availability
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="Public",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24,  # /24 subnets (256 IPs each)
                )
            ],
            enable_dns_hostnames=True,
            enable_dns_support=True,
        )

        # Add tags to VPC
        Tags.of(vpc).add("Name", f"{self.project_name}-vpc")
        Tags.of(vpc).add("Environment", self.environment_name)

        return vpc

    def _create_security_groups(self) -> ec2.SecurityGroup:
        """
        Create security groups for web servers with least privilege access
        
        Returns:
            ec2.SecurityGroup: Security group for web servers
        """
        web_sg = ec2.SecurityGroup(
            self, "WebSecurityGroup",
            vpc=self.vpc,
            description="Security group for web servers",
            security_group_name=f"{self.project_name}-web-sg",
            allow_all_outbound=True,
        )

        # Allow HTTP traffic from anywhere
        web_sg.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(80),
            description="Allow HTTP traffic from anywhere"
        )

        # Allow HTTPS traffic from anywhere
        web_sg.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(443),
            description="Allow HTTPS traffic from anywhere"
        )

        # Add tags
        Tags.of(web_sg).add("Name", f"{self.project_name}-web-sg")
        Tags.of(web_sg).add("Environment", self.environment_name)

        return web_sg

    def _create_instance_role(self) -> iam.Role:
        """
        Create IAM role for EC2 instances with necessary permissions
        
        Returns:
            iam.Role: IAM role for EC2 instances
        """
        role = iam.Role(
            self, "InstanceRole",
            role_name=f"{self.project_name}-instance-role",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            description="IAM role for web server instances",
        )

        # Add managed policy for SSM access (for better management)
        role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name("AmazonSSMManagedInstanceCore")
        )

        # Add CloudWatch agent permissions
        role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name("CloudWatchAgentServerPolicy")
        )

        # Add tags
        Tags.of(role).add("Name", f"{self.project_name}-instance-role")
        Tags.of(role).add("Environment", self.environment_name)

        return role

    def _create_application_load_balancer(self) -> elbv2.ApplicationLoadBalancer:
        """
        Create Application Load Balancer with target group and listener
        
        Returns:
            elbv2.ApplicationLoadBalancer: The created ALB
        """
        # Create Application Load Balancer
        alb = elbv2.ApplicationLoadBalancer(
            self, "ApplicationLoadBalancer",
            vpc=self.vpc,
            internet_facing=True,
            load_balancer_name=f"{self.project_name}-web-alb",
            security_group=self.web_security_group,
            vpc_subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PUBLIC),
        )

        # Create target group for web servers
        self.target_group = elbv2.ApplicationTargetGroup(
            self, "WebTargetGroup",
            target_group_name=f"{self.project_name}-web-tg",
            port=80,
            protocol=elbv2.ApplicationProtocol.HTTP,
            vpc=self.vpc,
            target_type=elbv2.TargetType.INSTANCE,
            health_check=elbv2.HealthCheck(
                enabled=True,
                healthy_threshold_count=2,
                unhealthy_threshold_count=2,
                timeout=Duration.seconds(5),
                interval=Duration.seconds(30),
                path="/",
                port="traffic-port",
                protocol=elbv2.Protocol.HTTP,
            ),
        )

        # Create listener
        alb.add_listener(
            "WebListener",
            port=80,
            protocol=elbv2.ApplicationProtocol.HTTP,
            default_target_groups=[self.target_group],
        )

        # Add tags
        Tags.of(alb).add("Name", f"{self.project_name}-web-alb")
        Tags.of(alb).add("Environment", self.environment_name)

        return alb

    def _create_auto_scaling_group(self) -> autoscaling.AutoScalingGroup:
        """
        Create Auto Scaling Group with launch template for web servers
        
        Returns:
            autoscaling.AutoScalingGroup: The created Auto Scaling Group
        """
        # Get latest Amazon Linux 2 AMI
        amazon_linux = ec2.MachineImage.latest_amazon_linux2(
            edition=ec2.AmazonLinuxEdition.STANDARD,
            virtualization=ec2.AmazonLinuxVirt.HVM,
            storage=ec2.AmazonLinuxStorage.GENERAL_PURPOSE,
        )

        # User data script to install and configure web server
        user_data = ec2.UserData.for_linux()
        user_data.add_commands(
            "#!/bin/bash",
            "yum update -y",
            "yum install -y httpd",
            "systemctl start httpd",
            "systemctl enable httpd",
            'echo "<h1>Hello from CDK Python!</h1>" > /var/www/html/index.html',
            'echo "<p>Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)</p>" >> /var/www/html/index.html',
            'echo "<p>Availability Zone: $(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)</p>" >> /var/www/html/index.html',
        )

        # Create Auto Scaling Group
        asg = autoscaling.AutoScalingGroup(
            self, "WebAutoScalingGroup",
            vpc=self.vpc,
            instance_type=ec2.InstanceType(self.instance_type),
            machine_image=amazon_linux,
            user_data=user_data,
            role=self.instance_role,
            security_group=self.web_security_group,
            vpc_subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PUBLIC),
            min_capacity=2,
            max_capacity=4,
            desired_capacity=2,
            health_check=autoscaling.HealthCheck.elb(grace=Duration.seconds(300)),
            auto_scaling_group_name=f"{self.project_name}-web-asg",
        )

        # Attach Auto Scaling Group to target group
        asg.attach_to_application_target_group(self.target_group)

        # Add scaling policies
        asg.scale_on_cpu_utilization(
            "CpuScaling",
            target_utilization_percent=70,
            scale_in_cooldown=Duration.seconds(300),
            scale_out_cooldown=Duration.seconds(300),
        )

        # Add tags
        Tags.of(asg).add("Name", f"{self.project_name}-web-asg")
        Tags.of(asg).add("Environment", self.environment_name)

        return asg

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key infrastructure components"""
        
        CfnOutput(
            self, "VpcId",
            value=self.vpc.vpc_id,
            description="ID of the VPC",
            export_name=f"{self.stack_name}-VpcId",
        )

        CfnOutput(
            self, "PublicSubnetIds",
            value=",".join([subnet.subnet_id for subnet in self.vpc.public_subnets]),
            description="IDs of public subnets",
            export_name=f"{self.stack_name}-PublicSubnetIds",
        )

        CfnOutput(
            self, "AlbDnsName",
            value=self.alb.load_balancer_dns_name,
            description="DNS name of the Application Load Balancer",
            export_name=f"{self.stack_name}-AlbDnsName",
        )

        CfnOutput(
            self, "AlbArn",
            value=self.alb.load_balancer_arn,
            description="ARN of the Application Load Balancer",
            export_name=f"{self.stack_name}-AlbArn",
        )

        CfnOutput(
            self, "AutoScalingGroupName",
            value=self.asg.auto_scaling_group_name,
            description="Name of the Auto Scaling Group",
            export_name=f"{self.stack_name}-AutoScalingGroupName",
        )

        CfnOutput(
            self, "WebUrl",
            value=f"http://{self.alb.load_balancer_dns_name}",
            description="URL of the web application",
            export_name=f"{self.stack_name}-WebUrl",
        )


def main() -> None:
    """
    Main function to create and deploy the CDK application
    """
    app = cdk.App()
    
    # Get configuration from context or environment variables
    env = Environment(
        account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
        region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
    )
    
    # Create the stack
    stack = InfrastructureAsCodeStack(
        app, 
        "InfrastructureAsCodeStack",
        env=env,
        description="Infrastructure as Code demo using AWS CDK Python - VPC, ALB, and Auto Scaling Group",
    )
    
    # Add global tags
    Tags.of(stack).add("Project", "terraform-iac-demo")
    Tags.of(stack).add("ManagedBy", "cdk")
    Tags.of(stack).add("Repository", "cloud-recipes")
    
    app.synth()


if __name__ == "__main__":
    main()