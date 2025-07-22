#!/usr/bin/env python3
"""
CDK Application for EC2 Hibernation Cost Optimization

This CDK application creates an EC2 instance with hibernation capabilities
along with CloudWatch monitoring and SNS notifications for cost optimization.
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_ec2 as ec2,
    aws_sns as sns,
    aws_cloudwatch as cloudwatch,
    aws_iam as iam,
    Duration,
    RemovalPolicy,
    CfnOutput,
    Tags,
)
from constructs import Construct


class EC2HibernationCostOptimizationStack(Stack):
    """
    Stack for EC2 Hibernation Cost Optimization
    
    This stack creates:
    - EC2 instance with hibernation enabled
    - CloudWatch alarms for monitoring
    - SNS topic for notifications
    - IAM roles and security groups
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        notification_email: str,
        **kwargs: Any
    ) -> None:
        """
        Initialize the EC2 Hibernation Cost Optimization stack.
        
        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            notification_email: Email address for SNS notifications
            **kwargs: Additional keyword arguments
        """
        super().__init__(scope, construct_id, **kwargs)

        # Create SNS topic for notifications
        self.notification_topic = self._create_sns_topic(notification_email)

        # Create VPC and security group
        self.vpc = self._create_vpc()
        self.security_group = self._create_security_group()

        # Create key pair for EC2 access
        self.key_pair = self._create_key_pair()

        # Create EC2 instance with hibernation enabled
        self.ec2_instance = self._create_ec2_instance()

        # Create CloudWatch alarms
        self._create_cloudwatch_alarms()

        # Create outputs
        self._create_outputs()

        # Add tags to all resources
        self._add_stack_tags()

    def _create_sns_topic(self, notification_email: str) -> sns.Topic:
        """Create SNS topic for notifications."""
        topic = sns.Topic(
            self,
            "HibernationNotificationTopic",
            display_name="EC2 Hibernation Notifications",
            topic_name=f"hibernation-notifications-{self.stack_name.lower()}",
        )

        # Add email subscription
        topic.add_subscription(
            sns.EmailSubscription(notification_email)
        )

        return topic

    def _create_vpc(self) -> ec2.Vpc:
        """Create VPC for the EC2 instance."""
        vpc = ec2.Vpc(
            self,
            "HibernationVPC",
            max_azs=2,
            nat_gateways=1,
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="Public",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24,
                ),
                ec2.SubnetConfiguration(
                    name="Private",
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                    cidr_mask=24,
                ),
            ],
            enable_dns_hostnames=True,
            enable_dns_support=True,
        )

        return vpc

    def _create_security_group(self) -> ec2.SecurityGroup:
        """Create security group for EC2 instance."""
        security_group = ec2.SecurityGroup(
            self,
            "HibernationSecurityGroup",
            vpc=self.vpc,
            description="Security group for hibernation demo instance",
            allow_all_outbound=True,
        )

        # Allow SSH access from anywhere (for demo purposes)
        # In production, restrict to specific IP ranges
        security_group.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(22),
            description="SSH access",
        )

        return security_group

    def _create_key_pair(self) -> ec2.KeyPair:
        """Create EC2 key pair for instance access."""
        key_pair = ec2.KeyPair(
            self,
            "HibernationKeyPair",
            key_pair_name=f"hibernate-demo-key-{self.stack_name.lower()}",
            type=ec2.KeyPairType.RSA,
        )

        return key_pair

    def _create_ec2_instance(self) -> ec2.Instance:
        """Create EC2 instance with hibernation enabled."""
        # Get the latest Amazon Linux 2 AMI
        amzn_linux = ec2.MachineImage.latest_amazon_linux2(
            generation=ec2.AmazonLinuxGeneration.AMAZON_LINUX_2,
        )

        # Create IAM role for EC2 instance
        instance_role = iam.Role(
            self,
            "HibernationInstanceRole",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "AmazonSSMManagedInstanceCore"
                ),
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "CloudWatchAgentServerPolicy"
                ),
            ],
        )

        # Create EC2 instance with hibernation enabled
        instance = ec2.Instance(
            self,
            "HibernationInstance",
            instance_type=ec2.InstanceType.of(
                ec2.InstanceClass.M5, ec2.InstanceSize.LARGE
            ),
            machine_image=amzn_linux,
            vpc=self.vpc,
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PUBLIC
            ),
            security_group=self.security_group,
            key_name=self.key_pair.key_pair_name,
            role=instance_role,
            block_devices=[
                ec2.BlockDevice(
                    device_name="/dev/xvda",
                    volume=ec2.BlockDeviceVolume.ebs(
                        volume_size=30,
                        volume_type=ec2.EbsDeviceVolumeType.GP3,
                        encrypted=True,
                        delete_on_termination=True,
                    ),
                )
            ],
            user_data=ec2.UserData.for_linux(),
            require_imdsv2=True,
        )

        # Configure hibernation using escape hatch
        cfn_instance = instance.node.default_child
        cfn_instance.hibernation_options = {"Configured": True}

        return instance

    def _create_cloudwatch_alarms(self) -> None:
        """Create CloudWatch alarms for monitoring."""
        # Low CPU utilization alarm
        low_cpu_alarm = cloudwatch.Alarm(
            self,
            "LowCPUAlarm",
            alarm_name=f"LowCPU-{self.ec2_instance.instance_id}",
            alarm_description="Alarm when CPU utilization is low",
            metric=cloudwatch.Metric(
                namespace="AWS/EC2",
                metric_name="CPUUtilization",
                dimensions_map={"InstanceId": self.ec2_instance.instance_id},
                statistic="Average",
                period=Duration.minutes(5),
            ),
            threshold=10,
            comparison_operator=cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
            evaluation_periods=6,
            datapoints_to_alarm=6,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

        # Add SNS action to alarm
        low_cpu_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.notification_topic)
        )

        # High CPU utilization alarm (for resume notifications)
        high_cpu_alarm = cloudwatch.Alarm(
            self,
            "HighCPUAlarm",
            alarm_name=f"HighCPU-{self.ec2_instance.instance_id}",
            alarm_description="Alarm when CPU utilization is high after resume",
            metric=cloudwatch.Metric(
                namespace="AWS/EC2",
                metric_name="CPUUtilization",
                dimensions_map={"InstanceId": self.ec2_instance.instance_id},
                statistic="Average",
                period=Duration.minutes(5),
            ),
            threshold=80,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=2,
            datapoints_to_alarm=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

        # Add SNS action to alarm
        high_cpu_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.notification_topic)
        )

    def _create_outputs(self) -> None:
        """Create stack outputs."""
        CfnOutput(
            self,
            "InstanceId",
            value=self.ec2_instance.instance_id,
            description="EC2 Instance ID",
        )

        CfnOutput(
            self,
            "KeyPairName",
            value=self.key_pair.key_pair_name,
            description="EC2 Key Pair Name",
        )

        CfnOutput(
            self,
            "PublicIP",
            value=self.ec2_instance.instance_public_ip,
            description="EC2 Instance Public IP",
        )

        CfnOutput(
            self,
            "PrivateIP",
            value=self.ec2_instance.instance_private_ip,
            description="EC2 Instance Private IP",
        )

        CfnOutput(
            self,
            "SNSTopicArn",
            value=self.notification_topic.topic_arn,
            description="SNS Topic ARN for notifications",
        )

        CfnOutput(
            self,
            "SSHCommand",
            value=f"ssh -i {self.key_pair.key_pair_name}.pem ec2-user@{self.ec2_instance.instance_public_ip}",
            description="SSH command to connect to the instance",
        )

        CfnOutput(
            self,
            "HibernateCommand",
            value=f"aws ec2 stop-instances --instance-ids {self.ec2_instance.instance_id} --hibernate",
            description="Command to hibernate the instance",
        )

        CfnOutput(
            self,
            "ResumeCommand",
            value=f"aws ec2 start-instances --instance-ids {self.ec2_instance.instance_id}",
            description="Command to resume the instance",
        )

    def _add_stack_tags(self) -> None:
        """Add tags to all resources in the stack."""
        Tags.of(self).add("Project", "EC2HibernationCostOptimization")
        Tags.of(self).add("Environment", "Demo")
        Tags.of(self).add("Purpose", "Cost Optimization")
        Tags.of(self).add("Owner", "CloudRecipes")


class EC2HibernationApp(cdk.App):
    """CDK Application for EC2 Hibernation Cost Optimization."""

    def __init__(self) -> None:
        """Initialize the CDK application."""
        super().__init__()

        # Get configuration from environment variables or context
        notification_email = self.node.try_get_context("notification_email") or os.environ.get(
            "NOTIFICATION_EMAIL", "admin@example.com"
        )
        
        stack_name = self.node.try_get_context("stack_name") or "EC2HibernationCostOptimization"
        
        env = cdk.Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
        )

        # Create the stack
        EC2HibernationCostOptimizationStack(
            self,
            stack_name,
            notification_email=notification_email,
            env=env,
            description="EC2 Hibernation Cost Optimization Stack - Deploy hibernation-enabled EC2 instances with monitoring",
        )


# Create and run the application
app = EC2HibernationApp()
app.synth()