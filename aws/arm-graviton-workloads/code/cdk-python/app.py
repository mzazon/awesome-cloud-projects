#!/usr/bin/env python3
"""
CDK Python application for ARM-based workloads with AWS Graviton processors.

This application demonstrates how to deploy and compare ARM-based Graviton instances
with x86 instances for performance and cost optimization analysis.
"""

import os
from typing import Dict, List, Optional
from aws_cdk import (
    App,
    Duration,
    Environment,
    RemovalPolicy,
    Stack,
    StackProps,
    aws_ec2 as ec2,
    aws_elasticloadbalancingv2 as elbv2,
    aws_autoscaling as autoscaling,
    aws_cloudwatch as cloudwatch,
    aws_iam as iam,
    aws_logs as logs,
    CfnOutput,
    Tags,
)
from constructs import Construct


class GravitonWorkloadStack(Stack):
    """Stack for deploying ARM-based workloads with AWS Graviton processors."""

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Create VPC or use default VPC
        self.vpc = self._create_or_get_vpc()
        
        # Create security group
        self.security_group = self._create_security_group()
        
        # Create key pair
        self.key_pair = self._create_key_pair()
        
        # Create IAM role for instances
        self.instance_role = self._create_instance_role()
        
        # Create user data scripts
        self.x86_user_data = self._create_x86_user_data()
        self.arm_user_data = self._create_arm_user_data()
        
        # Create instances
        self.x86_instance = self._create_x86_instance()
        self.arm_instance = self._create_arm_instance()
        
        # Create Application Load Balancer
        self.alb = self._create_application_load_balancer()
        
        # Create Auto Scaling Group for ARM instances
        self.arm_asg = self._create_arm_auto_scaling_group()
        
        # Create CloudWatch dashboard
        self.dashboard = self._create_cloudwatch_dashboard()
        
        # Create cost monitoring alarm
        self.cost_alarm = self._create_cost_alarm()
        
        # Create outputs
        self._create_outputs()

    def _create_or_get_vpc(self) -> ec2.Vpc:
        """Create a new VPC or use the default VPC."""
        # For simplicity, create a new VPC with public subnets
        vpc = ec2.Vpc(
            self,
            "GravitonVPC",
            max_azs=2,
            nat_gateways=0,  # Use public subnets only for demo
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="Public",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24,
                )
            ],
            enable_dns_hostnames=True,
            enable_dns_support=True,
        )
        
        Tags.of(vpc).add("Name", "GravitonWorkloadVPC")
        return vpc

    def _create_security_group(self) -> ec2.SecurityGroup:
        """Create security group for instances."""
        sg = ec2.SecurityGroup(
            self,
            "GravitonSecurityGroup",
            vpc=self.vpc,
            description="Security group for Graviton workload demo",
            allow_all_outbound=True,
        )
        
        # Allow HTTP traffic
        sg.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(80),
            description="Allow HTTP traffic",
        )
        
        # Allow SSH traffic
        sg.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(22),
            description="Allow SSH traffic",
        )
        
        Tags.of(sg).add("Name", "GravitonWorkloadSG")
        return sg

    def _create_key_pair(self) -> ec2.KeyPair:
        """Create EC2 key pair for instances."""
        key_pair = ec2.KeyPair(
            self,
            "GravitonKeyPair",
            key_pair_name=f"graviton-demo-{self.node.unique_id}",
            type=ec2.KeyPairType.RSA,
            format=ec2.KeyPairFormat.PEM,
        )
        
        Tags.of(key_pair).add("Name", "GravitonWorkloadKeyPair")
        return key_pair

    def _create_instance_role(self) -> iam.Role:
        """Create IAM role for EC2 instances."""
        role = iam.Role(
            self,
            "GravitonInstanceRole",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            description="IAM role for Graviton workload instances",
        )
        
        # Add CloudWatch agent permissions
        role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name("CloudWatchAgentServerPolicy")
        )
        
        # Add Systems Manager permissions for session manager
        role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name("AmazonSSMManagedInstanceCore")
        )
        
        return role

    def _create_x86_user_data(self) -> ec2.UserData:
        """Create user data script for x86 instances."""
        user_data = ec2.UserData.for_linux()
        
        user_data.add_commands(
            "yum update -y",
            "yum install -y httpd stress-ng htop",
            "systemctl start httpd",
            "systemctl enable httpd",
            "",
            "# Install CloudWatch agent",
            "wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm",
            "rpm -U amazon-cloudwatch-agent.rpm",
            "",
            "# Create simple web page showing architecture",
            'echo "<html><body><h1>x86 Architecture Server</h1><p>Instance: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)</p><p>Architecture: $(uname -m)</p></body></html>" > /var/www/html/index.html',
            "",
            "# Create benchmark script",
            "cat > /home/ec2-user/benchmark.sh << 'SCRIPT'",
            "#!/bin/bash",
            "echo 'Starting CPU benchmark on x86...'",
            "stress-ng --cpu 4 --timeout 60s --metrics-brief",
            "echo 'Benchmark completed'",
            "SCRIPT",
            "",
            "chmod +x /home/ec2-user/benchmark.sh",
        )
        
        return user_data

    def _create_arm_user_data(self) -> ec2.UserData:
        """Create user data script for ARM instances."""
        user_data = ec2.UserData.for_linux()
        
        user_data.add_commands(
            "yum update -y",
            "yum install -y httpd stress-ng htop",
            "systemctl start httpd",
            "systemctl enable httpd",
            "",
            "# Install CloudWatch agent for ARM",
            "wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/arm64/latest/amazon-cloudwatch-agent.rpm",
            "rpm -U amazon-cloudwatch-agent.rpm",
            "",
            "# Create simple web page showing architecture",
            'echo "<html><body><h1>ARM64 Graviton Server</h1><p>Instance: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)</p><p>Architecture: $(uname -m)</p></body></html>" > /var/www/html/index.html',
            "",
            "# Create benchmark script",
            "cat > /home/ec2-user/benchmark.sh << 'SCRIPT'",
            "#!/bin/bash",
            "echo 'Starting CPU benchmark on ARM64...'",
            "stress-ng --cpu 4 --timeout 60s --metrics-brief",
            "echo 'Benchmark completed'",
            "SCRIPT",
            "",
            "chmod +x /home/ec2-user/benchmark.sh",
        )
        
        return user_data

    def _create_x86_instance(self) -> ec2.Instance:
        """Create x86 baseline instance for comparison."""
        instance = ec2.Instance(
            self,
            "X86BaselineInstance",
            instance_type=ec2.InstanceType.of(
                ec2.InstanceClass.C6I, ec2.InstanceSize.LARGE
            ),
            machine_image=ec2.MachineImage.latest_amazon_linux2(),
            vpc=self.vpc,
            security_group=self.security_group,
            key_name=self.key_pair.key_pair_name,
            user_data=self.x86_user_data,
            role=self.instance_role,
            detailed_monitoring=True,
            vpc_subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PUBLIC),
        )
        
        Tags.of(instance).add("Name", "GravitonDemo-x86-baseline")
        Tags.of(instance).add("Architecture", "x86")
        Tags.of(instance).add("Project", "graviton-demo")
        
        return instance

    def _create_arm_instance(self) -> ec2.Instance:
        """Create ARM Graviton instance."""
        instance = ec2.Instance(
            self,
            "ARMGravitonInstance",
            instance_type=ec2.InstanceType.of(
                ec2.InstanceClass.C7G, ec2.InstanceSize.LARGE
            ),
            machine_image=ec2.MachineImage.latest_amazon_linux2(
                cpu_type=ec2.AmazonLinuxCpuType.ARM_64
            ),
            vpc=self.vpc,
            security_group=self.security_group,
            key_name=self.key_pair.key_pair_name,
            user_data=self.arm_user_data,
            role=self.instance_role,
            detailed_monitoring=True,
            vpc_subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PUBLIC),
        )
        
        Tags.of(instance).add("Name", "GravitonDemo-arm-graviton")
        Tags.of(instance).add("Architecture", "arm64")
        Tags.of(instance).add("Project", "graviton-demo")
        
        return instance

    def _create_application_load_balancer(self) -> elbv2.ApplicationLoadBalancer:
        """Create Application Load Balancer for traffic distribution."""
        alb = elbv2.ApplicationLoadBalancer(
            self,
            "GravitonALB",
            vpc=self.vpc,
            internet_facing=True,
            security_group=self.security_group,
            vpc_subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PUBLIC),
        )
        
        # Create target group
        target_group = elbv2.ApplicationTargetGroup(
            self,
            "GravitonTargetGroup",
            vpc=self.vpc,
            port=80,
            protocol=elbv2.ApplicationProtocol.HTTP,
            target_type=elbv2.TargetType.INSTANCE,
            health_check=elbv2.HealthCheck(
                enabled=True,
                healthy_threshold_count=2,
                interval=Duration.seconds(30),
                path="/",
                protocol=elbv2.Protocol.HTTP,
                timeout=Duration.seconds(5),
                unhealthy_threshold_count=3,
            ),
        )
        
        # Add instances to target group
        target_group.add_target(
            elbv2.InstanceTarget(self.x86_instance, port=80)
        )
        target_group.add_target(
            elbv2.InstanceTarget(self.arm_instance, port=80)
        )
        
        # Create listener
        listener = alb.add_listener(
            "GravitonListener",
            port=80,
            protocol=elbv2.ApplicationProtocol.HTTP,
            default_target_groups=[target_group],
        )
        
        Tags.of(alb).add("Name", "GravitonWorkloadALB")
        self.target_group = target_group
        
        return alb

    def _create_arm_auto_scaling_group(self) -> autoscaling.AutoScalingGroup:
        """Create Auto Scaling Group with ARM instances."""
        launch_template = ec2.LaunchTemplate(
            self,
            "ARMLaunchTemplate",
            launch_template_name=f"graviton-arm-template-{self.node.unique_id}",
            instance_type=ec2.InstanceType.of(
                ec2.InstanceClass.C7G, ec2.InstanceSize.LARGE
            ),
            machine_image=ec2.MachineImage.latest_amazon_linux2(
                cpu_type=ec2.AmazonLinuxCpuType.ARM_64
            ),
            key_name=self.key_pair.key_pair_name,
            security_group=self.security_group,
            user_data=self.arm_user_data,
            role=self.instance_role,
            detailed_monitoring=True,
        )
        
        asg = autoscaling.AutoScalingGroup(
            self,
            "ARMAutoScalingGroup",
            vpc=self.vpc,
            launch_template=launch_template,
            min_capacity=1,
            max_capacity=3,
            desired_capacity=2,
            health_check=autoscaling.HealthCheck.elb(
                grace=Duration.minutes(5)
            ),
            vpc_subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PUBLIC),
        )
        
        # Attach to load balancer target group
        asg.attach_to_application_target_group(self.target_group)
        
        Tags.of(asg).add("Name", "GravitonDemo-asg-arm")
        Tags.of(asg).add("Architecture", "arm64")
        Tags.of(asg).add("Project", "graviton-demo")
        
        return asg

    def _create_cloudwatch_dashboard(self) -> cloudwatch.Dashboard:
        """Create CloudWatch dashboard for performance comparison."""
        dashboard = cloudwatch.Dashboard(
            self,
            "GravitonDashboard",
            dashboard_name="Graviton-Performance-Comparison",
        )
        
        # CPU utilization comparison widget
        cpu_widget = cloudwatch.GraphWidget(
            title="CPU Utilization Comparison",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/EC2",
                    metric_name="CPUUtilization",
                    dimensions_map={
                        "InstanceId": self.x86_instance.instance_id
                    },
                    label="x86 Instance",
                    period=Duration.minutes(5),
                    statistic="Average",
                ),
                cloudwatch.Metric(
                    namespace="AWS/EC2",
                    metric_name="CPUUtilization",
                    dimensions_map={
                        "InstanceId": self.arm_instance.instance_id
                    },
                    label="ARM Instance",
                    period=Duration.minutes(5),
                    statistic="Average",
                ),
            ],
            width=12,
            height=6,
        )
        
        # Network In comparison widget
        network_widget = cloudwatch.GraphWidget(
            title="Network In Comparison",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/EC2",
                    metric_name="NetworkIn",
                    dimensions_map={
                        "InstanceId": self.x86_instance.instance_id
                    },
                    label="x86 Instance",
                    period=Duration.minutes(5),
                    statistic="Average",
                ),
                cloudwatch.Metric(
                    namespace="AWS/EC2",
                    metric_name="NetworkIn",
                    dimensions_map={
                        "InstanceId": self.arm_instance.instance_id
                    },
                    label="ARM Instance",
                    period=Duration.minutes(5),
                    statistic="Average",
                ),
            ],
            width=12,
            height=6,
        )
        
        dashboard.add_widgets(cpu_widget, network_widget)
        
        return dashboard

    def _create_cost_alarm(self) -> cloudwatch.Alarm:
        """Create CloudWatch alarm for cost monitoring."""
        alarm = cloudwatch.Alarm(
            self,
            "GravitonCostAlarm",
            alarm_name=f"graviton-cost-alert-{self.node.unique_id}",
            alarm_description="Alert when estimated charges exceed threshold",
            metric=cloudwatch.Metric(
                namespace="AWS/Billing",
                metric_name="EstimatedCharges",
                dimensions_map={"Currency": "USD"},
                statistic="Maximum",
                period=Duration.days(1),
            ),
            threshold=50.0,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        )
        
        return alarm

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs."""
        CfnOutput(
            self,
            "X86InstanceId",
            value=self.x86_instance.instance_id,
            description="Instance ID of the x86 baseline instance",
        )
        
        CfnOutput(
            self,
            "ARMInstanceId",
            value=self.arm_instance.instance_id,
            description="Instance ID of the ARM Graviton instance",
        )
        
        CfnOutput(
            self,
            "X86PublicIP",
            value=self.x86_instance.instance_public_ip,
            description="Public IP address of the x86 instance",
        )
        
        CfnOutput(
            self,
            "ARMPublicIP",
            value=self.arm_instance.instance_public_ip,
            description="Public IP address of the ARM instance",
        )
        
        CfnOutput(
            self,
            "LoadBalancerDNS",
            value=self.alb.load_balancer_dns_name,
            description="DNS name of the Application Load Balancer",
        )
        
        CfnOutput(
            self,
            "KeyPairName",
            value=self.key_pair.key_pair_name,
            description="Name of the EC2 key pair",
        )
        
        CfnOutput(
            self,
            "DashboardURL",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.dashboard.dashboard_name}",
            description="URL to the CloudWatch dashboard",
        )
        
        CfnOutput(
            self,
            "CostComparison",
            value="c6i.large (x86): $0.0864/hour | c7g.large (ARM): $0.0691/hour | Savings: 20.0%",
            description="Cost comparison between x86 and ARM instances",
        )


def main() -> None:
    """Main application entry point."""
    app = App()
    
    # Get environment from context or use defaults
    env = Environment(
        account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
        region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
    )
    
    # Create the stack
    GravitonWorkloadStack(
        app,
        "GravitonWorkloadStack",
        env=env,
        description="ARM-based workloads with AWS Graviton processors demonstration",
    )
    
    app.synth()


if __name__ == "__main__":
    main()