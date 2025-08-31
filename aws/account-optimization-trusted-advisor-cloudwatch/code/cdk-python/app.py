#!/usr/bin/env python3
"""
AWS CDK Python Application for Account Optimization Monitoring
This application creates AWS resources to monitor Trusted Advisor checks and send
notifications when optimization opportunities are identified.
"""

import aws_cdk as cdk
from aws_cdk import (
    App,
    Environment,
    Stack,
    CfnParameter,
    CfnOutput,
    aws_sns as sns,
    aws_cloudwatch as cloudwatch,
    aws_sns_subscriptions as sns_subscriptions,
    Duration,
    Aws
)
from typing import Optional
from constructs import Construct


class TrustedAdvisorMonitoringStack(Stack):
    """
    CDK Stack for AWS Trusted Advisor monitoring with CloudWatch alarms and SNS notifications.
    
    This stack creates:
    - SNS topic for alerts
    - CloudWatch alarms for different Trusted Advisor checks
    - Email subscription to SNS topic
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        email_address: Optional[str] = None,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # CloudFormation parameter for email address
        email_param = CfnParameter(
            self,
            "EmailAddress",
            type="String",
            description="Email address for receiving Trusted Advisor alerts",
            constraint_description="Must be a valid email address",
            default=email_address or ""
        )

        # CloudFormation parameter for resource prefix
        resource_prefix_param = CfnParameter(
            self,
            "ResourcePrefix",
            type="String",
            description="Prefix for resource names to ensure uniqueness",
            default="trusted-advisor",
            min_length=1,
            max_length=20,
            allowed_pattern="^[a-zA-Z][a-zA-Z0-9-]*$",
            constraint_description="Must start with a letter and contain only alphanumeric characters and hyphens"
        )

        # Create SNS topic for Trusted Advisor alerts
        self.alert_topic = sns.Topic(
            self,
            "TrustedAdvisorAlertsTopic",
            topic_name=f"{resource_prefix_param.value_as_string}-alerts",
            display_name="AWS Account Optimization Alerts",
            description="SNS topic for AWS Trusted Advisor optimization alerts"
        )

        # Subscribe email address to SNS topic if provided
        if email_param.value_as_string:
            self.alert_topic.add_subscription(
                sns_subscriptions.EmailSubscription(
                    email_address=email_param.value_as_string
                )
            )

        # Create CloudWatch alarm for EC2 cost optimization
        self.cost_optimization_alarm = cloudwatch.Alarm(
            self,
            "CostOptimizationAlarm",
            alarm_name=f"{resource_prefix_param.value_as_string}-cost-optimization",
            alarm_description="Alert when Trusted Advisor identifies cost optimization opportunities",
            metric=cloudwatch.Metric(
                namespace="AWS/TrustedAdvisor",
                metric_name="YellowResources",
                statistic="Average",
                period=Duration.minutes(5),
                dimensions_map={
                    "CheckName": "Low Utilization Amazon EC2 Instances"
                }
            ),
            threshold=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
            evaluation_periods=1,
            datapoints_to_alarm=1,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )

        # Add SNS action to cost optimization alarm
        self.cost_optimization_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.alert_topic)
        )

        # Create CloudWatch alarm for security recommendations
        self.security_alarm = cloudwatch.Alarm(
            self,
            "SecurityRecommendationsAlarm",
            alarm_name=f"{resource_prefix_param.value_as_string}-security",
            alarm_description="Alert when Trusted Advisor identifies security recommendations",
            metric=cloudwatch.Metric(
                namespace="AWS/TrustedAdvisor",
                metric_name="RedResources",
                statistic="Average",
                period=Duration.minutes(5),
                dimensions_map={
                    "CheckName": "Security Groups - Specific Ports Unrestricted"
                }
            ),
            threshold=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
            evaluation_periods=1,
            datapoints_to_alarm=1,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )

        # Add SNS action to security alarm
        self.security_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.alert_topic)
        )

        # Create CloudWatch alarm for service limits monitoring
        self.service_limits_alarm = cloudwatch.Alarm(
            self,
            "ServiceLimitsAlarm",
            alarm_name=f"{resource_prefix_param.value_as_string}-limits",
            alarm_description="Alert when service usage approaches limits",
            metric=cloudwatch.Metric(
                namespace="AWS/TrustedAdvisor",
                metric_name="ServiceLimitUsage",
                statistic="Average",
                period=Duration.minutes(5),
                dimensions_map={
                    "ServiceName": "EC2",
                    "ServiceLimit": "Running On-Demand EC2 Instances",
                    "Region": Aws.REGION
                }
            ),
            threshold=80,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=1,
            datapoints_to_alarm=1,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )

        # Add SNS action to service limits alarm
        self.service_limits_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.alert_topic)
        )

        # CloudFormation outputs
        CfnOutput(
            self,
            "SNSTopicArn",
            value=self.alert_topic.topic_arn,
            description="ARN of the SNS topic for Trusted Advisor alerts",
            export_name=f"{construct_id}-SNSTopicArn"
        )

        CfnOutput(
            self,
            "SNSTopicName",
            value=self.alert_topic.topic_name,
            description="Name of the SNS topic for Trusted Advisor alerts",
            export_name=f"{construct_id}-SNSTopicName"
        )

        CfnOutput(
            self,
            "CostOptimizationAlarmName",
            value=self.cost_optimization_alarm.alarm_name,
            description="Name of the cost optimization CloudWatch alarm",
            export_name=f"{construct_id}-CostOptimizationAlarmName"
        )

        CfnOutput(
            self,
            "SecurityAlarmName",
            value=self.security_alarm.alarm_name,
            description="Name of the security recommendations CloudWatch alarm",
            export_name=f"{construct_id}-SecurityAlarmName"
        )

        CfnOutput(
            self,
            "ServiceLimitsAlarmName",
            value=self.service_limits_alarm.alarm_name,
            description="Name of the service limits CloudWatch alarm",
            export_name=f"{construct_id}-ServiceLimitsAlarmName"
        )

        # Output for monitoring dashboard URL
        CfnOutput(
            self,
            "CloudWatchDashboardURL",
            value=f"https://{Aws.REGION}.console.aws.amazon.com/cloudwatch/home?region={Aws.REGION}#alarmsV2:search={resource_prefix_param.value_as_string}",
            description="URL to view CloudWatch alarms in AWS Console",
            export_name=f"{construct_id}-CloudWatchDashboardURL"
        )


def main() -> None:
    """
    Main entry point for the CDK application.
    """
    app = App()

    # Get email address from context variable or environment
    email_address = app.node.try_get_context("email_address")
    
    # Create the Trusted Advisor monitoring stack
    # Note: Trusted Advisor metrics are only available in us-east-1
    trusted_advisor_stack = TrustedAdvisorMonitoringStack(
        app,
        "TrustedAdvisorMonitoringStack",
        email_address=email_address,
        env=Environment(
            account=app.account,
            region="us-east-1"  # Required for Trusted Advisor
        ),
        description="AWS Trusted Advisor monitoring with CloudWatch alarms and SNS notifications",
        tags={
            "Project": "AccountOptimization",
            "Environment": app.node.try_get_context("environment") or "production",
            "Owner": "CloudOps",
            "CostCenter": app.node.try_get_context("cost_center") or "IT",
            "Purpose": "TrustedAdvisorMonitoring"
        }
    )

    # Add metadata to the stack
    trusted_advisor_stack.template_options.description = (
        "AWS CDK stack for monitoring AWS Trusted Advisor optimization "
        "recommendations with CloudWatch alarms and SNS notifications"
    )
    
    trusted_advisor_stack.template_options.template_format_version = "2010-09-09"

    app.synth()


if __name__ == "__main__":
    main()