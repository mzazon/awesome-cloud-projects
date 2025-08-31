#!/usr/bin/env python3
"""
AWS CDK Python application for Service Health Notifications.

This CDK application creates an automated notification system that monitors
AWS Personal Health Dashboard events and sends real-time alerts via SNS.
The solution includes EventBridge rules, SNS topics, and IAM roles for
comprehensive service health monitoring.
"""

import os
from typing import Optional

import aws_cdk as cdk
from aws_cdk import (
    Duration,
    Stack,
    StackProps,
    aws_events as events,
    aws_events_targets as targets,
    aws_iam as iam,
    aws_sns as sns,
    aws_sns_subscriptions as subscriptions,
)
from constructs import Construct


class ServiceHealthNotificationsStack(Stack):
    """
    CDK Stack for AWS Service Health Notifications.
    
    This stack creates:
    - SNS topic for health notifications
    - EventBridge rule to capture AWS Health events
    - IAM role for EventBridge to publish to SNS
    - Email subscription to the SNS topic
    - Proper permissions and policies
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        notification_email: str,
        **kwargs
    ) -> None:
        """
        Initialize the Service Health Notifications stack.

        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            notification_email: Email address for notifications
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)

        # Validate email parameter
        if not notification_email or "@" not in notification_email:
            raise ValueError("A valid email address must be provided for notifications")

        # Create SNS topic for health notifications
        self.health_topic = sns.Topic(
            self,
            "HealthNotificationsTopic",
            display_name="AWS Health Notifications",
            topic_name=f"aws-health-notifications-{construct_id.lower()}",
        )

        # Add email subscription to the SNS topic
        self.health_topic.add_subscription(
            subscriptions.EmailSubscription(notification_email)
        )

        # Create IAM role for EventBridge to publish to SNS
        self.eventbridge_role = iam.Role(
            self,
            "EventBridgeHealthRole",
            assumed_by=iam.ServicePrincipal("events.amazonaws.com"),
            description="Role for EventBridge to publish AWS Health events to SNS",
            inline_policies={
                "SNSPublishPolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=["sns:Publish"],
                            resources=[self.health_topic.topic_arn],
                        )
                    ]
                )
            },
        )

        # Create EventBridge rule for AWS Health events
        self.health_rule = events.Rule(
            self,
            "HealthEventsRule",
            description="Capture AWS Health events and send notifications",
            event_pattern=events.EventPattern(
                source=["aws.health"],
                detail_type=["AWS Health Event"],
            ),
            enabled=True,
        )

        # Add SNS topic as target for the EventBridge rule
        self.health_rule.add_target(
            targets.SnsTopic(
                self.health_topic,
                role=self.eventbridge_role,
                message=events.RuleTargetInput.from_object({
                    "event_id": events.EventField.from_path("$.detail.eventArn"),
                    "service": events.EventField.from_path("$.detail.service"),
                    "event_type": events.EventField.from_path("$.detail.eventTypeCode"),
                    "status": events.EventField.from_path("$.detail.statusCode"),
                    "region": events.EventField.from_path("$.detail.awsRegion"),
                    "start_time": events.EventField.from_path("$.detail.startTime"),
                    "description": events.EventField.from_path("$.detail.eventDescription[0].latestDescription"),
                    "affected_entities": events.EventField.from_path("$.detail.affectedEntities"),
                    "source": "AWS Personal Health Dashboard",
                    "alert_type": "Service Health Notification"
                }),
            )
        )

        # Grant EventBridge permission to publish to SNS topic
        self.health_topic.grant_publish(self.eventbridge_role)

        # Add resource tags for better organization
        cdk.Tags.of(self).add("Project", "ServiceHealthNotifications")
        cdk.Tags.of(self).add("Environment", "Production")
        cdk.Tags.of(self).add("ManagedBy", "CDK")

        # Outputs for verification and reference
        cdk.CfnOutput(
            self,
            "SNSTopicArn",
            value=self.health_topic.topic_arn,
            description="ARN of the SNS topic for health notifications",
            export_name=f"{construct_id}-SNSTopicArn"
        )

        cdk.CfnOutput(
            self,
            "EventBridgeRuleName",
            value=self.health_rule.rule_name,
            description="Name of the EventBridge rule for health events",
            export_name=f"{construct_id}-EventBridgeRuleName"
        )

        cdk.CfnOutput(
            self,
            "IAMRoleArn",
            value=self.eventbridge_role.role_arn,
            description="ARN of the IAM role used by EventBridge",
            export_name=f"{construct_id}-IAMRoleArn"
        )

        cdk.CfnOutput(
            self,
            "NotificationEmail",
            value=notification_email,
            description="Email address configured for notifications",
            export_name=f"{construct_id}-NotificationEmail"
        )


def main() -> None:
    """
    Main function to create and deploy the CDK application.
    
    Environment variables:
    - NOTIFICATION_EMAIL: Email address for notifications (required)
    - CDK_DEFAULT_ACCOUNT: AWS account ID (optional, defaults to current)
    - CDK_DEFAULT_REGION: AWS region (optional, defaults to current)
    """
    app = cdk.App()

    # Get notification email from context or environment variable
    notification_email = (
        app.node.try_get_context("notification_email") or
        os.environ.get("NOTIFICATION_EMAIL")
    )

    if not notification_email:
        raise ValueError(
            "Notification email must be provided via context variable "
            "'notification_email' or environment variable 'NOTIFICATION_EMAIL'"
        )

    # Get stack name from context or use default
    stack_name = (
        app.node.try_get_context("stack_name") or
        "ServiceHealthNotificationsStack"
    )

    # Create the stack with environment configuration
    env = cdk.Environment(
        account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
        region=os.environ.get("CDK_DEFAULT_REGION")
    )

    ServiceHealthNotificationsStack(
        app,
        stack_name,
        notification_email=notification_email,
        env=env,
        description="AWS CDK stack for automated service health notifications via SNS and EventBridge"
    )

    # Synthesize the CloudFormation template
    app.synth()


if __name__ == "__main__":
    main()