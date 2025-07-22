#!/usr/bin/env python3
"""
CDK Application for GPU-Accelerated Workloads with EC2 P4 and G4 Instances

This application deploys a complete GPU computing infrastructure including:
- P4 instances for ML training workloads
- G4 instances for inference and graphics workloads
- Comprehensive monitoring and alerting
- Cost optimization automation
- Security configurations

Author: AWS CDK Team
Version: 1.0
"""

import os
from typing import Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    Duration,
    Stack,
    StackProps,
    Tags,
    aws_cloudwatch as cloudwatch,
    aws_cloudwatch_actions as cw_actions,
    aws_ec2 as ec2,
    aws_events as events,
    aws_events_targets as targets,
    aws_iam as iam,
    aws_lambda as _lambda,
    aws_logs as logs,
    aws_sns as sns,
    aws_sns_subscriptions as subs,
    aws_ssm as ssm,
)
from constructs import Construct


class GpuWorkloadStack(Stack):
    """
    Stack for GPU-accelerated workloads using EC2 P4 and G4 instances.
    
    This stack creates:
    - VPC with public subnets for GPU instances
    - Security groups with appropriate access rules
    - IAM roles and policies for GPU instances
    - P4 instances for ML training
    - G4 instances for inference/graphics
    - CloudWatch monitoring and dashboards
    - SNS notifications for alerts
    - Lambda functions for cost optimization
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        notification_email: str,
        enable_spot_instances: bool = True,
        p4_instance_count: int = 1,
        g4_instance_count: int = 2,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Store configuration parameters
        self.notification_email = notification_email
        self.enable_spot_instances = enable_spot_instances
        self.p4_instance_count = p4_instance_count
        self.g4_instance_count = g4_instance_count

        # Create VPC infrastructure
        self.vpc = self._create_vpc()
        
        # Create security infrastructure
        self.security_group = self._create_security_group()
        self.gpu_role = self._create_iam_role()
        self.key_pair = self._create_key_pair()
        
        # Create monitoring infrastructure
        self.sns_topic = self._create_sns_topic()
        
        # Create GPU instances
        self.p4_instances = self._create_p4_instances()
        self.g4_instances = self._create_g4_instances()
        
        # Create monitoring and alerting
        self.dashboard = self._create_cloudwatch_dashboard()
        self.alarms = self._create_cloudwatch_alarms()
        
        # Create cost optimization
        self.cost_optimizer = self._create_cost_optimizer()
        
        # Create outputs
        self._create_outputs()

    def _create_vpc(self) -> ec2.Vpc:
        """Create VPC with public subnets for GPU instances."""
        vpc = ec2.Vpc(
            self,
            "GpuWorkloadVpc",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=2,
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
        
        Tags.of(vpc).add("Name", "GPU-Workload-VPC")
        Tags.of(vpc).add("Purpose", "GPU-Computing")
        
        return vpc

    def _create_security_group(self) -> ec2.SecurityGroup:
        """Create security group for GPU instances."""
        sg = ec2.SecurityGroup(
            self,
            "GpuWorkloadSecurityGroup",
            vpc=self.vpc,
            description="Security group for GPU workload instances",
            allow_all_outbound=True,
        )
        
        # Allow SSH access (restrict source as needed)
        sg.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(22),
            description="SSH access for administration"
        )
        
        # Allow Jupyter/TensorBoard access within security group
        sg.add_ingress_rule(
            peer=sg,
            connection=ec2.Port.tcp(8888),
            description="Jupyter notebook access"
        )
        
        # Allow HTTPS access for downloading models/data
        sg.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(443),
            description="HTTPS access"
        )
        
        Tags.of(sg).add("Name", "GPU-Workload-SecurityGroup")
        
        return sg

    def _create_iam_role(self) -> iam.Role:
        """Create IAM role for GPU instances."""
        role = iam.Role(
            self,
            "GpuInstanceRole",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            description="IAM role for GPU workload instances",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "AmazonSSMManagedInstanceCore"
                ),
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "CloudWatchAgentServerPolicy"
                ),
            ],
        )
        
        # Add custom policy for GPU metrics and cost optimization
        gpu_policy = iam.PolicyDocument(
            statements=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "cloudwatch:PutMetricData",
                        "cloudwatch:GetMetricStatistics",
                        "cloudwatch:ListMetrics",
                        "ec2:DescribeInstances",
                        "ec2:DescribeTags",
                        "ec2:CreateTags",
                    ],
                    resources=["*"],
                ),
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "s3:GetObject",
                        "s3:PutObject",
                        "s3:ListBucket",
                    ],
                    resources=[
                        "arn:aws:s3:::*training-data*",
                        "arn:aws:s3:::*training-data*/*",
                        "arn:aws:s3:::*model-artifacts*",
                        "arn:aws:s3:::*model-artifacts*/*",
                    ],
                ),
            ]
        )
        
        iam.Policy(
            self,
            "GpuInstancePolicy",
            document=gpu_policy,
            roles=[role],
        )
        
        Tags.of(role).add("Purpose", "GPU-Computing")
        
        return role

    def _create_key_pair(self) -> ec2.KeyPair:
        """Create EC2 Key Pair for SSH access."""
        key_pair = ec2.KeyPair(
            self,
            "GpuWorkloadKeyPair",
            key_pair_name=f"gpu-workload-{self.stack_name.lower()}",
            type=ec2.KeyPairType.RSA,
            format=ec2.KeyPairFormat.PEM,
        )
        
        # Store private key in Systems Manager Parameter Store
        ssm.StringParameter(
            self,
            "GpuKeyPairParameter",
            parameter_name=f"/gpu-workload/{self.stack_name}/private-key",
            string_value=key_pair.private_key_value,
            description="Private key for GPU workload instances",
            tier=ssm.ParameterTier.ADVANCED,
        )
        
        Tags.of(key_pair).add("Purpose", "GPU-Computing")
        
        return key_pair

    def _create_sns_topic(self) -> sns.Topic:
        """Create SNS topic for GPU monitoring alerts."""
        topic = sns.Topic(
            self,
            "GpuAlertsStopicTopic",
            display_name="GPU Workload Alerts",
            description="Notifications for GPU workload monitoring",
        )
        
        # Subscribe email to topic
        topic.add_subscription(
            subs.EmailSubscription(self.notification_email)
        )
        
        Tags.of(topic).add("Purpose", "GPU-Monitoring")
        
        return topic

    def _get_user_data(self) -> str:
        """Generate user data script for GPU instance setup."""
        return """#!/bin/bash
