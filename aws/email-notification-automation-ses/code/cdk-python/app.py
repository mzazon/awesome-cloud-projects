#!/usr/bin/env python3
"""
CDK Python application for Automated Email Notification Systems
Implements event-driven email automation using SES, Lambda, and EventBridge
"""

import os
from typing import Any, Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    aws_events as events,
    aws_events_targets as targets,
    aws_iam as iam,
    aws_lambda as _lambda,
    aws_logs as logs,
    aws_ses as ses,
    aws_cloudwatch as cloudwatch,
    aws_s3 as s3,
    Duration,
    RemovalPolicy,
    Stack,
    StackProps,
)
from constructs import Construct


class EmailNotificationStack(Stack):
    """
    CDK Stack for automated email notification system using SES, Lambda, and EventBridge.
    
    This stack creates:
    - Lambda function for email processing
    - EventBridge custom bus and rules
    - SES email template
    - CloudWatch monitoring and alarms
    - IAM roles with least privilege permissions
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs: Any) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Stack parameters
        self.project_name = "email-automation"
        self.sender_email = self.node.try_get_context("sender_email") or "your-email@example.com"
        self.recipient_email = self.node.try_get_context("recipient_email") or "test-recipient@example.com"

        # Create S3 bucket for Lambda deployment packages
        self.deployment_bucket = self._create_deployment_bucket()

        # Create IAM role for Lambda function
        self.lambda_role = self._create_lambda_role()

        # Create Lambda function for email processing
        self.email_processor = self._create_email_processor()

        # Create SES email template
        self.email_template = self._create_email_template()

        # Create EventBridge custom bus and rules
        self.event_bus = self._create_event_bus()
        self.email_rule = self._create_email_rule()
        self.priority_rule = self._create_priority_rule()
        self.daily_report_rule = self._create_daily_report_rule()

        # Create CloudWatch monitoring
        self._create_monitoring()

        # Output important values
        self._create_outputs()

    def _create_deployment_bucket(self) -> s3.Bucket:
        """Create S3 bucket for Lambda deployment packages."""
        bucket = s3.Bucket(
            self,
            "DeploymentBucket",
            bucket_name=f"lambda-deployment-{self.project_name}-{self.account}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        cdk.Tags.of(bucket).add("Purpose", "Lambda deployment packages")
        return bucket

    def _create_lambda_role(self) -> iam.Role:
        """Create IAM role for Lambda function with appropriate permissions."""
        role = iam.Role(
            self,
            "EmailProcessorRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="IAM role for email notification Lambda function",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
        )

        # Add SES permissions
        ses_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "ses:SendEmail",
                "ses:SendRawEmail",
                "ses:SendTemplatedEmail",
            ],
            resources=["*"],
        )
        role.add_to_policy(ses_policy)

        # Add CloudWatch metrics permissions
        cloudwatch_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "cloudwatch:PutMetricData",
            ],
            resources=["*"],
        )
        role.add_to_policy(cloudwatch_policy)

        cdk.Tags.of(role).add("Purpose", "Lambda execution role for email processing")
        return role

    def _create_email_processor(self) -> _lambda.Function:
        """Create Lambda function for processing email notifications."""
        # Lambda function code
        lambda_code = '''
import json
import boto3
import logging
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
ses_client = boto3.client('ses')

def lambda_handler(event, context):
    try:
        logger.info(f"Processing event: {json.dumps(event)}")
        
        # Extract event details
        event_detail = event.get('detail', {})
        event_source = event.get('source', 'unknown')
        event_type = event.get('detail-type', 'Unknown Event')
        
        # Extract email configuration from event
        email_config = event_detail.get('emailConfig', {})
        recipient = email_config.get('recipient', 'default-recipient@example.com')
        subject = email_config.get('subject', f'Notification: {event_type}')
        message = event_detail.get('message', 'No message provided')
        title = event_detail.get('title', event_type)
        
        # For scheduled events, create appropriate content
        if 'aws.events' in event_source:
            title = "Daily Report"
            message = "This is your automated daily report from the email notification system."
            subject = "Daily System Report"
            recipient = "''' + self.recipient_email + '''"
        
        # Prepare template data
        template_data = {
            'subject': subject,
            'title': title,
            'message': message,
            'timestamp': datetime.now().isoformat(),
            'source': event_source
        }
        
        # Send templated email
        response = ses_client.send_templated_email(
            Source="''' + self.sender_email + '''",
            Destination={'ToAddresses': [recipient]},
            Template='NotificationTemplate',
            TemplateData=json.dumps(template_data)
        )
        
        logger.info(f"Email sent successfully: {response['MessageId']}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Email sent successfully',
                'messageId': response['MessageId'],
                'recipient': recipient
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing email: {str(e)}")
        # Re-raise to trigger EventBridge retry mechanism
        raise e
'''

        function = _lambda.Function(
            self,
            "EmailProcessor",
            function_name=f"{self.project_name}-email-processor",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline(lambda_code),
            role=self.lambda_role,
            timeout=Duration.seconds(30),
            memory_size=256,
            description="Email notification processor for event-driven system",
            environment={
                "PROJECT_NAME": self.project_name,
                "SENDER_EMAIL": self.sender_email,
            },
            log_retention=logs.RetentionDays.ONE_WEEK,
        )

        # Create custom metric filter for Lambda logs
        logs.MetricFilter(
            self,
            "EmailProcessingErrorsFilter",
            log_group=function.log_group,
            filter_pattern=logs.FilterPattern.literal("ERROR"),
            metric_name="EmailProcessingErrors",
            metric_namespace="CustomMetrics",
            metric_value="1",
        )

        cdk.Tags.of(function).add("Purpose", "Email notification processing")
        return function

    def _create_email_template(self) -> ses.CfnTemplate:
        """Create SES email template for notifications."""
        template = ses.CfnTemplate(
            self,
            "NotificationTemplate",
            template={
                "templateName": "NotificationTemplate",
                "subjectPart": "{{subject}}",
                "htmlPart": "<html><body><h2>{{title}}</h2><p>{{message}}</p><p>Timestamp: {{timestamp}}</p><p>Event Source: {{source}}</p></body></html>",
                "textPart": "{{title}}\n\n{{message}}\n\nTimestamp: {{timestamp}}\nEvent Source: {{source}}",
            },
        )

        cdk.Tags.of(template).add("Purpose", "Email notification template")
        return template

    def _create_event_bus(self) -> events.EventBus:
        """Create custom EventBridge event bus."""
        event_bus = events.EventBus(
            self,
            "EmailEventBus",
            event_bus_name=f"{self.project_name}-event-bus",
            description="Custom event bus for email notification system",
        )

        cdk.Tags.of(event_bus).add("Purpose", "Email notification event routing")
        return event_bus

    def _create_email_rule(self) -> events.Rule:
        """Create EventBridge rule for email notifications."""
        rule = events.Rule(
            self,
            "EmailRule",
            rule_name=f"{self.project_name}-email-rule",
            event_bus=self.event_bus,
            event_pattern=events.EventPattern(
                source=["custom.application"],
                detail_type=["Email Notification Request"],
            ),
            description="Route email notification requests to Lambda processor",
        )

        # Add Lambda function as target
        rule.add_target(targets.LambdaFunction(self.email_processor))

        cdk.Tags.of(rule).add("Purpose", "Email notification routing")
        return rule

    def _create_priority_rule(self) -> events.Rule:
        """Create EventBridge rule for priority notifications."""
        rule = events.Rule(
            self,
            "PriorityRule",
            rule_name=f"{self.project_name}-priority-rule",
            event_bus=self.event_bus,
            event_pattern=events.EventPattern(
                source=["custom.application"],
                detail_type=["Priority Alert"],
                detail={"priority": ["high", "critical"]},
            ),
            description="Handle high priority alerts",
        )

        # Add Lambda function as target
        rule.add_target(targets.LambdaFunction(self.email_processor))

        cdk.Tags.of(rule).add("Purpose", "Priority alert routing")
        return rule

    def _create_daily_report_rule(self) -> events.Rule:
        """Create EventBridge rule for daily reports."""
        rule = events.Rule(
            self,
            "DailyReportRule",
            rule_name=f"{self.project_name}-daily-report",
            schedule=events.Schedule.cron(
                hour="9", minute="0", day="*", month="*", year="*"
            ),
            description="Send daily email reports",
        )

        # Add Lambda function as target
        rule.add_target(targets.LambdaFunction(self.email_processor))

        cdk.Tags.of(rule).add("Purpose", "Daily report scheduling")
        return rule

    def _create_monitoring(self) -> None:
        """Create CloudWatch monitoring and alarms."""
        # Lambda error alarm
        lambda_error_alarm = cloudwatch.Alarm(
            self,
            "LambdaErrorAlarm",
            alarm_name=f"{self.project_name}-lambda-errors",
            alarm_description="Monitor Lambda function errors",
            metric=self.email_processor.metric_errors(
                period=Duration.minutes(5),
                statistic="Sum",
            ),
            threshold=1,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
        )

        # SES bounce alarm
        ses_bounce_alarm = cloudwatch.Alarm(
            self,
            "SESBounceAlarm",
            alarm_name=f"{self.project_name}-ses-bounces",
            alarm_description="Monitor SES bounce rate",
            metric=cloudwatch.Metric(
                namespace="AWS/SES",
                metric_name="Bounce",
                statistic="Sum",
                period=Duration.minutes(5),
            ),
            threshold=5,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
        )

        cdk.Tags.of(lambda_error_alarm).add("Purpose", "Lambda error monitoring")
        cdk.Tags.of(ses_bounce_alarm).add("Purpose", "SES bounce monitoring")

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs."""
        cdk.CfnOutput(
            self,
            "EventBusName",
            value=self.event_bus.event_bus_name,
            description="Name of the custom EventBridge event bus",
        )

        cdk.CfnOutput(
            self,
            "LambdaFunctionName",
            value=self.email_processor.function_name,
            description="Name of the email processing Lambda function",
        )

        cdk.CfnOutput(
            self,
            "LambdaFunctionArn",
            value=self.email_processor.function_arn,
            description="ARN of the email processing Lambda function",
        )

        cdk.CfnOutput(
            self,
            "SenderEmail",
            value=self.sender_email,
            description="Configured sender email address",
        )

        cdk.CfnOutput(
            self,
            "RecipientEmail",
            value=self.recipient_email,
            description="Configured recipient email address",
        )


class EmailNotificationApp(cdk.App):
    """CDK Application for Email Notification System."""

    def __init__(self) -> None:
        super().__init__()

        # Get environment configuration
        env = cdk.Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
        )

        # Create the stack
        EmailNotificationStack(
            self,
            "EmailNotificationStack",
            env=env,
            description="Automated Email Notification System using SES, Lambda, and EventBridge",
            tags={
                "Project": "AutomatedEmailNotifications",
                "Environment": "Development",
                "ManagedBy": "CDK",
            },
        )


# Create and synthesize the CDK app
app = EmailNotificationApp()
app.synth()