#!/usr/bin/env python3
"""
CDK Python Application for Simple Resource Monitoring with CloudWatch and SNS

This CDK application creates:
- EC2 instance for monitoring
- SNS topic for notifications  
- Email subscription to SNS topic
- CloudWatch alarm for CPU utilization
- IAM role for EC2 instance with SSM permissions

The solution provides basic monitoring infrastructure that sends email alerts
when EC2 CPU utilization exceeds 70% for two consecutive 5-minute periods.
"""

import os
from typing import Optional

import aws_cdk as cdk
from aws_cdk import (
    App,
    CfnOutput,
    Duration,
    Environment,
    Stack,
    StackProps,
    Tags,
)
from aws_cdk import aws_cloudwatch as cloudwatch
from aws_cdk import aws_ec2 as ec2
from aws_cdk import aws_iam as iam
from aws_cdk import aws_sns as sns
from aws_cdk import aws_sns_subscriptions as sns_subs


class SimpleResourceMonitoringStack(Stack):
    """
    CDK Stack for Simple Resource Monitoring with CloudWatch and SNS
    
    This stack creates a complete monitoring solution including:
    - EC2 instance with CloudWatch monitoring enabled
    - SNS topic and email subscription for notifications
    - CloudWatch alarm that triggers on high CPU utilization
    - Appropriate IAM roles for EC2 Systems Manager access
    """

    def __init__(
        self, 
        scope: App, 
        construct_id: str, 
        email_address: str,
        instance_type: str = "t3.micro",
        cpu_threshold: float = 70.0,
        **kwargs
    ) -> None:
        """
        Initialize the Simple Resource Monitoring Stack
        
        Args:
            scope: CDK App scope
            construct_id: Unique identifier for this stack
            email_address: Email address for alarm notifications
            instance_type: EC2 instance type (default: t3.micro)
            cpu_threshold: CPU utilization threshold for alarm (default: 70.0)
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        unique_suffix = self.node.addr[-8:].lower()
        
        # Create VPC or use default VPC
        vpc = ec2.Vpc.from_lookup(self, "DefaultVPC", is_default=True)

        # Create IAM role for EC2 instance
        ec2_role = self._create_ec2_role(unique_suffix)

        # Create instance security group
        security_group = self._create_security_group(vpc, unique_suffix)

        # Create EC2 instance
        instance = self._create_ec2_instance(
            vpc, security_group, ec2_role, instance_type, unique_suffix
        )

        # Create SNS topic and subscription
        topic = self._create_sns_topic(email_address, unique_suffix)

        # Create CloudWatch alarm
        alarm = self._create_cloudwatch_alarm(
            instance, topic, cpu_threshold, unique_suffix
        )

        # Add tags to all resources
        self._add_tags()

        # Create stack outputs
        self._create_outputs(instance, topic, alarm, email_address)

    def _create_ec2_role(self, unique_suffix: str) -> iam.Role:
        """
        Create IAM role for EC2 instance with Systems Manager permissions
        
        Args:
            unique_suffix: Unique suffix for resource naming
            
        Returns:
            IAM Role for EC2 instance
        """
        role = iam.Role(
            self,
            "EC2MonitoringRole",
            role_name=f"EC2MonitoringRole-{unique_suffix}",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            description="IAM role for EC2 instance monitoring with SSM access",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "AmazonSSMManagedInstanceCore"
                ),
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "CloudWatchAgentServerPolicy"
                ),
            ],
        )

        return role

    def _create_security_group(self, vpc: ec2.IVpc, unique_suffix: str) -> ec2.SecurityGroup:
        """
        Create security group for EC2 instance
        
        Args:
            vpc: VPC where security group will be created
            unique_suffix: Unique suffix for resource naming
            
        Returns:
            Security Group for EC2 instance
        """
        security_group = ec2.SecurityGroup(
            self,
            "MonitoringInstanceSG",
            vpc=vpc,
            security_group_name=f"monitoring-instance-sg-{unique_suffix}",
            description="Security group for monitoring demo EC2 instance",
            allow_all_outbound=True,
        )

        # Add HTTPS outbound rule for SSM communication
        security_group.add_egress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(443),
            description="HTTPS outbound for SSM communication",
        )

        return security_group

    def _create_ec2_instance(
        self,
        vpc: ec2.IVpc,
        security_group: ec2.SecurityGroup,
        role: iam.Role,
        instance_type: str,
        unique_suffix: str,
    ) -> ec2.Instance:
        """
        Create EC2 instance for monitoring
        
        Args:
            vpc: VPC where instance will be created
            security_group: Security group for the instance
            role: IAM role for the instance
            instance_type: EC2 instance type
            unique_suffix: Unique suffix for resource naming
            
        Returns:
            EC2 Instance for monitoring
        """
        # Get latest Amazon Linux 2023 AMI
        amzn_linux = ec2.MachineImage.latest_amazon_linux2023(
            edition=ec2.AmazonLinuxEdition.STANDARD,
            virtualization=ec2.AmazonLinuxVirt.HVM,
            storage=ec2.AmazonLinuxStorage.GENERAL_PURPOSE,
        )

        # User data script for initial setup
        user_data = ec2.UserData.for_linux()
        user_data.add_commands(
            "#!/bin/bash",
            "yum update -y",
            "# Install stress-ng for testing CPU load",
            "yum install -y stress-ng",
            "# Enable detailed monitoring (1-minute intervals)",
            "echo 'Detailed monitoring enabled via CDK'",
        )

        # Create EC2 instance
        instance = ec2.Instance(
            self,
            "MonitoringInstance",
            instance_type=ec2.InstanceType(instance_type),
            machine_image=amzn_linux,
            vpc=vpc,
            security_group=security_group,
            role=role,
            user_data=user_data,
            vpc_subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PUBLIC),
            # Enable detailed monitoring for 1-minute metrics
            monitoring=ec2.Monitoring.DETAILED,
        )

        # Add name tag
        Tags.of(instance).add("Name", f"monitoring-demo-{unique_suffix}")

        return instance

    def _create_sns_topic(self, email_address: str, unique_suffix: str) -> sns.Topic:
        """
        Create SNS topic with email subscription
        
        Args:
            email_address: Email address for notifications
            unique_suffix: Unique suffix for resource naming
            
        Returns:
            SNS Topic for notifications
        """
        # Create SNS topic
        topic = sns.Topic(
            self,
            "CPUAlertsTopic",
            topic_name=f"cpu-alerts-{unique_suffix}",
            display_name="CPU Utilization Alerts",
            description="SNS topic for CPU utilization alarm notifications",
        )

        # Add email subscription
        topic.add_subscription(
            sns_subs.EmailSubscription(
                email_address=email_address,
                # Note: Email subscription requires manual confirmation
            )
        )

        return topic

    def _create_cloudwatch_alarm(
        self,
        instance: ec2.Instance,
        topic: sns.Topic,
        cpu_threshold: float,
        unique_suffix: str,
    ) -> cloudwatch.Alarm:
        """
        Create CloudWatch alarm for CPU utilization
        
        Args:
            instance: EC2 instance to monitor
            topic: SNS topic for notifications
            cpu_threshold: CPU utilization threshold
            unique_suffix: Unique suffix for resource naming
            
        Returns:
            CloudWatch Alarm for CPU monitoring
        """
        # Create CPU utilization metric
        cpu_metric = cloudwatch.Metric(
            namespace="AWS/EC2",
            metric_name="CPUUtilization",
            dimensions_map={"InstanceId": instance.instance_id},
            statistic="Average",
            period=Duration.minutes(5),
        )

        # Create CloudWatch alarm
        alarm = cloudwatch.Alarm(
            self,
            "HighCPUAlarm",
            alarm_name=f"high-cpu-{unique_suffix}",
            alarm_description=f"Alert when CPU exceeds {cpu_threshold}% for EC2 instance",
            metric=cpu_metric,
            threshold=cpu_threshold,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=2,
            datapoints_to_alarm=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

        # Add SNS action
        alarm.add_alarm_action(
            cloudwatch.SnsAction(topic)
        )

        return alarm

    def _add_tags(self) -> None:
        """Add common tags to all resources in the stack"""
        Tags.of(self).add("Project", "SimpleResourceMonitoring")
        Tags.of(self).add("Environment", "Demo")
        Tags.of(self).add("ManagedBy", "CDK")
        Tags.of(self).add("Recipe", "simple-resource-monitoring-cloudwatch-sns")

    def _create_outputs(
        self,
        instance: ec2.Instance,
        topic: sns.Topic,
        alarm: cloudwatch.Alarm,
        email_address: str,
    ) -> None:
        """
        Create CloudFormation outputs
        
        Args:
            instance: EC2 instance
            topic: SNS topic
            alarm: CloudWatch alarm
            email_address: Email address for notifications
        """
        CfnOutput(
            self,
            "InstanceId",
            value=instance.instance_id,
            description="EC2 Instance ID for monitoring",
            export_name=f"{self.stack_name}-InstanceId",
        )

        CfnOutput(
            self,
            "SNSTopicArn",
            value=topic.topic_arn,
            description="SNS Topic ARN for notifications",
            export_name=f"{self.stack_name}-SNSTopicArn",
        )

        CfnOutput(
            self,
            "AlarmName",
            value=alarm.alarm_name,
            description="CloudWatch Alarm Name",
            export_name=f"{self.stack_name}-AlarmName",
        )

        CfnOutput(
            self,
            "EmailAddress",
            value=email_address,
            description="Email address for notifications (requires confirmation)",
            export_name=f"{self.stack_name}-EmailAddress",
        )

        CfnOutput(
            self,
            "TestCommand",
            value=f"aws ssm send-command --document-name 'AWS-RunShellScript' --instance-ids {instance.instance_id} --parameters 'commands=[\"stress-ng --cpu 4 --timeout 600s\"]'",
            description="Command to test CPU alarm by generating load",
            export_name=f"{self.stack_name}-TestCommand",
        )


def main() -> None:
    """Main function to create and deploy the CDK application"""
    app = App()

    # Get email address from context or environment
    email_address = app.node.try_get_context("email_address")
    if not email_address:
        email_address = os.environ.get("EMAIL_ADDRESS")
    
    if not email_address:
        raise ValueError(
            "Email address is required. Set EMAIL_ADDRESS environment variable "
            "or pass -c email_address=your@email.com to cdk deploy"
        )

    # Get optional parameters
    instance_type = app.node.try_get_context("instance_type") or "t3.micro"
    cpu_threshold = float(app.node.try_get_context("cpu_threshold") or 70.0)

    # Create the stack
    SimpleResourceMonitoringStack(
        app,
        "SimpleResourceMonitoringStack",
        email_address=email_address,
        instance_type=instance_type,
        cpu_threshold=cpu_threshold,
        env=Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION"),
        ),
        description="Simple Resource Monitoring with CloudWatch and SNS - CDK Python",
    )

    app.synth()


if __name__ == "__main__":
    main()