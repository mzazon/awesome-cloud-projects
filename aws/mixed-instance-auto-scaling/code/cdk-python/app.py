#!/usr/bin/env python3
"""
CDK Python Application for Mixed Instance Auto Scaling Groups with Spot Instances

This application creates a cost-optimized Auto Scaling group that uses mixed instance types
and combines On-Demand and Spot Instances to achieve up to 90% cost savings while
maintaining high availability and automatic scaling capabilities.

Key Features:
- Mixed instance types across multiple families (m5, c5, r5)
- Spot Instance integration with capacity rebalancing
- Application Load Balancer with health checking
- CloudWatch-based auto scaling policies
- SNS notifications for scaling events
- Multi-AZ deployment for high availability
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    CfnOutput,
    Duration,
    RemovalPolicy,
    aws_ec2 as ec2,
    aws_autoscaling as autoscaling,
    aws_elasticloadbalancingv2 as elbv2,
    aws_elasticloadbalancingv2_targets as elbv2_targets,
    aws_iam as iam,
    aws_sns as sns,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
)
from constructs import Construct
import base64
from typing import List, Dict, Any


class MixedInstanceAutoScalingStack(Stack):
    """
    CDK Stack for Mixed Instance Auto Scaling Groups with Spot Instances
    
    This stack implements a cost-optimized auto scaling solution that combines
    On-Demand and Spot Instances across multiple instance types to achieve
    significant cost savings while maintaining high availability.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        instance_types: List[str] = None,
        min_size: int = 2,
        max_size: int = 10,
        desired_capacity: int = 4,
        on_demand_base_capacity: int = 1,
        on_demand_percentage_above_base: int = 20,
        target_cpu_utilization: float = 70.0,
        enable_capacity_rebalancing: bool = True,
        **kwargs
    ) -> None:
        """
        Initialize the Mixed Instance Auto Scaling Stack
        
        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            instance_types: List of instance types to use in mixed instance policy
            min_size: Minimum number of instances in the Auto Scaling group
            max_size: Maximum number of instances in the Auto Scaling group
            desired_capacity: Desired number of instances in the Auto Scaling group
            on_demand_base_capacity: Base number of On-Demand instances
            on_demand_percentage_above_base: Percentage of On-Demand instances above base
            target_cpu_utilization: Target CPU utilization for scaling policies
            enable_capacity_rebalancing: Whether to enable capacity rebalancing
            **kwargs: Additional keyword arguments for the Stack
        """
        super().__init__(scope, construct_id, **kwargs)

        # Set default instance types if not provided
        if instance_types is None:
            instance_types = [
                "m5.large", "m5.xlarge",
                "c5.large", "c5.xlarge", 
                "r5.large", "r5.xlarge"
            ]

        # Store configuration parameters
        self.instance_types = instance_types
        self.min_size = min_size
        self.max_size = max_size
        self.desired_capacity = desired_capacity
        self.on_demand_base_capacity = on_demand_base_capacity
        self.on_demand_percentage_above_base = on_demand_percentage_above_base
        self.target_cpu_utilization = target_cpu_utilization
        self.enable_capacity_rebalancing = enable_capacity_rebalancing

        # Create VPC and networking components
        self._create_vpc()
        
        # Create security group
        self._create_security_group()
        
        # Create IAM role for EC2 instances
        self._create_iam_role()
        
        # Create user data script
        self._create_user_data()
        
        # Create launch template
        self._create_launch_template()
        
        # Create Application Load Balancer
        self._create_load_balancer()
        
        # Create Auto Scaling group with mixed instance policy
        self._create_auto_scaling_group()
        
        # Create scaling policies
        self._create_scaling_policies()
        
        # Create SNS notifications
        self._create_sns_notifications()
        
        # Create CloudWatch dashboard
        self._create_cloudwatch_dashboard()
        
        # Create outputs
        self._create_outputs()

    def _create_vpc(self) -> None:
        """Create VPC with public subnets across multiple Availability Zones"""
        self.vpc = ec2.Vpc(
            self,
            "MixedInstanceVPC",
            vpc_name="mixed-instances-vpc",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=3,
            nat_gateways=0,  # Use public subnets only for this demo
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    subnet_type=ec2.SubnetType.PUBLIC,
                    name="PublicSubnet",
                    cidr_mask=24
                )
            ],
            enable_dns_hostnames=True,
            enable_dns_support=True
        )

        # Tag VPC for better organization
        cdk.Tags.of(self.vpc).add("Purpose", "MixedInstanceAutoScaling")
        cdk.Tags.of(self.vpc).add("Environment", "Demo")

    def _create_security_group(self) -> None:
        """Create security group for EC2 instances with web server access"""
        self.security_group = ec2.SecurityGroup(
            self,
            "MixedInstanceSecurityGroup",
            vpc=self.vpc,
            description="Security group for mixed instance Auto Scaling group",
            security_group_name="mixed-instances-sg"
        )

        # Allow HTTP traffic (port 80)
        self.security_group.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(80),
            description="Allow HTTP traffic from anywhere"
        )

        # Allow HTTPS traffic (port 443)
        self.security_group.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(443),
            description="Allow HTTPS traffic from anywhere"
        )

        # Allow SSH access (port 22) - restrict to your IP in production
        self.security_group.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(22),
            description="Allow SSH access for debugging"
        )

        # Tag security group
        cdk.Tags.of(self.security_group).add("Purpose", "WebServerAccess")

    def _create_iam_role(self) -> None:
        """Create IAM role for EC2 instances with CloudWatch and SSM permissions"""
        self.instance_role = iam.Role(
            self,
            "EC2InstanceRole",
            role_name=f"EC2InstanceRole-{self.node.addr}",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            description="IAM role for EC2 instances in mixed instance Auto Scaling group"
        )

        # Attach AWS managed policies for CloudWatch and Systems Manager
        self.instance_role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name(
                "CloudWatchAgentServerPolicy"
            )
        )

        self.instance_role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name(
                "AmazonSSMManagedInstanceCore"
            )
        )

        # Create instance profile
        self.instance_profile = iam.InstanceProfile(
            self,
            "EC2InstanceProfile",
            instance_profile_name=f"EC2InstanceProfile-{self.node.addr}",
            role=self.instance_role
        )

    def _create_user_data(self) -> str:
        """Create user data script for instance initialization"""
        user_data_script = """#!/bin/bash
yum update -y
yum install -y httpd

# Get instance metadata to display on the web page
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
INSTANCE_TYPE=$(curl -s http://169.254.169.254/latest/meta-data/instance-type)
AZ=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
SPOT_TERMINATION=$(curl -s http://169.254.169.254/latest/meta-data/spot/instance-action 2>/dev/null || echo "On-Demand")

# Create informative web page showing instance details
cat > /var/www/html/index.html << 'HTML'
<!DOCTYPE html>
<html>
<head>
    <title>Mixed Instance Auto Scaling Demo</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background-color: #f5f5f5; }
        .container { max-width: 800px; margin: 0 auto; background: white; padding: 30px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .info { background: #e8f4fd; padding: 20px; border-radius: 5px; margin: 20px 0; border-left: 4px solid #007acc; }
        .spot { color: #28a745; font-weight: bold; }
        .ondemand { color: #007bff; font-weight: bold; }
        .metric { display: inline-block; margin: 10px; padding: 15px; background: #f8f9fa; border-radius: 5px; border: 1px solid #dee2e6; }
        h1 { color: #343a40; text-align: center; }
        h2 { color: #495057; border-bottom: 2px solid #007acc; padding-bottom: 10px; }
        .refresh { text-align: center; margin: 20px 0; }
        .benefits { background: #d4edda; padding: 15px; border-radius: 5px; border-left: 4px solid #28a745; }
    </style>
    <script>
        function refreshPage() {
            location.reload();
        }
        // Auto-refresh every 30 seconds
        setTimeout(refreshPage, 30000);
    </script>
</head>
<body>
    <div class="container">
        <h1>🚀 Mixed Instance Auto Scaling Demo</h1>
        
        <div class="info">
            <h2>Instance Information</h2>
            <div class="metric">
                <strong>Instance ID:</strong><br>
HTML

# Add instance metadata dynamically
echo "                $INSTANCE_ID" >> /var/www/html/index.html

cat >> /var/www/html/index.html << 'HTML'
            </div>
            <div class="metric">
                <strong>Instance Type:</strong><br>
HTML

echo "                $INSTANCE_TYPE" >> /var/www/html/index.html

cat >> /var/www/html/index.html << 'HTML'
            </div>
            <div class="metric">
                <strong>Availability Zone:</strong><br>
HTML

echo "                $AZ" >> /var/www/html/index.html

cat >> /var/www/html/index.html << 'HTML'
            </div>
            <div class="metric">
                <strong>Purchase Type:</strong><br>
                <span class="HTML

if [ "$SPOT_TERMINATION" = "On-Demand" ]; then
    echo 'ondemand">On-Demand Instance</span>' >> /var/www/html/index.html
else
    echo 'spot">Spot Instance</span>' >> /var/www/html/index.html
fi

cat >> /var/www/html/index.html << 'HTML'
            </div>
            <div class="metric">
                <strong>Last Updated:</strong><br>
HTML

echo "                $(date)" >> /var/www/html/index.html

cat >> /var/www/html/index.html << 'HTML'
            </div>
        </div>
        
        <div class="benefits">
            <h2>💰 Auto Scaling Group Benefits</h2>
            <ul>
                <li><strong>Cost Optimization:</strong> Up to 90% savings with Spot Instances</li>
                <li><strong>High Availability:</strong> Multi-AZ deployment with automatic failover</li>
                <li><strong>Automatic Scaling:</strong> Scales based on CPU and network metrics</li>
                <li><strong>Instance Diversification:</strong> Multiple instance types and families</li>
                <li><strong>Capacity Rebalancing:</strong> Handles Spot interruptions gracefully</li>
                <li><strong>Health Monitoring:</strong> Integrated with Application Load Balancer</li>
            </ul>
        </div>
        
        <div class="refresh">
            <button onclick="refreshPage()" style="padding: 10px 20px; background: #007acc; color: white; border: none; border-radius: 5px; cursor: pointer;">
                🔄 Refresh Instance Info
            </button>
            <p><small>Page auto-refreshes every 30 seconds</small></p>
        </div>
    </div>
</body>
</html>
HTML

# Start and enable Apache web server
systemctl start httpd
systemctl enable httpd

# Install and configure CloudWatch agent for custom metrics
yum install -y amazon-cloudwatch-agent

cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'JSON'
{
    "metrics": {
        "namespace": "AutoScaling/MixedInstances",
        "metrics_collected": {
            "cpu": {
                "measurement": ["cpu_usage_idle", "cpu_usage_iowait", "cpu_usage_user", "cpu_usage_system"],
                "metrics_collection_interval": 60,
                "totalcpu": false
            },
            "disk": {
                "measurement": ["used_percent"],
                "metrics_collection_interval": 60,
                "resources": ["*"]
            },
            "mem": {
                "measurement": ["mem_used_percent"],
                "metrics_collection_interval": 60
            },
            "netstat": {
                "measurement": ["tcp_established", "tcp_time_wait"],
                "metrics_collection_interval": 60
            }
        }
    },
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/httpd/access_log",
                        "log_group_name": "mixed-instances-asg",
                        "log_stream_name": "{instance_id}/httpd/access_log"
                    },
                    {
                        "file_path": "/var/log/httpd/error_log",
                        "log_group_name": "mixed-instances-asg",
                        "log_stream_name": "{instance_id}/httpd/error_log"
                    }
                ]
            }
        }
    }
}
JSON

# Start CloudWatch agent with the configuration
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \\
    -a fetch-config -m ec2 -s \\
    -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

# Create a simple health check endpoint
echo "OK" > /var/www/html/health

# Log successful initialization
echo "$(date): Instance initialization completed successfully" >> /var/log/user-data.log
"""

        self.user_data = ec2.UserData.for_linux()
        self.user_data.add_commands(user_data_script)

    def _create_launch_template(self) -> None:
        """Create launch template with base configuration for mixed instance policy"""
        # Get latest Amazon Linux 2 AMI
        self.ami = ec2.MachineImage.latest_amazon_linux2(
            edition=ec2.AmazonLinuxEdition.STANDARD,
            virtualization=ec2.AmazonLinuxVirt.HVM,
            storage=ec2.AmazonLinuxStorage.GENERAL_PURPOSE
        )

        # Create launch template
        self.launch_template = ec2.LaunchTemplate(
            self,
            "MixedInstanceLaunchTemplate",
            launch_template_name="mixed-instances-template",
            machine_image=self.ami,
            instance_type=ec2.InstanceType.of(
                ec2.InstanceClass.M5,
                ec2.InstanceSize.LARGE
            ),
            security_group=self.security_group,
            user_data=self.user_data,
            role=self.instance_role,
            # Enable detailed monitoring for better scaling decisions
            detailed_monitoring=True,
            # Use IMDSv2 for improved security
            require_imdsv2=True,
            # Block device mappings for optimized storage
            block_devices=[
                ec2.BlockDevice(
                    device_name="/dev/xvda",
                    volume=ec2.BlockDeviceVolume.ebs(
                        volume_size=20,
                        volume_type=ec2.EbsDeviceVolumeType.GP3,
                        encrypted=True,
                        delete_on_termination=True
                    )
                )
            ]
        )

        # Tag launch template
        cdk.Tags.of(self.launch_template).add("Purpose", "MixedInstanceAutoScaling")

    def _create_load_balancer(self) -> None:
        """Create Application Load Balancer for the Auto Scaling group"""
        # Create Application Load Balancer
        self.load_balancer = elbv2.ApplicationLoadBalancer(
            self,
            "MixedInstanceALB",
            vpc=self.vpc,
            internet_facing=True,
            security_group=self.security_group,
            load_balancer_name="mixed-instances-alb"
        )

        # Create target group with health check configuration
        self.target_group = elbv2.ApplicationTargetGroup(
            self,
            "MixedInstanceTargetGroup",
            target_group_name="mixed-instances-tg",
            port=80,
            protocol=elbv2.ApplicationProtocol.HTTP,
            vpc=self.vpc,
            target_type=elbv2.TargetType.INSTANCE,
            health_check=elbv2.HealthCheck(
                enabled=True,
                healthy_http_codes="200",
                healthy_threshold_count=2,
                unhealthy_threshold_count=3,
                interval=Duration.seconds(30),
                path="/health",
                protocol=elbv2.Protocol.HTTP,
                timeout=Duration.seconds(5)
            ),
            # Configure stickiness for better user experience
            stickiness_cookie_duration=Duration.hours(1),
            # Enable deregistration delay for graceful shutdowns
            deregistration_delay=Duration.seconds(30)
        )

        # Create listener to route traffic to target group
        self.listener = self.load_balancer.add_listener(
            "MixedInstanceListener",
            port=80,
            protocol=elbv2.ApplicationProtocol.HTTP,
            default_target_groups=[self.target_group]
        )

        # Tag load balancer resources
        cdk.Tags.of(self.load_balancer).add("Purpose", "MixedInstanceAutoScaling")
        cdk.Tags.of(self.target_group).add("Purpose", "MixedInstanceAutoScaling")

    def _create_auto_scaling_group(self) -> None:
        """Create Auto Scaling group with mixed instance policy"""
        # Create mixed instance policy with multiple instance types
        mixed_instances_policy = autoscaling.MixedInstancesPolicy(
            launch_template=self.launch_template,
            launch_template_overrides=[
                autoscaling.LaunchTemplateOverrides(
                    instance_type=ec2.InstanceType(instance_type),
                    weighted_capacity=2 if "xlarge" in instance_type else 1
                )
                for instance_type in self.instance_types
            ],
            instances_distribution=autoscaling.InstancesDistribution(
                on_demand_allocation_strategy=autoscaling.OnDemandAllocationStrategy.PRIORITIZED,
                on_demand_base_capacity=self.on_demand_base_capacity,
                on_demand_percentage_above_base_capacity=self.on_demand_percentage_above_base,
                spot_allocation_strategy=autoscaling.SpotAllocationStrategy.DIVERSIFIED,
                spot_instance_pools=4,
                # Let AWS determine optimal Spot pricing
                spot_max_price=None
            )
        )

        # Create Auto Scaling group with mixed instance policy
        self.auto_scaling_group = autoscaling.AutoScalingGroup(
            self,
            "MixedInstanceAutoScalingGroup",
            auto_scaling_group_name="mixed-instances-asg",
            vpc=self.vpc,
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PUBLIC
            ),
            mixed_instances_policy=mixed_instances_policy,
            min_capacity=self.min_size,
            max_capacity=self.max_size,
            desired_capacity=self.desired_capacity,
            health_check=autoscaling.HealthCheck.elb(
                grace=Duration.seconds(300)
            ),
            default_instance_warmup=Duration.seconds(300),
            # Enable capacity rebalancing for Spot Instance management
            capacity_rebalance=self.enable_capacity_rebalancing,
            # Configure termination policies
            termination_policies=[
                autoscaling.TerminationPolicy.OLDEST_LAUNCH_TEMPLATE,
                autoscaling.TerminationPolicy.OLDEST_INSTANCE
            ],
            # Enable group metrics collection
            group_metrics=[autoscaling.GroupMetrics.all()],
            # Configure update policy for rolling updates
            update_policy=autoscaling.UpdatePolicy.rolling_update(
                min_instances_in_service=1,
                max_batch_size=2,
                pause_time=Duration.minutes(5)
            )
        )

        # Attach Auto Scaling group to target group
        self.auto_scaling_group.attach_to_application_target_group(
            self.target_group
        )

        # Tag Auto Scaling group
        cdk.Tags.of(self.auto_scaling_group).add("Purpose", "MixedInstanceAutoScaling")
        cdk.Tags.of(self.auto_scaling_group).add("Environment", "Demo")

    def _create_scaling_policies(self) -> None:
        """Create CloudWatch-based scaling policies"""
        # Create target tracking scaling policy for CPU utilization
        self.cpu_scaling_policy = self.auto_scaling_group.scale_on_cpu_utilization(
            "CPUScalingPolicy",
            target_utilization_percent=self.target_cpu_utilization,
            cooldown=Duration.seconds(300),
            scale_in_cooldown=Duration.seconds(300),
            scale_out_cooldown=Duration.seconds(300)
        )

        # Create target tracking scaling policy for network utilization
        self.network_scaling_policy = self.auto_scaling_group.scale_on_metric(
            "NetworkScalingPolicy",
            metric=cloudwatch.Metric(
                namespace="AWS/EC2",
                metric_name="NetworkIn",
                dimensions_map={
                    "AutoScalingGroupName": self.auto_scaling_group.auto_scaling_group_name
                },
                statistic="Average"
            ),
            scaling_steps=[
                autoscaling.ScalingInterval(
                    upper=1000000,  # 1MB
                    change=1
                ),
                autoscaling.ScalingInterval(
                    lower=10000000,  # 10MB
                    change=2
                )
            ],
            cooldown=Duration.seconds(300)
        )

        # Create step scaling policy for request count
        self.request_scaling_policy = self.auto_scaling_group.scale_on_metric(
            "RequestCountScalingPolicy",
            metric=self.target_group.metric_request_count_per_target(
                statistic="Sum"
            ),
            scaling_steps=[
                autoscaling.ScalingInterval(
                    upper=100,
                    change=0
                ),
                autoscaling.ScalingInterval(
                    lower=100,
                    upper=200,
                    change=1
                ),
                autoscaling.ScalingInterval(
                    lower=200,
                    change=2
                )
            ],
            cooldown=Duration.seconds(300)
        )

    def _create_sns_notifications(self) -> None:
        """Create SNS topic and notifications for Auto Scaling events"""
        # Create SNS topic for Auto Scaling notifications
        self.scaling_topic = sns.Topic(
            self,
            "AutoScalingNotifications",
            topic_name="autoscaling-notifications",
            display_name="Auto Scaling Notifications",
            description="Notifications for Auto Scaling group events"
        )

        # Configure Auto Scaling group to send notifications
        self.auto_scaling_group.add_notification_configuration(
            "ScalingNotifications",
            topic=self.scaling_topic,
            scaling_events=autoscaling.ScalingEvents.ALL
        )

        # Tag SNS topic
        cdk.Tags.of(self.scaling_topic).add("Purpose", "AutoScalingNotifications")

    def _create_cloudwatch_dashboard(self) -> None:
        """Create CloudWatch dashboard for monitoring the Auto Scaling group"""
        self.dashboard = cloudwatch.Dashboard(
            self,
            "MixedInstanceDashboard",
            dashboard_name="MixedInstanceAutoScaling",
            period_override=cloudwatch.PeriodOverride.AUTO
        )

        # Add widgets for Auto Scaling group metrics
        self.dashboard.add_widgets(
            # Instance count and capacity metrics
            cloudwatch.GraphWidget(
                title="Auto Scaling Group Capacity",
                left=[
                    self.auto_scaling_group.metric_group_desired_capacity(),
                    self.auto_scaling_group.metric_group_in_service_instances(),
                    self.auto_scaling_group.metric_group_total_instances()
                ],
                width=12,
                height=6
            ),
            
            # CPU utilization across instances
            cloudwatch.GraphWidget(
                title="CPU Utilization",
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/EC2",
                        metric_name="CPUUtilization",
                        dimensions_map={
                            "AutoScalingGroupName": self.auto_scaling_group.auto_scaling_group_name
                        },
                        statistic="Average"
                    )
                ],
                width=12,
                height=6
            )
        )

        # Add load balancer metrics
        self.dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Load Balancer Metrics",
                left=[
                    self.target_group.metric_request_count(),
                    self.target_group.metric_healthy_host_count(),
                    self.target_group.metric_target_response_time()
                ],
                width=12,
                height=6
            ),
            
            # Network metrics
            cloudwatch.GraphWidget(
                title="Network Utilization",
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/EC2",
                        metric_name="NetworkIn",
                        dimensions_map={
                            "AutoScalingGroupName": self.auto_scaling_group.auto_scaling_group_name
                        },
                        statistic="Average"
                    ),
                    cloudwatch.Metric(
                        namespace="AWS/EC2",
                        metric_name="NetworkOut",
                        dimensions_map={
                            "AutoScalingGroupName": self.auto_scaling_group.auto_scaling_group_name
                        },
                        statistic="Average"
                    )
                ],
                width=12,
                height=6
            )
        )

        # Create CloudWatch log group for application logs
        self.log_group = logs.LogGroup(
            self,
            "MixedInstanceLogGroup",
            log_group_name="mixed-instances-asg",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources"""
        CfnOutput(
            self,
            "LoadBalancerDNS",
            value=self.load_balancer.load_balancer_dns_name,
            description="DNS name of the Application Load Balancer",
            export_name=f"{self.stack_name}-LoadBalancerDNS"
        )

        CfnOutput(
            self,
            "LoadBalancerURL",
            value=f"http://{self.load_balancer.load_balancer_dns_name}",
            description="URL to access the web application",
            export_name=f"{self.stack_name}-LoadBalancerURL"
        )

        CfnOutput(
            self,
            "AutoScalingGroupName",
            value=self.auto_scaling_group.auto_scaling_group_name,
            description="Name of the Auto Scaling group",
            export_name=f"{self.stack_name}-AutoScalingGroupName"
        )

        CfnOutput(
            self,
            "AutoScalingGroupARN",
            value=self.auto_scaling_group.auto_scaling_group_arn,
            description="ARN of the Auto Scaling group",
            export_name=f"{self.stack_name}-AutoScalingGroupARN"
        )

        CfnOutput(
            self,
            "SNSTopicARN",
            value=self.scaling_topic.topic_arn,
            description="ARN of the SNS topic for scaling notifications",
            export_name=f"{self.stack_name}-SNSTopicARN"
        )

        CfnOutput(
            self,
            "CloudWatchDashboardURL",
            value=f"https://console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.dashboard.dashboard_name}",
            description="URL to the CloudWatch dashboard",
            export_name=f"{self.stack_name}-CloudWatchDashboardURL"
        )

        CfnOutput(
            self,
            "InstanceTypes",
            value=", ".join(self.instance_types),
            description="Instance types used in the mixed instance policy",
            export_name=f"{self.stack_name}-InstanceTypes"
        )

        CfnOutput(
            self,
            "CostOptimizationSummary",
            value=f"On-Demand base: {self.on_demand_base_capacity}, Above base: {self.on_demand_percentage_above_base}%, Estimated savings: 60-90%",
            description="Cost optimization configuration summary",
            export_name=f"{self.stack_name}-CostOptimizationSummary"
        )


# CDK App definition
app = cdk.App()

# Create the stack with customizable parameters
stack = MixedInstanceAutoScalingStack(
    app,
    "MixedInstanceAutoScalingStack",
    description="Cost-optimized Auto Scaling group with mixed instance types and Spot Instances",
    env=Environment(
        account=app.node.try_get_context("account"),
        region=app.node.try_get_context("region")
    ),
    # Customizable parameters (can be overridden via CDK context)
    instance_types=app.node.try_get_context("instance_types") or [
        "m5.large", "m5.xlarge",
        "c5.large", "c5.xlarge", 
        "r5.large", "r5.xlarge"
    ],
    min_size=int(app.node.try_get_context("min_size") or 2),
    max_size=int(app.node.try_get_context("max_size") or 10),
    desired_capacity=int(app.node.try_get_context("desired_capacity") or 4),
    on_demand_base_capacity=int(app.node.try_get_context("on_demand_base_capacity") or 1),
    on_demand_percentage_above_base=int(app.node.try_get_context("on_demand_percentage_above_base") or 20),
    target_cpu_utilization=float(app.node.try_get_context("target_cpu_utilization") or 70.0),
    enable_capacity_rebalancing=app.node.try_get_context("enable_capacity_rebalancing") != "false"
)

# Add tags to all resources in the stack
cdk.Tags.of(app).add("Project", "MixedInstanceAutoScaling")
cdk.Tags.of(app).add("Environment", "Demo")
cdk.Tags.of(app).add("CostCenter", "Engineering")
cdk.Tags.of(app).add("Owner", "DevOps Team")

# Synthesize the CloudFormation template
app.synth()