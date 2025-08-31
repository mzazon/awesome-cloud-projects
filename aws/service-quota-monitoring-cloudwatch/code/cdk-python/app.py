#!/usr/bin/env python3
"""
AWS CDK Python application for Service Quota Monitoring with CloudWatch Alarms.

This application creates:
- SNS topic for quota alert notifications
- CloudWatch alarms for monitoring service quotas (EC2, VPC, Lambda)
- Email subscription to the SNS topic

Author: AWS CDK Python Generator
Version: 1.0
"""

import os
from typing import Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_sns as sns,
    aws_sns_subscriptions as subscriptions,
    aws_cloudwatch as cloudwatch,
    aws_cloudwatch_actions as cw_actions,
    CfnParameter,
    CfnOutput,
    Tags,
)
from constructs import Construct


class ServiceQuotaMonitoringStack(Stack):
    """
    CDK Stack for implementing service quota monitoring with CloudWatch alarms.
    
    This stack creates monitoring infrastructure to proactively alert when AWS
    service quotas approach their limits, enabling teams to take action before
    service disruptions occur.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        notification_email: Optional[str] = None,
        quota_threshold: float = 80.0,
        **kwargs
    ) -> None:
        """
        Initialize the Service Quota Monitoring Stack.
        
        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            notification_email: Email address for quota notifications
            quota_threshold: Threshold percentage for quota alerts (default: 80%)
            **kwargs: Additional keyword arguments
        """
        super().__init__(scope, construct_id, **kwargs)

        # Parameters for customization
        email_param = CfnParameter(
            self,
            "NotificationEmail",
            type="String",
            description="Email address to receive quota notifications",
            default=notification_email or "admin@example.com",
            constraint_description="Must be a valid email address",
        )

        threshold_param = CfnParameter(
            self,
            "QuotaThreshold",
            type="Number",
            description="Percentage threshold for quota alerts (0-100)",
            default=quota_threshold,
            min_value=0,
            max_value=100,
            constraint_description="Must be a number between 0 and 100",
        )

        # Create SNS topic for quota notifications
        self.quota_alert_topic = self._create_notification_topic(email_param)

        # Create CloudWatch alarms for various service quotas
        self._create_quota_alarms(threshold_param)

        # Add stack tags
        Tags.of(self).add("Project", "ServiceQuotaMonitoring")
        Tags.of(self).add("Environment", "Production")
        Tags.of(self).add("ManagedBy", "CDK")

    def _create_notification_topic(self, email_param: CfnParameter) -> sns.Topic:
        """
        Create SNS topic for quota notifications with email subscription.
        
        Args:
            email_param: CloudFormation parameter containing notification email
            
        Returns:
            SNS Topic for quota alerts
        """
        # Create SNS topic for quota alerts
        topic = sns.Topic(
            self,
            "QuotaAlertTopic",
            topic_name="service-quota-alerts",
            display_name="Service Quota Alerts",
            description="Notifications for AWS service quota threshold breaches",
        )

        # Add email subscription to SNS topic
        topic.add_subscription(
            subscriptions.EmailSubscription(email_param.value_as_string)
        )

        # Output SNS topic ARN
        CfnOutput(
            self,
            "SNSTopicArn",
            value=topic.topic_arn,
            description="ARN of the SNS topic for quota alerts",
            export_name=f"{self.stack_name}-SNSTopicArn",
        )

        return topic

    def _create_quota_alarms(self, threshold_param: CfnParameter) -> None:
        """
        Create CloudWatch alarms for monitoring service quotas.
        
        Args:
            threshold_param: CloudFormation parameter for quota threshold percentage
        """
        # Common alarm properties
        alarm_action = cw_actions.SnsAction(self.quota_alert_topic)
        
        # EC2 Running Instances Quota Alarm
        ec2_alarm = cloudwatch.Alarm(
            self,
            "EC2RunningInstancesQuotaAlarm",
            alarm_name="EC2-Running-Instances-Quota-Alert",
            alarm_description="Alert when EC2 running instances exceed quota threshold",
            metric=cloudwatch.Metric(
                namespace="AWS/ServiceQuotas",
                metric_name="ServiceQuotaUtilization",
                dimensions_map={
                    "ServiceCode": "ec2",
                    "QuotaCode": "L-1216C47A",  # Running On-Demand instances
                },
                statistic="Maximum",
                period=cdk.Duration.minutes(5),
            ),
            threshold=threshold_param.value_as_number,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=1,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )
        ec2_alarm.add_alarm_action(alarm_action)

        # VPC Quota Alarm
        vpc_alarm = cloudwatch.Alarm(
            self,
            "VPCQuotaAlarm",
            alarm_name="VPC-Quota-Alert",
            alarm_description="Alert when VPC count exceeds quota threshold",
            metric=cloudwatch.Metric(
                namespace="AWS/ServiceQuotas",
                metric_name="ServiceQuotaUtilization",
                dimensions_map={
                    "ServiceCode": "vpc",
                    "QuotaCode": "L-F678F1CE",  # VPCs per Region
                },
                statistic="Maximum",
                period=cdk.Duration.minutes(5),
            ),
            threshold=threshold_param.value_as_number,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=1,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )
        vpc_alarm.add_alarm_action(alarm_action)

        # Lambda Concurrent Executions Quota Alarm
        lambda_alarm = cloudwatch.Alarm(
            self,
            "LambdaConcurrentExecutionsQuotaAlarm",
            alarm_name="Lambda-Concurrent-Executions-Quota-Alert",
            alarm_description="Alert when Lambda concurrent executions exceed quota threshold",
            metric=cloudwatch.Metric(
                namespace="AWS/ServiceQuotas",
                metric_name="ServiceQuotaUtilization",
                dimensions_map={
                    "ServiceCode": "lambda",
                    "QuotaCode": "L-B99A9384",  # Concurrent executions
                },
                statistic="Maximum",
                period=cdk.Duration.minutes(5),
            ),
            threshold=threshold_param.value_as_number,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=1,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )
        lambda_alarm.add_alarm_action(alarm_action)

        # Output alarm names for reference
        CfnOutput(
            self,
            "EC2AlarmName",
            value=ec2_alarm.alarm_name,
            description="Name of the EC2 quota alarm",
        )

        CfnOutput(
            self,
            "VPCAlarmName",
            value=vpc_alarm.alarm_name,
            description="Name of the VPC quota alarm",
        )

        CfnOutput(
            self,
            "LambdaAlarmName",
            value=lambda_alarm.alarm_name,
            description="Name of the Lambda quota alarm",
        )


class ServiceQuotaMonitoringApp(cdk.App):
    """
    CDK Application for Service Quota Monitoring.
    
    This application creates the complete infrastructure stack for monitoring
    AWS service quotas and sending notifications when thresholds are exceeded.
    """

    def __init__(self) -> None:
        """Initialize the CDK application."""
        super().__init__()

        # Get configuration from environment variables or use defaults
        notification_email = os.environ.get("NOTIFICATION_EMAIL", "admin@example.com")
        quota_threshold = float(os.environ.get("QUOTA_THRESHOLD", "80.0"))
        
        # Get AWS account and region from environment
        account = os.environ.get("CDK_DEFAULT_ACCOUNT")
        region = os.environ.get("CDK_DEFAULT_REGION", "us-east-1")

        # Create the service quota monitoring stack
        ServiceQuotaMonitoringStack(
            self,
            "ServiceQuotaMonitoringStack",
            notification_email=notification_email,
            quota_threshold=quota_threshold,
            env=cdk.Environment(account=account, region=region),
            description="Infrastructure for monitoring AWS service quotas with CloudWatch alarms",
        )


# Application entry point
app = ServiceQuotaMonitoringApp()
app.synth()