#!/usr/bin/env python3
"""
CDK Python Application for Basic CloudWatch Monitoring with Alarms

This application creates a complete monitoring solution using Amazon CloudWatch
and SNS for automated alerting. It deploys the infrastructure described in the
"Basic Monitoring with CloudWatch Alarms" recipe.

The stack includes:
- SNS Topic for notifications
- Email subscription for alerts
- CloudWatch Alarms for EC2 CPU utilization
- CloudWatch Alarms for ALB response time
- CloudWatch Alarms for RDS database connections

Author: AWS CDK Team
Version: 1.0.0
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_cloudwatch as cloudwatch,
    aws_sns as sns,
    aws_sns_subscriptions as subscriptions,
    CfnParameter,
    CfnOutput,
    Tags,
)
from constructs import Construct
from typing import Optional
import os


class BasicMonitoringStack(Stack):
    """
    CDK Stack for basic CloudWatch monitoring with alarms and SNS notifications.
    
    This stack creates a comprehensive monitoring solution that includes:
    - An SNS topic for alert notifications
    - Email subscription for receiving alerts
    - CloudWatch alarms for various AWS services
    - Proper alarm configurations with best practices
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        notification_email: Optional[str] = None,
        **kwargs
    ) -> None:
        """
        Initialize the Basic Monitoring Stack.
        
        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            notification_email: Email address for notifications (optional)
            **kwargs: Additional keyword arguments
        """
        super().__init__(scope, construct_id, **kwargs)

        # Create parameter for notification email if not provided
        if notification_email:
            email_param_value = notification_email
        else:
            email_param = CfnParameter(
                self,
                "NotificationEmail",
                type="String",
                description="Email address to receive CloudWatch alarm notifications",
                constraint_description="Must be a valid email address",
                allowed_pattern=r"^[^\s@]+@[^\s@]+\.[^\s@]+$",
            )
            email_param_value = email_param.value_as_string

        # Create SNS topic for alarm notifications
        self.alarm_topic = sns.Topic(
            self,
            "MonitoringAlarmsTopic",
            display_name="CloudWatch Monitoring Alerts",
            topic_name="monitoring-alerts",
        )

        # Add email subscription to SNS topic
        self.alarm_topic.add_subscription(
            subscriptions.EmailSubscription(email_param_value)
        )

        # Create CloudWatch alarms
        self._create_ec2_cpu_alarm()
        self._create_alb_response_time_alarm()
        self._create_rds_connection_alarm()

        # Add tags to all resources
        Tags.of(self).add("Project", "BasicMonitoring")
        Tags.of(self).add("Environment", "Production")
        Tags.of(self).add("Owner", "Operations")
        Tags.of(self).add("CostCenter", "IT")

        # Create outputs
        self._create_outputs()

    def _create_ec2_cpu_alarm(self) -> None:
        """
        Create CloudWatch alarm for EC2 high CPU utilization.
        
        This alarm monitors average CPU utilization across all EC2 instances
        and triggers when usage exceeds 80% for two consecutive 5-minute periods.
        """
        self.cpu_alarm = cloudwatch.Alarm(
            self,
            "HighCPUUtilizationAlarm",
            alarm_name="HighCPUUtilization",
            alarm_description="Triggers when EC2 CPU exceeds 80%",
            metric=cloudwatch.Metric(
                namespace="AWS/EC2",
                metric_name="CPUUtilization",
                statistic="Average",
                period=cdk.Duration.minutes(5),
            ),
            threshold=80.0,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=2,
            datapoints_to_alarm=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

        # Add SNS action for alarm and OK states
        self.cpu_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.alarm_topic)
        )
        self.cpu_alarm.add_ok_action(
            cloudwatch.SnsAction(self.alarm_topic)
        )

    def _create_alb_response_time_alarm(self) -> None:
        """
        Create CloudWatch alarm for Application Load Balancer high response time.
        
        This alarm monitors average response time for ALB targets and triggers
        when response time exceeds 1 second for three consecutive periods.
        """
        self.response_time_alarm = cloudwatch.Alarm(
            self,
            "HighResponseTimeAlarm",
            alarm_name="HighResponseTime",
            alarm_description="Triggers when ALB response time exceeds 1 second",
            metric=cloudwatch.Metric(
                namespace="AWS/ApplicationELB",
                metric_name="TargetResponseTime",
                statistic="Average",
                period=cdk.Duration.minutes(5),
            ),
            threshold=1.0,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=3,
            datapoints_to_alarm=3,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

        # Add SNS action for alarm state only
        self.response_time_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.alarm_topic)
        )

    def _create_rds_connection_alarm(self) -> None:
        """
        Create CloudWatch alarm for RDS high database connections.
        
        This alarm monitors database connection count across all RDS instances
        and triggers when connections exceed 80 for two consecutive periods.
        """
        self.db_connection_alarm = cloudwatch.Alarm(
            self,
            "HighDBConnectionsAlarm",
            alarm_name="HighDBConnections",
            alarm_description="Triggers when RDS connections exceed 80% of max",
            metric=cloudwatch.Metric(
                namespace="AWS/RDS",
                metric_name="DatabaseConnections",
                statistic="Average",
                period=cdk.Duration.minutes(5),
            ),
            threshold=80.0,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=2,
            datapoints_to_alarm=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

        # Add SNS action for alarm state only
        self.db_connection_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.alarm_topic)
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        CfnOutput(
            self,
            "SNSTopicArn",
            description="ARN of the SNS topic for alarm notifications",
            value=self.alarm_topic.topic_arn,
        )

        CfnOutput(
            self,
            "SNSTopicName",
            description="Name of the SNS topic for alarm notifications",
            value=self.alarm_topic.topic_name,
        )

        CfnOutput(
            self,
            "CPUAlarmName",
            description="Name of the EC2 CPU utilization alarm",
            value=self.cpu_alarm.alarm_name,
        )

        CfnOutput(
            self,
            "ResponseTimeAlarmName",
            description="Name of the ALB response time alarm",
            value=self.response_time_alarm.alarm_name,
        )

        CfnOutput(
            self,
            "DBConnectionAlarmName",
            description="Name of the RDS database connection alarm",
            value=self.db_connection_alarm.alarm_name,
        )


class BasicMonitoringApp(cdk.App):
    """
    CDK Application for Basic CloudWatch Monitoring.
    
    This application creates a complete monitoring solution with CloudWatch
    alarms and SNS notifications following AWS best practices.
    """

    def __init__(self) -> None:
        """Initialize the CDK application."""
        super().__init__()

        # Get configuration from environment variables or context
        notification_email = (
            self.node.try_get_context("notification_email")
            or os.environ.get("NOTIFICATION_EMAIL")
        )

        # Create the monitoring stack
        BasicMonitoringStack(
            self,
            "BasicMonitoringStack",
            notification_email=notification_email,
            description="Basic CloudWatch monitoring with alarms and SNS notifications",
            env=cdk.Environment(
                account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
                region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
            ),
        )


def main() -> None:
    """
    Main entry point for the CDK application.
    
    This function creates and synthesizes the CDK application.
    """
    app = BasicMonitoringApp()
    app.synth()


if __name__ == "__main__":
    main()