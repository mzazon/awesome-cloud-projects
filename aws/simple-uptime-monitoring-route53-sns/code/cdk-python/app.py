#!/usr/bin/env python3
"""
AWS CDK Application for Simple Website Uptime Monitoring

This CDK application creates an automated uptime monitoring system using:
- Route53 health checks for continuous website monitoring
- CloudWatch alarms for health status evaluation
- SNS topics and email notifications for immediate alerting

The solution provides 24/7 monitoring with global health check locations,
immediate email alerts, and minimal operational overhead.

Author: AWS CDK Recipe Generator
Version: 1.0
"""

import os
from typing import Any, Dict, Optional

import aws_cdk as cdk
from aws_cdk import (
    App,
    CfnOutput,
    Environment,
    Stack,
    StackProps,
    Tags,
)
from aws_cdk import aws_cloudwatch as cloudwatch
from aws_cdk import aws_route53 as route53
from aws_cdk import aws_sns as sns
from aws_cdk import aws_sns_subscriptions as sns_subscriptions
from constructs import Construct
from cdk_nag import AwsSolutionsChecks, NagSuppressions


class UptimeMonitoringStack(Stack):
    """
    CDK Stack for Website Uptime Monitoring
    
    Creates a comprehensive monitoring solution with Route53 health checks,
    CloudWatch alarms, and SNS email notifications for automated website
    uptime monitoring and alerting.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        website_url: str,
        admin_email: str,
        **kwargs
    ) -> None:
        """
        Initialize the Uptime Monitoring Stack
        
        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            website_url: The website URL to monitor (HTTP or HTTPS)
            admin_email: Email address for receiving alerts
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)

        # Store configuration parameters
        self.website_url = website_url
        self.admin_email = admin_email
        
        # Parse URL components for health check configuration
        self.domain_name = self._extract_domain_from_url(website_url)
        self.is_https = website_url.startswith('https://')
        self.port = 443 if self.is_https else 80
        self.protocol = 'HTTPS' if self.is_https else 'HTTP'

        # Create the monitoring infrastructure
        self._create_sns_topic()
        self._create_health_check()
        self._create_cloudwatch_alarms()
        self._create_outputs()
        self._apply_tags()

    def _extract_domain_from_url(self, url: str) -> str:
        """
        Extract domain name from URL for health check configuration
        
        Args:
            url: Full website URL
            
        Returns:
            Domain name without protocol or path
        """
        # Remove protocol (http:// or https://)
        domain = url.replace('https://', '').replace('http://', '')
        # Remove path if present
        domain = domain.split('/')[0]
        return domain

    def _create_sns_topic(self) -> None:
        """
        Create SNS topic for email notifications
        
        Creates an SNS topic with email subscription for delivering
        uptime monitoring alerts to the specified admin email address.
        """
        # Create SNS topic for uptime alerts
        self.alert_topic = sns.Topic(
            self,
            "UptimeAlertTopic",
            display_name=f"Website Uptime Alerts - {self.domain_name}",
            topic_name=f"website-uptime-alerts-{self.domain_name.replace('.', '-')}",
        )

        # Subscribe email address to receive notifications
        self.alert_topic.add_subscription(
            sns_subscriptions.EmailSubscription(self.admin_email)
        )

        # Add tags for organization and cost allocation
        Tags.of(self.alert_topic).add("Purpose", "UptimeMonitoring")
        Tags.of(self.alert_topic).add("Environment", "Production")
        Tags.of(self.alert_topic).add("Service", "Monitoring")

    def _create_health_check(self) -> None:
        """
        Create Route53 health check for website monitoring
        
        Creates a health check that monitors the website from multiple
        global locations, checking availability every 30 seconds with
        a 3-failure threshold to prevent false positives.
        """
        # Create Route53 health check
        self.health_check = route53.CfnHealthCheck(
            self,
            "WebsiteHealthCheck",
            type=self.protocol,
            resource_path="/",
            fully_qualified_domain_name=self.domain_name,
            port=self.port,
            request_interval=30,  # Check every 30 seconds
            failure_threshold=3,  # 3 consecutive failures trigger alarm
            enable_sni=self.is_https,  # Enable SNI for HTTPS
            tags=[
                {
                    "key": "Name",
                    "value": f"health-check-{self.domain_name}"
                },
                {
                    "key": "Website",
                    "value": self.website_url
                },
                {
                    "key": "Purpose",
                    "value": "UptimeMonitoring"
                },
                {
                    "key": "Environment",
                    "value": "Production"
                }
            ]
        )

    def _create_cloudwatch_alarms(self) -> None:
        """
        Create CloudWatch alarms for health check monitoring
        
        Creates alarms for both website failure and recovery events,
        providing complete visibility into website availability status
        with SNS notifications for immediate alerting.
        """
        # Create alarm for website downtime detection
        self.downtime_alarm = cloudwatch.Alarm(
            self,
            "WebsiteDownAlarm",
            alarm_name=f"Website-Down-{self.domain_name}",
            alarm_description=f"Alert when website {self.website_url} is down",
            metric=cloudwatch.Metric(
                namespace="AWS/Route53",
                metric_name="HealthCheckStatus",
                dimensions_map={
                    "HealthCheckId": self.health_check.ref
                },
                statistic="Minimum",
                period=cdk.Duration.minutes(1)
            ),
            threshold=1,
            comparison_operator=cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
            evaluation_periods=1,
            treat_missing_data=cloudwatch.TreatMissingData.BREACHING,
        )

        # Add SNS notification for downtime alerts
        self.downtime_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.alert_topic)
        )
        self.downtime_alarm.add_ok_action(
            cloudwatch.SnsAction(self.alert_topic)
        )

        # Create alarm for website recovery notification
        self.recovery_alarm = cloudwatch.Alarm(
            self,
            "WebsiteRecoveryAlarm",
            alarm_name=f"Website-Recovered-{self.domain_name}",
            alarm_description=f"Notify when website {self.website_url} recovers",
            metric=cloudwatch.Metric(
                namespace="AWS/Route53",
                metric_name="HealthCheckStatus",
                dimensions_map={
                    "HealthCheckId": self.health_check.ref
                },
                statistic="Minimum",
                period=cdk.Duration.minutes(1)
            ),
            threshold=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
            evaluation_periods=2,  # Require 2 consecutive successes for stability
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

        # Add SNS notification for recovery alerts
        self.recovery_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.alert_topic)
        )

        # Add tags to alarms for organization
        Tags.of(self.downtime_alarm).add("Purpose", "UptimeMonitoring")
        Tags.of(self.downtime_alarm).add("AlarmType", "Downtime")
        Tags.of(self.recovery_alarm).add("Purpose", "UptimeMonitoring")
        Tags.of(self.recovery_alarm).add("AlarmType", "Recovery")

    def _create_outputs(self) -> None:
        """
        Create CloudFormation outputs for key resource information
        
        Provides essential information about created resources for
        verification, integration, and operational purposes.
        """
        # Output SNS topic ARN for reference
        CfnOutput(
            self,
            "SNSTopicArn",
            value=self.alert_topic.topic_arn,
            description="ARN of the SNS topic for uptime alerts",
            export_name=f"{self.stack_name}-SNSTopicArn"
        )

        # Output health check ID for reference
        CfnOutput(
            self,
            "HealthCheckId",
            value=self.health_check.ref,
            description="Route53 health check ID for website monitoring",
            export_name=f"{self.stack_name}-HealthCheckId"
        )

        # Output website URL being monitored
        CfnOutput(
            self,
            "MonitoredWebsite",
            value=self.website_url,
            description="Website URL being monitored for uptime",
            export_name=f"{self.stack_name}-MonitoredWebsite"
        )

        # Output admin email for confirmation
        CfnOutput(
            self,
            "AdminEmail",
            value=self.admin_email,
            description="Email address receiving uptime alerts",
            export_name=f"{self.stack_name}-AdminEmail"
        )

        # Output downtime alarm name
        CfnOutput(
            self,
            "DowntimeAlarmName",
            value=self.downtime_alarm.alarm_name,
            description="CloudWatch alarm name for website downtime detection",
            export_name=f"{self.stack_name}-DowntimeAlarmName"
        )

        # Output recovery alarm name
        CfnOutput(
            self,
            "RecoveryAlarmName",
            value=self.recovery_alarm.alarm_name,
            description="CloudWatch alarm name for website recovery notification",
            export_name=f"{self.stack_name}-RecoveryAlarmName"
        )

    def _apply_tags(self) -> None:
        """
        Apply consistent tags across all resources
        
        Implements tagging strategy for cost allocation, resource
        organization, and operational management following AWS
        tagging best practices.
        """
        # Apply stack-level tags that propagate to all resources
        Tags.of(self).add("Project", "UptimeMonitoring")
        Tags.of(self).add("Environment", "Production")
        Tags.of(self).add("Owner", "Infrastructure")
        Tags.of(self).add("CostCenter", "Operations")
        Tags.of(self).add("Application", "WebsiteMonitoring")
        Tags.of(self).add("CDKVersion", cdk.App().version)