yum update -y
yum install -y awscli htop nvtop

# Install NVIDIA drivers
aws s3 cp --recursive s3://ec2-linux-nvidia-drivers/latest/ .
chmod +x NVIDIA-Linux-x86_64*.run
./NVIDIA-Linux-x86_64*.run --silent

# Install Docker for containerized workloads
yum install -y docker
systemctl start docker
systemctl enable docker
usermod -aG docker ec2-user

# Install NVIDIA Container Toolkit
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | rpm --import -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.repo | \\
    tee /etc/yum.repos.d/nvidia-docker.repo
yum install -y nvidia-docker2
systemctl restart docker

# Install Python and ML frameworks
amazon-linux-extras install python3.8 -y
pip3 install torch torchvision torchaudio tensorflow-gpu jupyter matplotlib pandas numpy scipy scikit-learn

# Install CloudWatch agent
wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
rpm -U ./amazon-cloudwatch-agent.rpm

# Configure GPU monitoring
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'EOF'
{
    "agent": {
        "metrics_collection_interval": 60
    },
    "metrics": {
        "namespace": "GPU/EC2",
        "metrics_collected": {
            "nvidia_gpu": {
                "measurement": [
                    "utilization_gpu",
                    "utilization_memory",
                    "temperature_gpu",
                    "power_draw"
                ],
                "metrics_collection_interval": 60
            }
        }
    }
}
EOF

# Start CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \\
    -a fetch-config -m ec2 \\
    -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \\
    -s

# Create GPU monitoring script
cat > /home/ec2-user/monitor-gpu.py << 'EOF'
#!/usr/bin/env python3
import subprocess
import time
import boto3
from datetime import datetime

