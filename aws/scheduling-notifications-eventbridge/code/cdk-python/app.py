#!/usr/bin/env python3
"""
AWS CDK App for Simple Business Notifications with EventBridge Scheduler and SNS

This CDK application creates a serverless notification system using EventBridge Scheduler
and SNS to automatically send business notifications on predefined schedules. The solution
demonstrates enterprise-grade scheduling capabilities with reliable message delivery.

Author: AWS CDK Generator v2.0
Recipe: Scheduling Notifications with EventBridge and SNS
"""

import os
from typing import Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    Tags,
    aws_sns as sns,
    aws_iam as iam,
    aws_scheduler as scheduler,
)
from constructs import Construct


class BusinessNotificationsStack(Stack):
    """
    CDK Stack for Business Notifications using EventBridge Scheduler and SNS.
    
    This stack creates:
    - SNS Topic for business notifications
    - IAM Role for EventBridge Scheduler execution
    - Schedule Group for organizing business schedules
    - Multiple schedules (daily, weekly, monthly) for different business needs
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        notification_email: Optional[str] = None,
        timezone: str = "America/New_York",
        environment: str = "production",
        **kwargs
    ) -> None:
        """
        Initialize the Business Notifications Stack.
        
        Args:
            scope: The construct scope
            construct_id: The construct identifier
            notification_email: Email address for notifications (optional - can be added later)
            timezone: Timezone for schedule expressions (default: America/New_York)
            environment: Environment name for tagging (default: production)
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)

        # Store parameters
        self.notification_email = notification_email
        self.timezone = timezone
        self.environment = environment

        # Create SNS topic for business notifications
        self.notification_topic = self._create_sns_topic()

        # Create email subscription if email provided
        if self.notification_email:
            self._create_email_subscription()

        # Create IAM role for EventBridge Scheduler
        self.scheduler_role = self._create_scheduler_execution_role()

        # Create schedule group for organization
        self.schedule_group = self._create_schedule_group()

        # Create business notification schedules
        self._create_daily_business_report_schedule()
        self._create_weekly_summary_schedule()
        self._create_monthly_reminder_schedule()

        # Add stack tags
        self._add_tags()

        # Create outputs
        self._create_outputs()

    def _create_sns_topic(self) -> sns.Topic:
        """
        Create SNS topic for business notifications with proper configuration.
        
        Returns:
            sns.Topic: The created SNS topic
        """
        topic = sns.Topic(
            self,
            "BusinessNotificationsTopic",
            topic_name=f"business-notifications-{cdk.Aws.STACK_NAME}",
            display_name="Business Notifications",
            fifo=False,  # Standard topic for business notifications
        )

        # Add topic policy for enhanced security (optional)
        topic_policy = sns.TopicPolicy(
            self,
            "BusinessNotificationsTopicPolicy",
            topics=[topic],
        )

        # Allow EventBridge Scheduler to publish to this topic
        topic_policy.document.add_statements(
            iam.PolicyStatement(
                sid="AllowEventBridgeSchedulerPublish",
                effect=iam.Effect.ALLOW,
                principals=[iam.ServicePrincipal("scheduler.amazonaws.com")],
                actions=["sns:Publish"],
                resources=[topic.topic_arn],
                conditions={
                    "StringEquals": {
                        "aws:SourceAccount": cdk.Aws.ACCOUNT_ID
                    }
                }
            )
        )

        return topic

    def _create_email_subscription(self) -> sns.Subscription:
        """
        Create email subscription to SNS topic.
        
        Returns:
            sns.Subscription: The created email subscription
        """
        return sns.Subscription(
            self,
            "EmailSubscription",
            topic=self.notification_topic,
            protocol=sns.SubscriptionProtocol.EMAIL,
            endpoint=self.notification_email,
        )

    def _create_scheduler_execution_role(self) -> iam.Role:
        """
        Create IAM role for EventBridge Scheduler with least privilege permissions.
        
        Returns:
            iam.Role: The created IAM role
        """
        role = iam.Role(
            self,
            "SchedulerExecutionRole",
            role_name=f"eventbridge-scheduler-role-{cdk.Aws.STACK_NAME}",
            assumed_by=iam.ServicePrincipal("scheduler.amazonaws.com"),
            description="Execution role for EventBridge Scheduler to publish to SNS",
        )

        # Add policy to allow publishing to SNS topic
        role.add_to_policy(
            iam.PolicyStatement(
                sid="AllowSNSPublish",
                effect=iam.Effect.ALLOW,
                actions=["sns:Publish"],
                resources=[self.notification_topic.topic_arn],
            )
        )

        return role

    def _create_schedule_group(self) -> scheduler.CfnScheduleGroup:
        """
        Create schedule group for organizing business notification schedules.
        
        Returns:
            scheduler.CfnScheduleGroup: The created schedule group
        """
        return scheduler.CfnScheduleGroup(
            self,
            "BusinessScheduleGroup",
            name=f"business-schedules-{cdk.Aws.STACK_NAME}",
            tags=[
                cdk.CfnTag(key="Purpose", value="BusinessNotifications"),
                cdk.CfnTag(key="Environment", value=self.environment),
            ],
        )

    def _create_daily_business_report_schedule(self) -> scheduler.CfnSchedule:
        """
        Create daily business report schedule (weekdays at 9 AM).
        
        Returns:
            scheduler.CfnSchedule: The created daily schedule
        """
        return scheduler.CfnSchedule(
            self,
            "DailyBusinessReportSchedule",
            name="daily-business-report",
            group_name=self.schedule_group.name,
            schedule_expression=f"cron(0 9 ? * MON-FRI *)",
            schedule_expression_timezone=self.timezone,
            description="Daily business report notification sent on weekdays at 9 AM",
            flexible_time_window=scheduler.CfnSchedule.FlexibleTimeWindowProperty(
                mode="FLEXIBLE",
                maximum_window_in_minutes=15,
            ),
            target=scheduler.CfnSchedule.TargetProperty(
                arn=self.notification_topic.topic_arn,
                role_arn=self.scheduler_role.role_arn,
                sns_parameters=scheduler.CfnSchedule.SnsParametersProperty(
                    subject="Daily Business Report - Ready for Review",
                    message_body=(
                        "Good morning! Your daily business report is ready for review. "
                        "Please check the dashboard for key metrics including sales performance, "
                        "customer engagement, and operational status. Have a great day!"
                    ),
                ),
            ),
        )

    def _create_weekly_summary_schedule(self) -> scheduler.CfnSchedule:
        """
        Create weekly summary schedule (Mondays at 8 AM).
        
        Returns:
            scheduler.CfnSchedule: The created weekly schedule
        """
        return scheduler.CfnSchedule(
            self,
            "WeeklySummarySchedule",
            name="weekly-summary",
            group_name=self.schedule_group.name,
            schedule_expression=f"cron(0 8 ? * MON *)",
            schedule_expression_timezone=self.timezone,
            description="Weekly business summary notification sent every Monday at 8 AM",
            flexible_time_window=scheduler.CfnSchedule.FlexibleTimeWindowProperty(
                mode="FLEXIBLE",
                maximum_window_in_minutes=30,
            ),
            target=scheduler.CfnSchedule.TargetProperty(
                arn=self.notification_topic.topic_arn,
                role_arn=self.scheduler_role.role_arn,
                sns_parameters=scheduler.CfnSchedule.SnsParametersProperty(
                    subject="Weekly Business Summary - New Week Ahead",
                    message_body=(
                        "Good Monday morning! Here is your weekly business summary with key achievements "
                        "from last week and priorities for the week ahead. Review the quarterly goals "
                        "progress and upcoming milestones. Let's make this week productive!"
                    ),
                ),
            ),
        )

    def _create_monthly_reminder_schedule(self) -> scheduler.CfnSchedule:
        """
        Create monthly reminder schedule (1st of each month at 10 AM).
        
        Returns:
            scheduler.CfnSchedule: The created monthly schedule
        """
        return scheduler.CfnSchedule(
            self,
            "MonthlyReminderSchedule",
            name="monthly-reminder",
            group_name=self.schedule_group.name,
            schedule_expression=f"cron(0 10 1 * ? *)",
            schedule_expression_timezone=self.timezone,
            description="Monthly business reminder notification sent on 1st of each month at 10 AM",
            flexible_time_window=scheduler.CfnSchedule.FlexibleTimeWindowProperty(
                mode="OFF",
            ),
            target=scheduler.CfnSchedule.TargetProperty(
                arn=self.notification_topic.topic_arn,
                role_arn=self.scheduler_role.role_arn,
                sns_parameters=scheduler.CfnSchedule.SnsParametersProperty(
                    subject="Monthly Business Reminder - Important Tasks",
                    message_body=(
                        "Welcome to a new month! This is your monthly reminder for important business tasks: "
                        "review financial reports, update quarterly projections, conduct team performance reviews, "
                        "and assess goal progress. Schedule time for strategic planning and process improvements."
                    ),
                ),
            ),
        )

    def _add_tags(self) -> None:
        """Add common tags to all stack resources."""
        Tags.of(self).add("Recipe", "SimpleBusinessNotifications")
        Tags.of(self).add("Environment", self.environment)
        Tags.of(self).add("Purpose", "BusinessNotifications")
        Tags.of(self).add("ManagedBy", "CDK")

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        cdk.CfnOutput(
            self,
            "SNSTopicArn",
            description="ARN of the SNS topic for business notifications",
            value=self.notification_topic.topic_arn,
            export_name=f"{cdk.Aws.STACK_NAME}-SNSTopicArn",
        )

        cdk.CfnOutput(
            self,
            "SNSTopicName",
            description="Name of the SNS topic for business notifications",
            value=self.notification_topic.topic_name,
            export_name=f"{cdk.Aws.STACK_NAME}-SNSTopicName",
        )

        cdk.CfnOutput(
            self,
            "SchedulerRoleArn",
            description="ARN of the IAM role used by EventBridge Scheduler",
            value=self.scheduler_role.role_arn,
            export_name=f"{cdk.Aws.STACK_NAME}-SchedulerRoleArn",
        )

        cdk.CfnOutput(
            self,
            "ScheduleGroupName",
            description="Name of the EventBridge Scheduler schedule group",
            value=self.schedule_group.name,
            export_name=f"{cdk.Aws.STACK_NAME}-ScheduleGroupName",
        )

        if self.notification_email:
            cdk.CfnOutput(
                self,
                "NotificationEmail",
                description="Email address configured for notifications",
                value=self.notification_email,
            )


class BusinessNotificationsApp(cdk.App):
    """
    CDK Application for Business Notifications.
    
    This application creates a complete serverless notification system using
    EventBridge Scheduler and SNS for automated business communications.
    """

    def __init__(self) -> None:
        """Initialize the CDK application."""
        super().__init__()

        # Get configuration from environment variables or context
        notification_email = self.node.try_get_context("notification_email")
        timezone = self.node.try_get_context("timezone") or "America/New_York"
        environment = self.node.try_get_context("environment") or "production"

        # Create the main stack
        BusinessNotificationsStack(
            self,
            "BusinessNotificationsStack",
            notification_email=notification_email,
            timezone=timezone,
            environment=environment,
            description="Simple Business Notifications with EventBridge Scheduler and SNS",
            tags={
                "Recipe": "SimpleBusinessNotifications",
                "CreatedBy": "CDK",
            },
        )


def main() -> None:
    """Main application entry point."""
    app = BusinessNotificationsApp()
    app.synth()


if __name__ == "__main__":
    main()