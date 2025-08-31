#!/usr/bin/env python3

"""
CDK Python application for EC2 Launch Templates with Auto Scaling.

This application demonstrates how to create reusable EC2 launch templates
and configure Auto Scaling groups to automatically manage instance capacity
based on CloudWatch metrics.
"""

import aws_cdk as cdk
from aws_cdk import (
    Duration,
    Stack,
    aws_ec2 as ec2,
    aws_autoscaling as autoscaling,
    aws_cloudwatch as cloudwatch,
    CfnOutput,
)
from constructs import Construct
from typing import List, Dict, Any


class Ec2LaunchTemplateAutoScalingStack(Stack):
    """
    CDK Stack for EC2 Launch Templates with Auto Scaling.
    
    This stack creates:
    - Security group for EC2 instances
    - Launch template with UserData for web server setup
    - Auto Scaling group with target tracking scaling policy
    - CloudWatch metrics collection
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Get default VPC
        vpc = ec2.Vpc.from_lookup(self, "DefaultVpc", is_default=True)

        # Create security group for EC2 instances
        security_group = self._create_security_group(vpc)

        # Get latest Amazon Linux 2 AMI
        ami = ec2.MachineImage.latest_amazon_linux2()

        # Create launch template
        launch_template = self._create_launch_template(
            security_group=security_group,
            ami=ami
        )

        # Create Auto Scaling group
        auto_scaling_group = self._create_auto_scaling_group(
            vpc=vpc,
            launch_template=launch_template
        )

        # Create target tracking scaling policy
        self._create_scaling_policy(auto_scaling_group)

        # Enable CloudWatch metrics
        self._enable_cloudwatch_metrics(auto_scaling_group)

        # Create outputs
        self._create_outputs(
            security_group=security_group,
            launch_template=launch_template,
            auto_scaling_group=auto_scaling_group
        )

    def _create_security_group(self, vpc: ec2.IVpc) -> ec2.SecurityGroup:
        """
        Create security group for EC2 instances.
        
        Args:
            vpc: The VPC to create the security group in
            
        Returns:
            The created security group
        """
        security_group = ec2.SecurityGroup(
            self,
            "AutoScalingSecurityGroup",
            vpc=vpc,
            description="Security group for Auto Scaling demo instances",
            security_group_name="demo-autoscaling-sg",
            allow_all_outbound=True
        )

        # Allow HTTP traffic from anywhere
        security_group.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(80),
            description="Allow HTTP traffic"
        )

        # Allow SSH access from anywhere (consider restricting in production)
        security_group.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(22),
            description="Allow SSH access"
        )

        return security_group

    def _create_launch_template(
        self,
        security_group: ec2.SecurityGroup,
        ami: ec2.IMachineImage
    ) -> ec2.LaunchTemplate:
        """
        Create launch template with UserData for web server setup.
        
        Args:
            security_group: Security group to assign to instances
            ami: Amazon Machine Image to use
            
        Returns:
            The created launch template
        """
        # UserData script to install and configure Apache web server
        user_data = ec2.UserData.for_linux()
        user_data.add_commands(
            "#!/bin/bash",
            "yum update -y",
            "yum install -y httpd",
            "systemctl start httpd",
            "systemctl enable httpd",
            'echo "<h1>Hello from $(hostname -f)</h1>" > /var/www/html/index.html',
            'echo "<p>Instance launched at $(date)</p>" >> /var/www/html/index.html',
            'echo "<p>Auto Scaling Demo</p>" >> /var/www/html/index.html'
        )

        launch_template = ec2.LaunchTemplate(
            self,
            "AutoScalingLaunchTemplate",
            launch_template_name="demo-launch-template",
            machine_image=ami,
            instance_type=ec2.InstanceType.of(
                ec2.InstanceClass.T2,
                ec2.InstanceSize.MICRO
            ),
            security_group=security_group,
            user_data=user_data,
            detailed_monitoring=True,  # Enable detailed CloudWatch monitoring
        )

        # Add tags to the launch template
        cdk.Tags.of(launch_template).add("Name", "AutoScaling-LaunchTemplate")
        cdk.Tags.of(launch_template).add("Environment", "Demo")
        cdk.Tags.of(launch_template).add("Purpose", "AutoScaling-Demo")

        return launch_template

    def _create_auto_scaling_group(
        self,
        vpc: ec2.IVpc,
        launch_template: ec2.LaunchTemplate
    ) -> autoscaling.AutoScalingGroup:
        """
        Create Auto Scaling group with launch template.
        
        Args:
            vpc: The VPC to create the Auto Scaling group in
            launch_template: Launch template to use for instances
            
        Returns:
            The created Auto Scaling group
        """
        auto_scaling_group = autoscaling.AutoScalingGroup(
            self,
            "DemoAutoScalingGroup",
            vpc=vpc,
            launch_template=launch_template,
            min_capacity=1,
            max_capacity=4,
            desired_capacity=2,
            health_check=autoscaling.HealthCheck.ec2(
                grace=Duration.minutes(5)
            ),
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PUBLIC
            ),
            auto_scaling_group_name="demo-auto-scaling-group"
        )

        # Add tags to instances launched by Auto Scaling group
        cdk.Tags.of(auto_scaling_group).add("Name", "AutoScaling-Instance")
        cdk.Tags.of(auto_scaling_group).add("Environment", "Demo")
        cdk.Tags.of(auto_scaling_group).add("ManagedBy", "AutoScaling")

        return auto_scaling_group

    def _create_scaling_policy(
        self,
        auto_scaling_group: autoscaling.AutoScalingGroup
    ) -> None:
        """
        Create target tracking scaling policy for CPU utilization.
        
        Args:
            auto_scaling_group: The Auto Scaling group to attach the policy to
        """
        # Create target tracking scaling policy for CPU utilization
        auto_scaling_group.scale_on_cpu_utilization(
            "CpuTargetTrackingPolicy",
            target_utilization_percent=70,
            scale_in_cooldown=Duration.minutes(5),
            scale_out_cooldown=Duration.minutes(5)
        )

    def _enable_cloudwatch_metrics(
        self,
        auto_scaling_group: autoscaling.AutoScalingGroup
    ) -> None:
        """
        Enable CloudWatch metrics collection for Auto Scaling group.
        
        Args:
            auto_scaling_group: The Auto Scaling group to enable metrics for
        """
        # Enable detailed CloudWatch metrics
        # Note: CDK automatically enables basic metrics for Auto Scaling groups
        # Additional custom metrics can be added here if needed
        pass

    def _create_outputs(
        self,
        security_group: ec2.SecurityGroup,
        launch_template: ec2.LaunchTemplate,
        auto_scaling_group: autoscaling.AutoScalingGroup
    ) -> None:
        """
        Create CloudFormation outputs for important resource information.
        
        Args:
            security_group: The security group created
            launch_template: The launch template created
            auto_scaling_group: The Auto Scaling group created
        """
        CfnOutput(
            self,
            "SecurityGroupId",
            value=security_group.security_group_id,
            description="ID of the security group for Auto Scaling instances"
        )

        CfnOutput(
            self,
            "LaunchTemplateId",
            value=launch_template.launch_template_id or "",
            description="ID of the launch template"
        )

        CfnOutput(
            self,
            "LaunchTemplateName",
            value=launch_template.launch_template_name or "",
            description="Name of the launch template"
        )

        CfnOutput(
            self,
            "AutoScalingGroupName",
            value=auto_scaling_group.auto_scaling_group_name,
            description="Name of the Auto Scaling group"
        )

        CfnOutput(
            self,
            "AutoScalingGroupArn",
            value=auto_scaling_group.auto_scaling_group_arn,
            description="ARN of the Auto Scaling group"
        )


class Ec2LaunchTemplateAutoScalingApp(cdk.App):
    """CDK Application for EC2 Launch Templates with Auto Scaling."""

    def __init__(self) -> None:
        super().__init__()

        # Create the main stack
        Ec2LaunchTemplateAutoScalingStack(
            self,
            "Ec2LaunchTemplateAutoScalingStack",
            description="EC2 Launch Templates with Auto Scaling demonstration stack",
            env=cdk.Environment(
                account=self.node.try_get_context("account"),
                region=self.node.try_get_context("region")
            )
        )


def main() -> None:
    """Main entry point for the CDK application."""
    app = Ec2LaunchTemplateAutoScalingApp()
    
    # Synthesize the CloudFormation template
    app.synth()


if __name__ == "__main__":
    main()