def get_gpu_metrics():
    try:
        result = subprocess.run([
            'nvidia-smi', 
            '--query-gpu=utilization.gpu,utilization.memory,temperature.gpu,power.draw',
            '--format=csv,noheader,nounits'
        ], capture_output=True, text=True)
        
        if result.returncode == 0:
            metrics = result.stdout.strip().split(', ')
            return {
                'gpu_util': float(metrics[0]) if metrics[0] != 'N/A' else 0,
                'mem_util': float(metrics[1]) if metrics[1] != 'N/A' else 0,
                'temperature': float(metrics[2]) if metrics[2] != 'N/A' else 0,
                'power_draw': float(metrics[3]) if metrics[3] != 'N/A' else 0
            }
    except Exception as e:
        print(f"Error getting GPU metrics: {e}")
    return None

def send_custom_metrics(metrics, instance_id):
    cloudwatch = boto3.client('cloudwatch')
    
    try:
        cloudwatch.put_metric_data(
            Namespace='GPU/Custom',
            MetricData=[
                {
                    'MetricName': 'GPUUtilization',
                    'Value': metrics['gpu_util'],
                    'Unit': 'Percent',
                    'Dimensions': [{'Name': 'InstanceId', 'Value': instance_id}]
                },
                {
                    'MetricName': 'GPUMemoryUtilization',
                    'Value': metrics['mem_util'],
                    'Unit': 'Percent',
                    'Dimensions': [{'Name': 'InstanceId', 'Value': instance_id}]
                },
                {
                    'MetricName': 'GPUTemperature',
                    'Value': metrics['temperature'],
                    'Unit': 'None',
                    'Dimensions': [{'Name': 'InstanceId', 'Value': instance_id}]
                },
                {
                    'MetricName': 'GPUPowerDraw',
                    'Value': metrics['power_draw'],
                    'Unit': 'None',
                    'Dimensions': [{'Name': 'InstanceId', 'Value': instance_id}]
                }
            ]
        )
    except Exception as e:
        print(f"Error sending metrics: {e}")

if __name__ == "__main__":
    try:
        result = subprocess.run([
            'curl', '-s', 'http://169.254.169.254/latest/meta-data/instance-id'
        ], capture_output=True, text=True)
        instance_id = result.stdout.strip()
    except:
        instance_id = "unknown"
    
    while True:
        metrics = get_gpu_metrics()
        if metrics:
            send_custom_metrics(metrics, instance_id)
            print(f"{datetime.now()}: {metrics}")
        time.sleep(60)
EOF

chmod +x /home/ec2-user/monitor-gpu.py
chown ec2-user:ec2-user /home/ec2-user/monitor-gpu.py

# Start GPU monitoring as a service
cat > /etc/systemd/system/gpu-monitor.service << 'EOF'
[Unit]
Description=GPU Monitoring Service
After=network.target

[Service]
Type=simple
User=ec2-user
ExecStart=/usr/bin/python3 /home/ec2-user/monitor-gpu.py
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF

systemctl enable gpu-monitor
systemctl start gpu-monitor