def main() -> None:
    """
    Main application entry point
    
    Creates and configures the CDK application with proper environment
    settings and applies security best practices using CDK Nag.
    """
    # Create CDK application
    app = App()

    # Get configuration from environment variables or context
    website_url = app.node.try_get_context("website_url") or os.environ.get(
        "WEBSITE_URL", "https://example.com"
    )
    admin_email = app.node.try_get_context("admin_email") or os.environ.get(
        "ADMIN_EMAIL", "admin@example.com"
    )
    
    # Get AWS environment configuration
    account = os.environ.get("CDK_DEFAULT_ACCOUNT")
    region = os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
    
    # Create environment configuration
    env = Environment(account=account, region=region) if account else None

    # Create the uptime monitoring stack
    stack = UptimeMonitoringStack(
        app,
        "UptimeMonitoringStack",
        website_url=website_url,
        admin_email=admin_email,
        env=env,
        description="Simple Website Uptime Monitoring with Route53 and SNS",
        stack_name="uptime-monitoring-stack"
    )

    # Apply CDK Nag for security best practices
    # Note: Route53 health checks and SNS topics have minimal security concerns
    # but we still apply CDK Nag for comprehensive validation
    AwsSolutionsChecks(app, verbose=True)

    # Suppress specific CDK Nag rules that don't apply to this monitoring solution
    NagSuppressions.add_stack_suppressions(
        stack,
        [
            {
                "id": "AwsSolutions-SNS3", 
                "reason": "SSL enforcement not required for uptime monitoring alerts - content is operational status only and not sensitive data. SNS topic is used for internal monitoring notifications."
            }
        ]
    )

    # Synthesize the CloudFormation template
    app.synth()


if __name__ == "__main__":
    main()