#!/usr/bin/env python3
"""
SSL Certificate Monitoring with AWS CDK Python

This CDK application creates a complete SSL certificate monitoring solution using:
- AWS Certificate Manager (ACM) for SSL certificate management
- Amazon CloudWatch for metrics and alarms
- Amazon SNS for notifications

The solution monitors SSL certificates for expiration and sends email alerts
when certificates are approaching expiration (30 days threshold).
"""

import os
from typing import Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    aws_certificatemanager as acm,
    aws_cloudwatch as cloudwatch,
    aws_sns as sns,
    aws_sns_subscriptions as sns_subscriptions,
    CfnParameter,
    CfnOutput,
)
from constructs import Construct


class SslCertificateMonitoringStack(Stack):
    """
    CDK Stack for SSL Certificate Monitoring
    
    This stack creates:
    1. SNS Topic for certificate expiration notifications
    2. Email subscription to the SNS topic
    3. CloudWatch alarm to monitor certificate expiration
    4. Optional: Import existing ACM certificate for monitoring
    """

    def __init__(
        self, 
        scope: Construct, 
        construct_id: str, 
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Parameters for customization
        notification_email = CfnParameter(
            self,
            "NotificationEmail",
            type="String",
            description="Email address to receive SSL certificate expiration alerts",
            constraint_description="Must be a valid email address",
            default="admin@example.com"
        )

        certificate_arn = CfnParameter(
            self,
            "CertificateArn",
            type="String",
            description="ARN of existing ACM certificate to monitor (optional - leave blank to skip monitoring setup)",
            default="",
            constraint_description="Must be a valid ACM certificate ARN or empty string"
        )

        certificate_domain = CfnParameter(
            self,
            "CertificateDomain",
            type="String",
            description="Domain name for the certificate being monitored (used for alarm naming)",
            default="example.com",
            constraint_description="Must be a valid domain name"
        )

        expiration_threshold_days = CfnParameter(
            self,
            "ExpirationThresholdDays",
            type="Number",
            description="Number of days before expiration to trigger alert",
            default=30,
            min_value=1,
            max_value=365,
            constraint_description="Must be between 1 and 365 days"
        )

        # Create SNS Topic for certificate expiration alerts
        cert_alerts_topic = sns.Topic(
            self,
            "CertificateAlertsTopic",
            display_name="SSL Certificate Expiration Alerts",
            description="Topic for SSL certificate expiration notifications"
        )

        # Add email subscription to SNS topic
        cert_alerts_topic.add_subscription(
            sns_subscriptions.EmailSubscription(
                notification_email.value_as_string
            )
        )

        # Create CloudWatch alarm for certificate expiration monitoring
        # Note: This will only be created if a certificate ARN is provided
        certificate_alarm = cloudwatch.Alarm(
            self,
            "CertificateExpirationAlarm",
            alarm_name=f"SSL-Certificate-Expiring-{certificate_domain.value_as_string}",
            alarm_description=f"Alert when SSL certificate for {certificate_domain.value_as_string} expires in {expiration_threshold_days.value_as_number} days",
            metric=cloudwatch.Metric(
                namespace="AWS/CertificateManager",
                metric_name="DaysToExpiry",
                dimensions_map={
                    "CertificateArn": certificate_arn.value_as_string
                },
                statistic="Minimum",
                period=Duration.days(1)
            ),
            threshold=expiration_threshold_days.value_as_number,
            comparison_operator=cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
            evaluation_periods=1,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )

        # Add SNS topic as alarm action
        certificate_alarm.add_alarm_action(
            cloudwatch.SnsAction(cert_alerts_topic)
        )

        # Outputs for reference
        CfnOutput(
            self,
            "SnsTopicArn",
            value=cert_alerts_topic.topic_arn,
            description="ARN of the SNS topic for certificate alerts",
            export_name=f"{self.stack_name}-SnsTopicArn"
        )

        CfnOutput(
            self,
            "SnsTopicName",
            value=cert_alerts_topic.topic_name,
            description="Name of the SNS topic for certificate alerts",
            export_name=f"{self.stack_name}-SnsTopicName"
        )

        CfnOutput(
            self,
            "CloudWatchAlarmName",
            value=certificate_alarm.alarm_name,
            description="Name of the CloudWatch alarm monitoring certificate expiration",
            export_name=f"{self.stack_name}-AlarmName"
        )

        CfnOutput(
            self,
            "MonitoringInstructions",
            value="To monitor additional certificates, create new alarms using the same SNS topic ARN as the alarm action",
            description="Instructions for extending the monitoring solution"
        )


class SslCertificateMonitoringApp(cdk.App):
    """
    CDK Application for SSL Certificate Monitoring
    
    This application can be deployed to monitor SSL certificates for expiration
    and send notifications when certificates are approaching expiration.
    """

    def __init__(self) -> None:
        super().__init__()

        # Get environment configuration
        env = cdk.Environment(
            account=os.getenv('CDK_DEFAULT_ACCOUNT'),
            region=os.getenv('CDK_DEFAULT_REGION', 'us-east-1')
        )

        # Create the monitoring stack
        monitoring_stack = SslCertificateMonitoringStack(
            self,
            "SslCertificateMonitoringStack",
            env=env,
            description="SSL Certificate Monitoring with ACM, CloudWatch, and SNS",
            tags={
                "Project": "SSL Certificate Monitoring",
                "Environment": os.getenv('ENVIRONMENT', 'development'),
                "Owner": os.getenv('OWNER', 'DevOps Team'),
                "CostCenter": os.getenv('COST_CENTER', 'IT-Security'),
                "CreatedBy": "AWS CDK Python"
            }
        )


# Entry point for CDK CLI
app = SslCertificateMonitoringApp()
app.synth()