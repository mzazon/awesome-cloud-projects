#!/usr/bin/env python3
"""
CDK Python application for Chat Notifications with SNS and Chatbot.

This application creates:
- SNS Topic with KMS encryption for team notifications
- CloudWatch Alarm for demonstration and testing purposes
- IAM roles and policies for secure Chatbot integration
- Outputs for manual Chatbot configuration

Note: AWS Chatbot workspace and channel configuration must be set up manually
through the AWS Console as it requires OAuth authentication with Slack/Teams.
"""

import os
from typing import Dict, Any, Optional

import aws_cdk as cdk
from aws_cdk import (
    Duration,
    Stack,
    aws_sns as sns,
    aws_cloudwatch as cloudwatch,
    aws_iam as iam,
    aws_kms as kms,
    CfnOutput,
    Tags,
    RemovalPolicy,
)
from constructs import Construct


class ChatNotificationsStack(Stack):
    """
    CDK Stack for Chat Notifications with SNS and Chatbot.
    
    This stack creates the infrastructure needed for sending AWS notifications
    to chat platforms like Slack and Microsoft Teams using AWS SNS and Chatbot.
    """

    def __init__(
        self, 
        scope: Construct, 
        construct_id: str, 
        *,
        random_suffix: str = "demo",
        environment: str = "development",
        **kwargs: Any
    ) -> None:
        """
        Initialize the Chat Notifications Stack.
        
        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            random_suffix: Unique suffix for resource naming
            environment: Environment name (development, staging, production)
            **kwargs: Additional keyword arguments
        """
        super().__init__(scope, construct_id, **kwargs)

        # Store configuration parameters
        self.random_suffix = random_suffix
        self.environment = environment
        
        # Create the core resources
        self._create_sns_topic()
        self._create_cloudwatch_alarm()
        self._create_chatbot_iam_role()
        self._create_outputs()

    def _create_sns_topic(self) -> None:
        """Create encrypted SNS topic for team notifications."""
        self.notification_topic = sns.Topic(
            self, "TeamNotificationsTopic",
            topic_name=f"team-notifications-{self.random_suffix}",
            display_name="Team Notifications Topic",
            # Use AWS managed KMS key for SNS encryption
            master_key=kms.Alias.from_alias_name(
                self, "SnsKmsKey", 
                "alias/aws/sns"
            ),
            fifo=False,
        )

        # Add comprehensive tags
        Tags.of(self.notification_topic).add("Purpose", "ChatNotifications")
        Tags.of(self.notification_topic).add("Environment", self.environment)
        Tags.of(self.notification_topic).add("ManagedBy", "CDK")
        Tags.of(self.notification_topic).add("Service", "SNS")
        Tags.of(self.notification_topic).add("Component", "Messaging")

        # Apply removal policy based on environment
        if self.environment == "production":
            self.notification_topic.apply_removal_policy(RemovalPolicy.RETAIN)
        else:
            self.notification_topic.apply_removal_policy(RemovalPolicy.DESTROY)

    def _create_cloudwatch_alarm(self) -> None:
        """Create CloudWatch alarm for testing the notification pipeline."""
        # Create CloudWatch Alarm for testing notifications
        # This alarm triggers when CPU utilization is less than 1% (for easy testing)
        self.demo_alarm = cloudwatch.Alarm(
            self, "DemoCpuAlarm",
            alarm_name=f"demo-cpu-alarm-{self.random_suffix}",
            alarm_description="Demo CPU alarm for testing chat notifications - triggers on low CPU usage for easy testing",
            metric=cloudwatch.Metric(
                namespace="AWS/EC2",
                metric_name="CPUUtilization",
                statistic="Average",
                period=Duration.minutes(5),
                # Add dimensions if needed for specific instances
                dimensions_map={} if self.environment == "demo" else {}
            ),
            threshold=1.0,
            comparison_operator=cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
            evaluation_periods=1,
            datapoints_to_alarm=1,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

        # Add SNS topic as alarm action
        self.demo_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.notification_topic)
        )

        # Also add OK action to test state transitions
        self.demo_alarm.add_ok_action(
            cloudwatch.SnsAction(self.notification_topic)
        )

        # Add tags to the alarm
        Tags.of(self.demo_alarm).add("Purpose", "Testing")
        Tags.of(self.demo_alarm).add("Environment", self.environment)
        Tags.of(self.demo_alarm).add("ManagedBy", "CDK")

    def _create_chatbot_iam_role(self) -> None:
        """Create IAM role for AWS Chatbot with appropriate permissions."""
        # Create IAM role for AWS Chatbot
        # This role will be used by Chatbot to access AWS resources from chat
        self.chatbot_role = iam.Role(
            self, "ChatbotRole",
            role_name=f"chatbot-role-{self.random_suffix}",
            assumed_by=iam.ServicePrincipal("chatbot.amazonaws.com"),
            description="IAM role for AWS Chatbot to access AWS resources securely",
            managed_policies=[
                # Read-only access for general AWS resource information
                iam.ManagedPolicy.from_aws_managed_policy_name("ReadOnlyAccess"),
                # Enhanced CloudWatch permissions for monitoring
                iam.ManagedPolicy.from_aws_managed_policy_name("CloudWatchReadOnlyAccess"),
            ],
            max_session_duration=Duration.hours(12),
        )

        # Add inline policy for specific Chatbot operations
        self.chatbot_role.add_to_policy(
            iam.PolicyStatement(
                sid="ChatbotServicePermissions",
                effect=iam.Effect.ALLOW,
                actions=[
                    "chatbot:DescribeSlackChannelConfigurations",
                    "chatbot:DescribeChimeWebhookConfigurations", 
                    "chatbot:DescribeSlackWorkspaces",
                    "chatbot:DescribeSlackUserIdentities",
                    "chatbot:ListMicrosoftTeamsChannelConfigurations",
                    "chatbot:DescribeMicrosoftTeamsChannelConfigurations",
                ],
                resources=["*"],
            )
        )

        # Add policy for SNS topic access
        self.chatbot_role.add_to_policy(
            iam.PolicyStatement(
                sid="SnsTopicAccess",
                effect=iam.Effect.ALLOW,
                actions=[
                    "sns:ListTopics",
                    "sns:GetTopicAttributes",
                    "sns:ListSubscriptionsByTopic",
                ],
                resources=[
                    self.notification_topic.topic_arn,
                    f"arn:aws:sns:*:{self.account}:*"
                ],
            )
        )

        # Add CloudWatch Logs permissions for troubleshooting
        self.chatbot_role.add_to_policy(
            iam.PolicyStatement(
                sid="CloudWatchLogsAccess",
                effect=iam.Effect.ALLOW,
                actions=[
                    "logs:DescribeLogGroups",
                    "logs:DescribeLogStreams",
                    "logs:GetLogEvents",
                    "logs:FilterLogEvents",
                ],
                resources=[
                    f"arn:aws:logs:*:{self.account}:log-group:/aws/chatbot/*"
                ],
            )
        )

        # Add tags to the IAM role
        Tags.of(self.chatbot_role).add("Purpose", "ChatbotIntegration")
        Tags.of(self.chatbot_role).add("Environment", self.environment)
        Tags.of(self.chatbot_role).add("ManagedBy", "CDK")
        Tags.of(self.chatbot_role).add("Service", "Chatbot")

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for reference and manual configuration."""
        # Primary SNS topic information
        CfnOutput(
            self, "SnsTopicArn",
            value=self.notification_topic.topic_arn,
            description="ARN of the SNS topic for team notifications",
            export_name=f"TeamNotificationsTopic-{self.random_suffix}",
        )

        CfnOutput(
            self, "SnsTopicName",
            value=self.notification_topic.topic_name,
            description="Name of the SNS topic for team notifications",
        )

        # CloudWatch alarm information
        CfnOutput(
            self, "CloudWatchAlarmName",
            value=self.demo_alarm.alarm_name,
            description="Name of the demo CloudWatch alarm for testing notifications",
        )

        CfnOutput(
            self, "CloudWatchAlarmArn",
            value=self.demo_alarm.alarm_arn,
            description="ARN of the demo CloudWatch alarm",
        )

        # IAM role information for Chatbot
        CfnOutput(
            self, "ChatbotRoleArn",
            value=self.chatbot_role.role_arn,
            description="ARN of the IAM role for AWS Chatbot",
        )

        CfnOutput(
            self, "ChatbotRoleName",
            value=self.chatbot_role.role_name,
            description="Name of the IAM role for AWS Chatbot",
        )

        # Console URLs for manual setup
        CfnOutput(
            self, "ChatbotConsoleUrl",
            value="https://console.aws.amazon.com/chatbot/",
            description="URL to AWS Chatbot console for manual workspace and channel configuration",
        )

        CfnOutput(
            self, "CloudWatchConsoleUrl",
            value=f"https://console.aws.amazon.com/cloudwatch/home?region={self.region}#alarmsV2:alarm/{self.demo_alarm.alarm_name}",
            description="URL to view the demo CloudWatch alarm in the console",
        )

        # Configuration summary
        CfnOutput(
            self, "ManualSetupInstructions",
            value=f"Complete setup: 1) Open Chatbot console, 2) Add Slack/Teams workspace, 3) Create channel config with role {self.chatbot_role.role_name}, 4) Subscribe to SNS topic {self.notification_topic.topic_name}",
            description="Step-by-step instructions for completing the chat notification setup",
        )

        # Testing instructions
        CfnOutput(
            self, "TestingInstructions", 
            value=f"Test notifications: aws sns publish --topic-arn {self.notification_topic.topic_arn} --subject 'Test Alert' --message 'Testing chat notifications'",
            description="CLI command to test the notification system",
        )


def main() -> None:
    """Main function to create and synthesize the CDK app."""
    # Initialize CDK App
    app = cdk.App()

    # Get context values or use defaults
    random_suffix = app.node.try_get_context("random_suffix") or "demo"
    environment = app.node.try_get_context("environment") or "development"
    
    # Validate environment
    valid_environments = ["development", "staging", "production", "demo"]
    if environment not in valid_environments:
        raise ValueError(f"Invalid environment '{environment}'. Must be one of: {valid_environments}")

    # Create the stack with enhanced configuration
    stack = ChatNotificationsStack(
        app,
        f"ChatNotificationsStack-{random_suffix}",
        random_suffix=random_suffix,
        environment=environment,
        description=f"Chat Notifications with SNS and Chatbot - {environment} environment (CDK Python)",
        env=cdk.Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
        ),
        tags={
            "Project": "ChatNotifications",
            "Environment": environment,
            "ManagedBy": "CDK",
            "Language": "Python",
            "Purpose": "TeamCommunication",
            "Recipe": "chat-notifications-sns-chatbot",
            "CostCenter": "DevOps",
        }
    )

    # Add stack-level tags
    Tags.of(stack).add("StackName", stack.stack_name)
    Tags.of(stack).add("CreatedBy", "CDK-Python")
    
    # Synthesize the app
    app.synth()


if __name__ == "__main__":
    main()