echo "GPU setup completed" > /tmp/gpu-setup-complete
"""

    def _create_p4_instances(self) -> List[ec2.Instance]:
        """Create P4 instances for ML training workloads."""
        instances = []
        
        # Get the latest Deep Learning AMI
        ami = ec2.MachineImage.lookup(
            name="Deep Learning AMI*Ubuntu*",
            owners=["amazon"],
            filters={"state": ["available"]},
        )
        
        for i in range(self.p4_instance_count):
            instance = ec2.Instance(
                self,
                f"P4Instance{i+1}",
                instance_type=ec2.InstanceType.of(
                    ec2.InstanceClass.P4D, ec2.InstanceSize.XLARGE24
                ),
                machine_image=ami,
                vpc=self.vpc,
                security_group=self.security_group,
                role=self.gpu_role,
                key_name=self.key_pair.key_pair_name,
                user_data=ec2.UserData.custom(self._get_user_data()),
                vpc_subnets=ec2.SubnetSelection(
                    subnet_type=ec2.SubnetType.PUBLIC
                ),
                detailed_monitoring=True,
            )
            
            Tags.of(instance).add("Name", f"P4-ML-Training-{i+1}")
            Tags.of(instance).add("Purpose", "GPU-Workload")
            Tags.of(instance).add("InstanceType", "P4-Training")
            
            instances.append(instance)
        
        return instances

    def _create_g4_instances(self) -> List[ec2.Instance]:
        """Create G4 instances for inference and graphics workloads."""
        instances = []
        
        # Get the latest Deep Learning AMI
        ami = ec2.MachineImage.lookup(
            name="Deep Learning AMI*Ubuntu*",
            owners=["amazon"],
            filters={"state": ["available"]},
        )
        
        for i in range(self.g4_instance_count):
            if self.enable_spot_instances:
                # Create Spot instances for cost optimization
                instance = ec2.Instance(
                    self,
                    f"G4SpotInstance{i+1}",
                    instance_type=ec2.InstanceType.of(
                        ec2.InstanceClass.G4DN, ec2.InstanceSize.XLARGE
                    ),
                    machine_image=ami,
                    vpc=self.vpc,
                    security_group=self.security_group,
                    role=self.gpu_role,
                    key_name=self.key_pair.key_pair_name,
                    user_data=ec2.UserData.custom(self._get_user_data()),
                    vpc_subnets=ec2.SubnetSelection(
                        subnet_type=ec2.SubnetType.PUBLIC
                    ),
                    detailed_monitoring=True,
                    spot_options=ec2.SpotOptions(
                        max_price=0.50,  # Maximum price per hour
                        spot_instance_type=ec2.SpotInstanceType.ONE_TIME,
                        interruption_behavior=ec2.SpotInstanceInterruption.TERMINATE,
                    ),
                )
                
                Tags.of(instance).add("Name", f"G4-Spot-Inference-{i+1}")
            else:
                # Create On-Demand instances
                instance = ec2.Instance(
                    self,
                    f"G4Instance{i+1}",
                    instance_type=ec2.InstanceType.of(
                        ec2.InstanceClass.G4DN, ec2.InstanceSize.XLARGE
                    ),
                    machine_image=ami,
                    vpc=self.vpc,
                    security_group=self.security_group,
                    role=self.gpu_role,
                    key_name=self.key_pair.key_pair_name,
                    user_data=ec2.UserData.custom(self._get_user_data()),
                    vpc_subnets=ec2.SubnetSelection(
                        subnet_type=ec2.SubnetType.PUBLIC
                    ),
                    detailed_monitoring=True,
                )
                
                Tags.of(instance).add("Name", f"G4-Inference-{i+1}")
            
            Tags.of(instance).add("Purpose", "GPU-Workload")
            Tags.of(instance).add("InstanceType", "G4-Inference")
            
            instances.append(instance)
        
        return instances

    def _create_cloudwatch_dashboard(self) -> cloudwatch.Dashboard:
        """Create CloudWatch dashboard for GPU monitoring."""
        dashboard = cloudwatch.Dashboard(
            self,
            "GpuWorkloadDashboard",
            dashboard_name="GPU-Workload-Monitoring",
            period_override=cloudwatch.PeriodOverride.AUTO,
        )
        
        # Create widgets for each P4 instance
        for i, instance in enumerate(self.p4_instances):
            dashboard.add_widgets(
                cloudwatch.GraphWidget(
                    title=f"P4 Instance {i+1} - GPU Utilization",
                    left=[
                        cloudwatch.Metric(
                            namespace="GPU/EC2",
                            metric_name="utilization_gpu",
                            dimensions_map={"InstanceId": instance.instance_id},
                            statistic="Average",
                        )
                    ],
                    width=12,
                    height=6,
                ),
                cloudwatch.GraphWidget(
                    title=f"P4 Instance {i+1} - GPU Memory",
                    left=[
                        cloudwatch.Metric(
                            namespace="GPU/EC2",
                            metric_name="utilization_memory",
                            dimensions_map={"InstanceId": instance.instance_id},
                            statistic="Average",
                        )
                    ],
                    width=12,
                    height=6,
                ),
            )
        
        # Create widgets for G4 instances
        for i, instance in enumerate(self.g4_instances):
            dashboard.add_widgets(
                cloudwatch.GraphWidget(
                    title=f"G4 Instance {i+1} - GPU Temperature",
                    left=[
                        cloudwatch.Metric(
                            namespace="GPU/EC2",
                            metric_name="temperature_gpu",
                            dimensions_map={"InstanceId": instance.instance_id},
                            statistic="Average",
                        )
                    ],
                    width=12,
                    height=6,
                ),
                cloudwatch.GraphWidget(
                    title=f"G4 Instance {i+1} - Power Draw",
                    left=[
                        cloudwatch.Metric(
                            namespace="GPU/EC2",
                            metric_name="power_draw",
                            dimensions_map={"InstanceId": instance.instance_id},
                            statistic="Average",
                        )
                    ],
                    width=12,
                    height=6,
                ),
            )
        
        return dashboard

    def _create_cloudwatch_alarms(self) -> List[cloudwatch.Alarm]:
        """Create CloudWatch alarms for GPU monitoring."""
        alarms = []
        
        all_instances = self.p4_instances + self.g4_instances
        
        for instance in all_instances:
            # High temperature alarm
            temp_alarm = cloudwatch.Alarm(
                self,
                f"HighTemperatureAlarm{instance.instance_id}",
                alarm_name=f"GPU-High-Temperature-{instance.instance_id}",
                alarm_description=f"GPU temperature too high for {instance.instance_id}",
                metric=cloudwatch.Metric(
                    namespace="GPU/EC2",
                    metric_name="temperature_gpu",
                    dimensions_map={"InstanceId": instance.instance_id},
                    statistic="Average",
                ),
                threshold=85,
                comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
                evaluation_periods=2,
                datapoints_to_alarm=2,
            )
            
            temp_alarm.add_alarm_action(
                cw_actions.SnsAction(self.sns_topic)
            )
            
            # Low utilization alarm for cost optimization
            util_alarm = cloudwatch.Alarm(
                self,
                f"LowUtilizationAlarm{instance.instance_id}",
                alarm_name=f"GPU-Low-Utilization-{instance.instance_id}",
                alarm_description=f"GPU utilization too low for {instance.instance_id}",
                metric=cloudwatch.Metric(
                    namespace="GPU/EC2",
                    metric_name="utilization_gpu",
                    dimensions_map={"InstanceId": instance.instance_id},
                    statistic="Average",
                    period=Duration.minutes(30),
                ),
                threshold=10,
                comparison_operator=cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
                evaluation_periods=3,
                datapoints_to_alarm=3,
            )
            
            util_alarm.add_alarm_action(
                cw_actions.SnsAction(self.sns_topic)
            )
            
            alarms.extend([temp_alarm, util_alarm])
        
        return alarms

    def _create_cost_optimizer(self) -> _lambda.Function:
        """Create Lambda function for cost optimization."""
        # Create Lambda function
        cost_optimizer = _lambda.Function(
            self,
            "CostOptimizer",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline("""
