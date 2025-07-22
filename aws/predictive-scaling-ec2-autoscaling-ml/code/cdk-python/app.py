#!/usr/bin/env python3
"""
CDK Python application for Implementing Predictive Scaling for EC2 with Auto Scaling and Machine Learning.

This application creates:
- VPC with public subnets
- Security group for EC2 instances
- Launch template with user data for demo web server
- Auto Scaling group with predictive and target tracking scaling policies
- CloudWatch dashboard for monitoring
- IAM roles and instance profiles

Author: AWS CDK Generator
Version: 1.0
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Tags,
    aws_ec2 as ec2,
    aws_autoscaling as autoscaling,
    aws_iam as iam,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
)
from constructs import Construct


class PredictiveScalingStack(Stack):
    """Stack for implementing predictive scaling with EC2 Auto Scaling and Machine Learning."""

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Parameters
        self.environment_name = "PredictiveScaling"
        self.instance_type = "t3.micro"
        self.min_capacity = 2
        self.max_capacity = 10
        self.desired_capacity = 2
        self.cpu_target_utilization = 50.0

        # Create VPC and networking components
        self.vpc = self._create_vpc()
        
        # Create security group
        self.security_group = self._create_security_group()
        
        # Create IAM role for EC2 instances
        self.instance_role = self._create_instance_role()
        
        # Create launch template
        self.launch_template = self._create_launch_template()
        
        # Create Auto Scaling group
        self.auto_scaling_group = self._create_auto_scaling_group()
        
        # Create scaling policies
        self._create_scaling_policies()
        
        # Create CloudWatch dashboard
        self._create_dashboard()
        
        # Apply tags
        self._apply_tags()

    def _create_vpc(self) -> ec2.Vpc:
        """Create VPC with public subnets in multiple AZs."""
        vpc = ec2.Vpc(
            self,
            "PredictiveScalingVPC",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=2,
            nat_gateways=0,  # No NAT gateways needed for this demo
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="PublicSubnet",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24,
                )
            ],
            enable_dns_hostnames=True,
            enable_dns_support=True,
        )

        # Add tags to VPC
        Tags.of(vpc).add("Name", f"{self.environment_name}VPC")
        
        return vpc

    def _create_security_group(self) -> ec2.SecurityGroup:
        """Create security group for EC2 instances."""
        security_group = ec2.SecurityGroup(
            self,
            "PredictiveScalingSG",
            vpc=self.vpc,
            description="Security group for Predictive Scaling demo",
            allow_all_outbound=True,
        )

        # Allow HTTP traffic from anywhere
        security_group.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(80),
            description="Allow HTTP traffic",
        )

        # Allow SSH for debugging (optional - you may want to restrict this)
        security_group.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(22),
            description="Allow SSH traffic",
        )

        Tags.of(security_group).add("Name", f"{self.environment_name}SG")
        
        return security_group

    def _create_instance_role(self) -> iam.Role:
        """Create IAM role for EC2 instances with CloudWatch permissions."""
        role = iam.Role(
            self,
            "PredictiveScalingEC2Role",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            description="IAM role for Predictive Scaling EC2 instances",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("CloudWatchAgentServerPolicy"),
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonSSMManagedInstanceCore"),
            ],
        )

        # Create instance profile
        instance_profile = iam.CfnInstanceProfile(
            self,
            "PredictiveScalingInstanceProfile",
            roles=[role.role_name],
            instance_profile_name="PredictiveScalingProfile",
        )

        Tags.of(role).add("Name", f"{self.environment_name}EC2Role")
        
        return role

    def _create_launch_template(self) -> ec2.LaunchTemplate:
        """Create launch template for Auto Scaling group."""
        # Get the latest Amazon Linux 2 AMI
        amzn_linux = ec2.MachineImage.latest_amazon_linux2()

        # User data script for demo web server with CPU load generation
        user_data = ec2.UserData.for_linux()
        user_data.add_commands(
            "yum update -y",
            "yum install -y httpd stress",
            "systemctl start httpd",
            "systemctl enable httpd",
            'echo "<html><body><h1>Predictive Scaling Demo</h1><p>Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)</p><p>Availability Zone: $(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)</p></body></html>" > /var/www/html/index.html',
            "# Create CPU load for demonstration purposes",
            'cat > /etc/cron.d/stress << "END"',
            "# Create CPU load during business hours (8 AM - 8 PM UTC) on weekdays",
            "0 8 * * 1-5 root stress --cpu 2 --timeout 12h",
            "# Create lower CPU load during weekends",
            "0 10 * * 6,0 root stress --cpu 1 --timeout 8h",
            "END",
        )

        launch_template = ec2.LaunchTemplate(
            self,
            "PredictiveScalingTemplate",
            instance_type=ec2.InstanceType(self.instance_type),
            machine_image=amzn_linux,
            security_group=self.security_group,
            user_data=user_data,
            role=self.instance_role,
            detailed_monitoring=True,  # Enable detailed monitoring for better metrics
        )

        Tags.of(launch_template).add("Name", f"{self.environment_name}LaunchTemplate")
        
        return launch_template

    def _create_auto_scaling_group(self) -> autoscaling.AutoScalingGroup:
        """Create Auto Scaling group with the launch template."""
        auto_scaling_group = autoscaling.AutoScalingGroup(
            self,
            "PredictiveScalingASG",
            vpc=self.vpc,
            launch_template=self.launch_template,
            min_capacity=self.min_capacity,
            max_capacity=self.max_capacity,
            desired_capacity=self.desired_capacity,
            vpc_subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PUBLIC),
            health_check=autoscaling.HealthCheck.ec2(grace=cdk.Duration.seconds(300)),
            default_instance_warmup=cdk.Duration.seconds(300),  # Critical for predictive scaling
            signals=autoscaling.Signals.wait_for_capacity_timeout(
                timeout=cdk.Duration.minutes(10)
            ),
        )

        # Add tags to instances launched by ASG
        auto_scaling_group.node.add_metadata("CreatedBy", "CDK-PredictiveScaling")
        Tags.of(auto_scaling_group).add("Environment", "Production")
        Tags.of(auto_scaling_group).add("Application", "PredictiveScalingDemo")
        
        return auto_scaling_group

    def _create_scaling_policies(self) -> None:
        """Create both target tracking and predictive scaling policies."""
        # Target tracking scaling policy for reactive scaling
        target_tracking_policy = autoscaling.TargetTrackingScalingPolicy(
            self,
            "CPUTargetTrackingPolicy",
            auto_scaling_group=self.auto_scaling_group,
            target_value=self.cpu_target_utilization,
            predefined_metric=autoscaling.PredefinedMetric.ASG_AVERAGE_CPU_UTILIZATION,
            disable_scale_in=False,
            cooldown=cdk.Duration.seconds(300),
        )

        # Predictive scaling policy using CDK escape hatch (L1 construct)
        # Note: CDK doesn't yet have L2 constructs for predictive scaling
        predictive_scaling_policy = autoscaling.CfnScalingPolicy(
            self,
            "PredictiveScalingPolicy",
            auto_scaling_group_name=self.auto_scaling_group.auto_scaling_group_name,
            policy_type="PredictiveScaling",
            predictive_scaling_configuration=autoscaling.CfnScalingPolicy.PredictiveScalingConfigurationProperty(
                metric_specifications=[
                    autoscaling.CfnScalingPolicy.PredictiveScalingMetricSpecificationProperty(
                        target_value=self.cpu_target_utilization,
                        predefined_metric_pair_specification=autoscaling.CfnScalingPolicy.PredictiveScalingPredefinedMetricPairProperty(
                            predefined_metric_type="ASGCPUUtilization"
                        ),
                    )
                ],
                mode="ForecastOnly",  # Start in forecast-only mode for evaluation
                scheduling_buffer_time=300,  # 5 minutes buffer for instance launch
                max_capacity_breach_behavior="IncreaseMaxCapacity",
                max_capacity_buffer=10,  # Allow up to 10 instances beyond max capacity
            ),
        )

        # Output the policy ARNs for reference
        cdk.CfnOutput(
            self,
            "TargetTrackingPolicyARN",
            value=target_tracking_policy.scaling_policy_arn,
            description="ARN of the target tracking scaling policy",
        )

        cdk.CfnOutput(
            self,
            "PredictiveScalingPolicyARN",
            value=predictive_scaling_policy.ref,
            description="ARN of the predictive scaling policy",
        )

    def _create_dashboard(self) -> cloudwatch.Dashboard:
        """Create CloudWatch dashboard for monitoring predictive scaling."""
        dashboard = cloudwatch.Dashboard(
            self,
            "PredictiveScalingDashboard",
            dashboard_name="PredictiveScalingDashboard",
        )

        # CPU Utilization widget
        cpu_widget = cloudwatch.GraphWidget(
            title="ASG CPU Utilization",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/EC2",
                    metric_name="CPUUtilization",
                    dimensions_map={
                        "AutoScalingGroupName": self.auto_scaling_group.auto_scaling_group_name
                    },
                    statistic="Average",
                    period=cdk.Duration.minutes(5),
                )
            ],
            width=12,
            height=6,
        )

        # Instance count widget
        instance_widget = cloudwatch.GraphWidget(
            title="ASG Instance Count",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/AutoScaling",
                    metric_name="GroupInServiceInstances",
                    dimensions_map={
                        "AutoScalingGroupName": self.auto_scaling_group.auto_scaling_group_name
                    },
                    statistic="Average",
                    period=cdk.Duration.minutes(5),
                )
            ],
            width=12,
            height=6,
        )

        # Desired capacity widget
        desired_capacity_widget = cloudwatch.GraphWidget(
            title="ASG Desired Capacity",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/AutoScaling",
                    metric_name="GroupDesiredCapacity",
                    dimensions_map={
                        "AutoScalingGroupName": self.auto_scaling_group.auto_scaling_group_name
                    },
                    statistic="Average",
                    period=cdk.Duration.minutes(5),
                )
            ],
            width=12,
            height=6,
        )

        # Network I/O widget
        network_widget = cloudwatch.GraphWidget(
            title="Network I/O",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/EC2",
                    metric_name="NetworkIn",
                    dimensions_map={
                        "AutoScalingGroupName": self.auto_scaling_group.auto_scaling_group_name
                    },
                    statistic="Sum",
                    period=cdk.Duration.minutes(5),
                ),
                cloudwatch.Metric(
                    namespace="AWS/EC2",
                    metric_name="NetworkOut",
                    dimensions_map={
                        "AutoScalingGroupName": self.auto_scaling_group.auto_scaling_group_name
                    },
                    statistic="Sum",
                    period=cdk.Duration.minutes(5),
                ),
            ],
            width=12,
            height=6,
        )

        # Add widgets to dashboard
        dashboard.add_widgets(cpu_widget, instance_widget)
        dashboard.add_widgets(desired_capacity_widget, network_widget)

        # Output dashboard URL
        cdk.CfnOutput(
            self,
            "DashboardURL",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name=PredictiveScalingDashboard",
            description="URL to the CloudWatch dashboard",
        )

        return dashboard

    def _apply_tags(self) -> None:
        """Apply tags to all resources in the stack."""
        Tags.of(self).add("Project", "PredictiveScaling")
        Tags.of(self).add("Environment", "Demo")
        Tags.of(self).add("ManagedBy", "CDK")
        Tags.of(self).add("Recipe", "predictive-scaling-ec2-autoscaling-machine-learning")


class PredictiveScalingApp(cdk.App):
    """CDK Application for Predictive Scaling demo."""

    def __init__(self) -> None:
        super().__init__()

        # Get environment configuration
        env = cdk.Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
        )

        # Create the stack
        PredictiveScalingStack(
            self,
            "PredictiveScalingStack",
            env=env,
            description="Stack for implementing predictive scaling with EC2 Auto Scaling and Machine Learning",
        )


if __name__ == "__main__":
    app = PredictiveScalingApp()
    app.synth()