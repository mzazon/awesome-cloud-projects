#!/usr/bin/env python3
"""
CDK Python Application for Auto Scaling with Application Load Balancers and Target Groups

This application creates a comprehensive auto scaling infrastructure including:
- VPC with public and private subnets across multiple AZs
- Application Load Balancer with target groups
- Auto Scaling Group with launch template
- Target tracking scaling policies for CPU and ALB request count
- Scheduled scaling actions for business hours
- CloudWatch monitoring and alarms
- Security groups with appropriate access controls

Author: AWS CDK Recipe Generator
Version: 1.0
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    CfnOutput,
    Duration,
    aws_ec2 as ec2,
    aws_elasticloadbalancingv2 as elbv2,
    aws_autoscaling as autoscaling,
    aws_cloudwatch as cloudwatch,
    aws_iam as iam,
)
from constructs import Construct
from typing import List, Dict, Any
import json


class AutoScalingALBStack(Stack):
    """
    CDK Stack for Auto Scaling with Load Balancers.
    
    This stack creates a production-ready auto scaling infrastructure with:
    - Multi-AZ deployment for high availability
    - Intelligent load balancing with health checks
    - Reactive and proactive scaling policies
    - Comprehensive monitoring and alerting
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Configuration parameters
        self.app_name = "web-app-autoscaling"
        self.environment = "demo"
        
        # Create VPC and networking components
        self.vpc = self._create_vpc()
        
        # Create security groups
        self.security_group = self._create_security_group()
        
        # Create Application Load Balancer
        self.alb, self.target_group = self._create_load_balancer()
        
        # Create Auto Scaling Group
        self.auto_scaling_group = self._create_auto_scaling_group()
        
        # Configure scaling policies
        self._create_scaling_policies()
        
        # Create scheduled scaling actions
        self._create_scheduled_scaling()
        
        # Set up CloudWatch monitoring and alarms
        self._create_monitoring_and_alarms()
        
        # Create outputs
        self._create_outputs()

    def _create_vpc(self) -> ec2.Vpc:
        """
        Create VPC with public and private subnets across multiple AZs.
        
        Returns:
            ec2.Vpc: The created VPC with proper subnet configuration
        """
        vpc = ec2.Vpc(
            self,
            "AutoScalingVPC",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=3,
            nat_gateways=1,  # Cost optimization: single NAT gateway
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
        
        # Tag subnets for better organization
        for subnet in vpc.public_subnets:
            cdk.Tags.of(subnet).add("Name", f"{self.app_name}-public-{subnet.availability_zone}")
            cdk.Tags.of(subnet).add("Type", "Public")
        
        for subnet in vpc.private_subnets:
            cdk.Tags.of(subnet).add("Name", f"{self.app_name}-private-{subnet.availability_zone}")
            cdk.Tags.of(subnet).add("Type", "Private")
        
        return vpc

    def _create_security_group(self) -> ec2.SecurityGroup:
        """
        Create security group for web application instances.
        
        Returns:
            ec2.SecurityGroup: Security group with HTTP, HTTPS, and SSH access
        """
        security_group = ec2.SecurityGroup(
            self,
            "WebAppSecurityGroup",
            vpc=self.vpc,
            description="Security group for auto-scaled web application instances",
            security_group_name=f"{self.app_name}-sg",
            allow_all_outbound=True,
        )
        
        # Allow HTTP traffic from anywhere
        security_group.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(80),
            description="Allow HTTP traffic from anywhere",
        )
        
        # Allow HTTPS traffic from anywhere
        security_group.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(443),
            description="Allow HTTPS traffic from anywhere",
        )
        
        # Allow SSH access for troubleshooting (consider restricting in production)
        security_group.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(22),
            description="Allow SSH access for troubleshooting",
        )
        
        return security_group

    def _create_user_data_script(self) -> str:
        """
        Create user data script for web server initialization.
        
        Returns:
            str: Base64 encoded user data script
        """
        user_data_script = """#!/bin/bash
yum update -y
yum install -y httpd

# Start and enable Apache
systemctl start httpd
systemctl enable httpd

# Create demo web page with instance metadata and load testing capability
cat > /var/www/html/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Auto Scaling Demo</title>
    <style>
        body { 
            font-family: Arial, sans-serif; 
            margin: 40px; 
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
        }
        .container { 
            max-width: 800px; 
            margin: 0 auto; 
            background: rgba(255,255,255,0.1);
            padding: 30px;
            border-radius: 15px;
            backdrop-filter: blur(10px);
        }
        .metric { 
            background: rgba(255,255,255,0.2); 
            padding: 20px; 
            margin: 15px 0; 
            border-radius: 10px; 
            border: 1px solid rgba(255,255,255,0.3);
        }
        button {
            background: #4CAF50;
            color: white;
            padding: 12px 24px;
            border: none;
            border-radius: 6px;
            cursor: pointer;
            font-size: 16px;
            transition: background 0.3s;
        }
        button:hover { background: #45a049; }
        button:disabled { background: #666; cursor: not-allowed; }
        .status { margin-top: 10px; }
        h1 { text-align: center; margin-bottom: 30px; }
        h3 { margin-top: 0; color: #ffeb3b; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 Auto Scaling Demo Application</h1>
        <div class="metric">
            <h3>📊 Instance Information</h3>
            <p><strong>Instance ID:</strong> <span id="instance-id">Loading...</span></p>
            <p><strong>Availability Zone:</strong> <span id="az">Loading...</span></p>
            <p><strong>Instance Type:</strong> <span id="instance-type">Loading...</span></p>
            <p><strong>Local IP:</strong> <span id="local-ip">Loading...</span></p>
            <p><strong>Server Time:</strong> <span id="server-time"></span></p>
            <p><strong>Page Load Count:</strong> <span id="load-count">1</span></p>
        </div>
        <div class="metric">
            <h3>🔥 Load Testing</h3>
            <button id="load-btn" onclick="generateLoad()">Generate CPU Load (30 seconds)</button>
            <div class="status">
                <p><strong>Status:</strong> <span id="load-status">Ready</span></p>
                <p><strong>Progress:</strong> <span id="progress">0%</span></p>
            </div>
        </div>
        <div class="metric">
            <h3>📈 Auto Scaling Information</h3>
            <p>This instance is part of an Auto Scaling Group that:</p>
            <ul>
                <li>Scales based on CPU utilization (target: 70%)</li>
                <li>Scales based on ALB request count (target: 1000 requests/minute)</li>
                <li>Has scheduled scaling for business hours</li>
                <li>Performs health checks every 30 seconds</li>
            </ul>
        </div>
    </div>
    
    <script>
        let loadCount = 1;
        
        // Fetch instance metadata using IMDSv2
        async function fetchMetadata() {
            try {
                const token = await fetch('http://169.254.169.254/latest/api/token', {
                    method: 'PUT',
                    headers: {'X-aws-ec2-metadata-token-ttl-seconds': '21600'}
                }).then(r => r.text());
                
                const headers = {'X-aws-ec2-metadata-token': token};
                
                const instanceId = await fetch('http://169.254.169.254/latest/meta-data/instance-id', {headers}).then(r => r.text());
                const az = await fetch('http://169.254.169.254/latest/meta-data/placement/availability-zone', {headers}).then(r => r.text());
                const instanceType = await fetch('http://169.254.169.254/latest/meta-data/instance-type', {headers}).then(r => r.text());
                const localIp = await fetch('http://169.254.169.254/latest/meta-data/local-ipv4', {headers}).then(r => r.text());
                
                document.getElementById('instance-id').textContent = instanceId;
                document.getElementById('az').textContent = az;
                document.getElementById('instance-type').textContent = instanceType;
                document.getElementById('local-ip').textContent = localIp;
            } catch (error) {
                console.error('Error fetching metadata:', error);
                document.getElementById('instance-id').textContent = 'N/A (possibly not on EC2)';
                document.getElementById('az').textContent = 'N/A';
                document.getElementById('instance-type').textContent = 'N/A';
                document.getElementById('local-ip').textContent = 'N/A';
            }
        }
        
        // Generate CPU load for testing auto scaling
        function generateLoad() {
            const button = document.getElementById('load-btn');
            const status = document.getElementById('load-status');
            const progress = document.getElementById('progress');
            
            button.disabled = true;
            status.textContent = 'Generating high CPU load...';
            
            // Create multiple workers to consume CPU
            const workers = [];
            const workerCount = navigator.hardwareConcurrency || 4;
            
            for (let i = 0; i < workerCount; i++) {
                const worker = new Worker('data:application/javascript,let start=Date.now();while(Date.now()-start<30000){Math.random();}postMessage("done");');
                workers.push(worker);
            }
            
            // Update progress
            let progressValue = 0;
            const progressInterval = setInterval(() => {
                progressValue += 3.33; // 30 seconds / 100% = 0.3 seconds per 1%
                progress.textContent = Math.min(100, Math.round(progressValue)) + '%';
            }, 100);
            
            setTimeout(() => {
                workers.forEach(worker => worker.terminate());
                clearInterval(progressInterval);
                button.disabled = false;
                status.textContent = 'Load test completed';
                progress.textContent = '100%';
                
                setTimeout(() => {
                    status.textContent = 'Ready';
                    progress.textContent = '0%';
                }, 3000);
            }, 30000);
        }
        
        // Update server time and load count
        function updateDynamicContent() {
            document.getElementById('server-time').textContent = new Date().toLocaleString();
            document.getElementById('load-count').textContent = ++loadCount;
        }
        
        // Initialize page
        fetchMetadata();
        updateDynamicContent();
        setInterval(updateDynamicContent, 1000);
        
        // Update load count on page visibility change
        document.addEventListener('visibilitychange', () => {
            if (!document.hidden) {
                updateDynamicContent();
            }
        });
    </script>
</body>
</html>
EOF

# Set proper permissions
chown apache:apache /var/www/html/index.html
chmod 644 /var/www/html/index.html

# Install CloudWatch agent for better monitoring
yum install -y amazon-cloudwatch-agent
"""
        return user_data_script

    def _create_load_balancer(self) -> tuple[elbv2.ApplicationLoadBalancer, elbv2.ApplicationTargetGroup]:
        """
        Create Application Load Balancer and target group.
        
        Returns:
            tuple: ALB and target group instances
        """
        # Create Application Load Balancer
        alb = elbv2.ApplicationLoadBalancer(
            self,
            "WebAppALB",
            vpc=self.vpc,
            internet_facing=True,
            load_balancer_name=f"{self.app_name}-alb",
            security_group=self.security_group,
            vpc_subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PUBLIC),
        )
        
        # Create target group with optimized health check settings
        target_group = elbv2.ApplicationTargetGroup(
            self,
            "WebAppTargetGroup",
            target_group_name=f"{self.app_name}-targets",
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
                path="/",
                port="80",
                protocol=elbv2.Protocol.HTTP,
                timeout=Duration.seconds(5),
            ),
            deregistration_delay=Duration.seconds(30),
            stickiness_cookie_duration=Duration.seconds(0),  # Disable stickiness
        )
        
        # Create listener
        alb.add_listener(
            "WebAppListener",
            port=80,
            protocol=elbv2.ApplicationProtocol.HTTP,
            default_target_groups=[target_group],
        )
        
        return alb, target_group

    def _create_auto_scaling_group(self) -> autoscaling.AutoScalingGroup:
        """
        Create Auto Scaling Group with launch template.
        
        Returns:
            autoscaling.AutoScalingGroup: The configured Auto Scaling Group
        """
        # Get the latest Amazon Linux 2 AMI
        amzn_linux = ec2.MachineImage.latest_amazon_linux2(
            edition=ec2.AmazonLinuxEdition.STANDARD,
            virtualization=ec2.AmazonLinuxVirt.HVM,
            storage=ec2.AmazonLinuxStorage.GENERAL_PURPOSE,
        )
        
        # Create IAM role for EC2 instances (for CloudWatch monitoring)
        instance_role = iam.Role(
            self,
            "EC2InstanceRole",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("CloudWatchAgentServerPolicy"),
            ],
        )
        
        # Create Auto Scaling Group
        auto_scaling_group = autoscaling.AutoScalingGroup(
            self,
            "WebAppAutoScalingGroup",
            vpc=self.vpc,
            vpc_subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS),
            instance_type=ec2.InstanceType.of(
                ec2.InstanceClass.BURSTABLE3, ec2.InstanceSize.MICRO
            ),
            machine_image=amzn_linux,
            security_group=self.security_group,
            user_data=ec2.UserData.custom(self._create_user_data_script()),
            role=instance_role,
            min_capacity=2,
            max_capacity=8,
            desired_capacity=2,
            health_check=autoscaling.HealthCheck.elb(grace=Duration.minutes(5)),
            update_policy=autoscaling.UpdatePolicy.rolling_update(
                max_batch_size=1,
                min_instances_in_service=1,
                pause_time=Duration.minutes(5),
            ),
        )
        
        # Attach target group to Auto Scaling Group
        auto_scaling_group.attach_to_application_target_group(self.target_group)
        
        # Add tags to instances
        cdk.Tags.of(auto_scaling_group).add("Name", f"{self.app_name}-instance")
        cdk.Tags.of(auto_scaling_group).add("Environment", self.environment)
        cdk.Tags.of(auto_scaling_group).add("Application", self.app_name)
        
        return auto_scaling_group

    def _create_scaling_policies(self) -> None:
        """Create target tracking scaling policies for CPU and ALB request count."""
        
        # CPU utilization target tracking policy
        self.auto_scaling_group.scale_on_cpu_utilization(
            "CPUTargetTrackingPolicy",
            target_utilization_percent=70,
            scale_in_cooldown=Duration.minutes(5),
            scale_out_cooldown=Duration.minutes(5),
            disable_scale_in=False,
        )
        
        # ALB request count target tracking policy
        self.auto_scaling_group.scale_on_request_count(
            "ALBRequestCountPolicy",
            requests_per_target=1000,
            target_group=self.target_group,
            scale_in_cooldown=Duration.minutes(5),
            scale_out_cooldown=Duration.minutes(5),
            disable_scale_in=False,
        )

    def _create_scheduled_scaling(self) -> None:
        """Create scheduled scaling actions for business hours."""
        
        # Scale up during business hours (9 AM UTC, Monday-Friday)
        self.auto_scaling_group.scale_on_schedule(
            "ScaleUpBusinessHours",
            schedule=autoscaling.Schedule.cron(
                hour="9",
                minute="0",
                week_day="MON-FRI",
            ),
            min_capacity=3,
            max_capacity=10,
            desired_capacity=4,
        )
        
        # Scale down after business hours (6 PM UTC, Monday-Friday)
        self.auto_scaling_group.scale_on_schedule(
            "ScaleDownAfterHours",
            schedule=autoscaling.Schedule.cron(
                hour="18",
                minute="0",
                week_day="MON-FRI",
            ),
            min_capacity=1,
            max_capacity=8,
            desired_capacity=2,
        )

    def _create_monitoring_and_alarms(self) -> None:
        """Create CloudWatch monitoring and alarms."""
        
        # High CPU utilization alarm
        cpu_alarm = cloudwatch.Alarm(
            self,
            "HighCPUAlarm",
            alarm_name=f"{self.app_name}-high-cpu",
            alarm_description="High CPU utilization across Auto Scaling Group",
            metric=self.auto_scaling_group.metric_cpu_utilization(
                statistic=cloudwatch.Stats.AVERAGE,
                period=Duration.minutes(5),
            ),
            threshold=80,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        )
        
        # Unhealthy targets alarm
        unhealthy_targets_alarm = cloudwatch.Alarm(
            self,
            "UnhealthyTargetsAlarm",
            alarm_name=f"{self.app_name}-unhealthy-targets",
            alarm_description="Unhealthy targets in target group",
            metric=self.target_group.metric_unhealthy_host_count(
                statistic=cloudwatch.Stats.AVERAGE,
                period=Duration.minutes(1),
            ),
            threshold=1,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
        )
        
        # Store alarms as instance variables for potential SNS integration
        self.cpu_alarm = cpu_alarm
        self.unhealthy_targets_alarm = unhealthy_targets_alarm

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        
        CfnOutput(
            self,
            "LoadBalancerDNS",
            value=self.alb.load_balancer_dns_name,
            description="DNS name of the Application Load Balancer",
            export_name=f"{self.stack_name}-ALB-DNS",
        )
        
        CfnOutput(
            self,
            "LoadBalancerURL",
            value=f"http://{self.alb.load_balancer_dns_name}",
            description="URL to access the web application",
        )
        
        CfnOutput(
            self,
            "AutoScalingGroupName",
            value=self.auto_scaling_group.auto_scaling_group_name,
            description="Name of the Auto Scaling Group",
            export_name=f"{self.stack_name}-ASG-Name",
        )
        
        CfnOutput(
            self,
            "TargetGroupArn",
            value=self.target_group.target_group_arn,
            description="ARN of the target group",
            export_name=f"{self.stack_name}-TG-ARN",
        )
        
        CfnOutput(
            self,
            "VPCId",
            value=self.vpc.vpc_id,
            description="ID of the VPC",
            export_name=f"{self.stack_name}-VPC-ID",
        )


# CDK App and Stack instantiation
app = cdk.App()

# Get configuration from context or use defaults
stack_name = app.node.try_get_context("stack_name") or "AutoScalingALBStack"
env_config = {
    "account": app.node.try_get_context("account") or None,
    "region": app.node.try_get_context("region") or "us-east-1",
}

# Create the stack
AutoScalingALBStack(
    app,
    stack_name,
    env=cdk.Environment(**env_config),
    description="Auto Scaling with Application Load Balancers and Target Groups",
    tags={
        "Project": "AutoScalingDemo",
        "Environment": "Demo",
        "Owner": "CDK",
        "CostCenter": "Engineering",
    },
)

# Synthesize the CDK app
app.synth()