import boto3
import json
from datetime import datetime, timedelta

def lambda_handler(event, context):
    ec2 = boto3.client('ec2')
    cloudwatch = boto3.client('cloudwatch')
    
    # Get GPU instances
    instances = ec2.describe_instances(
        Filters=[
            {'Name': 'tag:Purpose', 'Values': ['GPU-Workload']},
            {'Name': 'instance-state-name', 'Values': ['running']}
        ]
    )
    
    results = []
    
    for reservation in instances['Reservations']:
        for instance in reservation['Instances']:
            instance_id = instance['InstanceId']
            
            # Check GPU utilization over last hour
            end_time = datetime.utcnow()
            start_time = end_time - timedelta(hours=1)
            
            try:
                metrics = cloudwatch.get_metric_statistics(
                    Namespace='GPU/EC2',
                    MetricName='utilization_gpu',
                    Dimensions=[
                        {'Name': 'InstanceId', 'Value': instance_id}
                    ],
                    StartTime=start_time,
                    EndTime=end_time,
                    Period=300,
                    Statistics=['Average']
                )
                
                if metrics['Datapoints']:
                    avg_util = sum(dp['Average'] for dp in metrics['Datapoints']) / len(metrics['Datapoints'])
                    
                    result = {
                        'InstanceId': instance_id,
                        'AvgUtilization': avg_util,
                        'Action': 'none'
                    }
                    
                    # If utilization < 5% for an hour, tag for review
                    if avg_util < 5:
                        print(f"Low utilization detected for {instance_id}: {avg_util}%. Tagging for review.")
                        
                        # Add tag for review
                        ec2.create_tags(
                            Resources=[instance_id],
                            Tags=[
                                {'Key': 'LowUtilization', 'Value': str(datetime.now())},
                                {'Key': 'ReviewForTermination', 'Value': 'true'}
                            ]
                        )
                        result['Action'] = 'tagged_for_review'
                    
                    results.append(result)
                
            except Exception as e:
                print(f"Error checking metrics for {instance_id}: {e}")
                results.append({
                    'InstanceId': instance_id,
                    'Error': str(e)
                })
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Cost optimization check completed',
            'results': results
        })
    }
            """),
            description="Lambda function for GPU cost optimization",
            timeout=Duration.minutes(5),
            log_retention=logs.RetentionDays.ONE_WEEK,
        )
        
        # Grant permissions to Lambda
        cost_optimizer.add_to_role_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "ec2:DescribeInstances",
                    "ec2:CreateTags",
                    "cloudwatch:GetMetricStatistics",
                ],
                resources=["*"],
            )
        )
        
        # Create EventBridge rule to run every hour
        rule = events.Rule(
            self,
            "CostOptimizerSchedule",
            schedule=events.Schedule.rate(Duration.hours(1)),
            description="Trigger cost optimizer every hour",
        )
        
        rule.add_target(targets.LambdaFunction(cost_optimizer))
        
        Tags.of(cost_optimizer).add("Purpose", "Cost-Optimization")
        
        return cost_optimizer

    def _create_outputs(self) -> None:
        """Create stack outputs."""
        # VPC outputs
        cdk.CfnOutput(
            self,
            "VpcId",
            value=self.vpc.vpc_id,
            description="VPC ID for GPU workloads",
        )
        
        # Security Group output
        cdk.CfnOutput(
            self,
            "SecurityGroupId",
            value=self.security_group.security_group_id,
            description="Security Group ID for GPU instances",
        )
        
        # Key Pair output
        cdk.CfnOutput(
            self,
            "KeyPairName",
            value=self.key_pair.key_pair_name,
            description="Key Pair name for SSH access",
        )
        
        # Instance outputs
        for i, instance in enumerate(self.p4_instances):
            cdk.CfnOutput(
                self,
                f"P4Instance{i+1}Id",
                value=instance.instance_id,
                description=f"P4 Instance {i+1} ID",
            )
            
            cdk.CfnOutput(
                self,
                f"P4Instance{i+1}PublicIp",
                value=instance.instance_public_ip,
                description=f"P4 Instance {i+1} Public IP",
            )
        
        for i, instance in enumerate(self.g4_instances):
            cdk.CfnOutput(
                self,
                f"G4Instance{i+1}Id",
                value=instance.instance_id,
                description=f"G4 Instance {i+1} ID",
            )
            
            cdk.CfnOutput(
                self,
                f"G4Instance{i+1}PublicIp",
                value=instance.instance_public_ip,
                description=f"G4 Instance {i+1} Public IP",
            )
        
        # Dashboard output
        cdk.CfnOutput(
            self,
            "DashboardUrl",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.dashboard.dashboard_name}",
            description="CloudWatch Dashboard URL",
        )
        
        # SNS Topic output
        cdk.CfnOutput(
            self,
            "SnsTopicArn",
            value=self.sns_topic.topic_arn,
            description="SNS Topic ARN for alerts",
        )


class GpuWorkloadApp(cdk.App):
    """CDK Application for GPU Workload Infrastructure."""
    
    def __init__(self) -> None:
        super().__init__()
        
        # Get configuration from context or environment
        notification_email = self.node.try_get_context("notification_email") or os.environ.get("NOTIFICATION_EMAIL", "admin@example.com")
        enable_spot_instances = self.node.try_get_context("enable_spot_instances") or True
        p4_instance_count = int(self.node.try_get_context("p4_instance_count") or 1)
        g4_instance_count = int(self.node.try_get_context("g4_instance_count") or 2)
        
        # Create the main stack
        stack = GpuWorkloadStack(
            self,
            "GpuWorkloadStack",
            notification_email=notification_email,
            enable_spot_instances=enable_spot_instances,
            p4_instance_count=p4_instance_count,
            g4_instance_count=g4_instance_count,
            description="GPU-accelerated workloads infrastructure with P4 and G4 instances",
            env=cdk.Environment(
                account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
                region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
            ),
        )
        
        # Add stack-level tags
        Tags.of(stack).add("Project", "GPU-Workloads")
        Tags.of(stack).add("Environment", "Production")
        Tags.of(stack).add("Owner", "ML-Team")
        Tags.of(stack).add("CostCenter", "Research")


if __name__ == "__main__":
    app = GpuWorkloadApp()
    app.synth()