#!/usr/bin/env python3
"""
AWS CDK Python application for Community Knowledge Base with re:Post Private and SNS.

This application creates the infrastructure for establishing a centralized enterprise 
knowledge base using AWS re:Post Private integrated with Amazon SNS email notifications 
to ensure team members stay informed about new questions, solutions, and discussions.
"""

import aws_cdk as cdk
from aws_cdk import (
    Duration,
    Stack,
    aws_sns as sns,
    aws_sns_subscriptions as subscriptions,
    CfnParameter,
    CfnOutput,
    Tags,
)
from constructs import Construct
from typing import List


class CommunityKnowledgeBaseStack(Stack):
    """
    CDK Stack for Community Knowledge Base with re:Post Private and SNS.
    
    This stack creates:
    - SNS Topic for knowledge base notifications
    - Email subscriptions for team members
    - Appropriate IAM policies and permissions
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Parameters for customization
        self.team_emails_param = CfnParameter(
            self,
            "TeamEmails",
            type="CommaDelimitedList",
            description="Comma-separated list of email addresses for team notifications",
            default="developer1@company.com,developer2@company.com,teamlead@company.com"
        )

        self.topic_name_param = CfnParameter(
            self,
            "TopicName",
            type="String",
            description="Name for the SNS topic for knowledge base notifications",
            default="repost-knowledge-notifications",
            min_length=1,
            max_length=256
        )

        # Create SNS Topic for knowledge base notifications
        self.knowledge_topic = sns.Topic(
            self,
            "KnowledgeBaseTopic",
            topic_name=self.topic_name_param.value_as_string,
            display_name="Enterprise Knowledge Base Notifications",
            description="SNS topic for AWS re:Post Private knowledge base notifications"
        )

        # Add email subscriptions for team members
        self._create_email_subscriptions()

        # Add resource tags for governance
        self._add_resource_tags()

        # Create outputs
        self._create_outputs()

    def _create_email_subscriptions(self) -> None:
        """
        Create email subscriptions for each team member.
        
        This method iterates through the provided email addresses and creates
        SNS email subscriptions for knowledge base notifications.
        """
        team_emails = self.team_emails_param.value_as_list
        
        for i, email in enumerate(team_emails):
            # Create email subscription for each team member
            self.knowledge_topic.add_subscription(
                subscriptions.EmailSubscription(
                    email_address=email
                )
            )

    def _add_resource_tags(self) -> None:
        """
        Add consistent tags to all resources for governance and cost tracking.
        """
        Tags.of(self).add("Project", "CommunityKnowledgeBase")
        Tags.of(self).add("Environment", "Production")
        Tags.of(self).add("Owner", "DevOps-Team")
        Tags.of(self).add("Purpose", "Knowledge-Management")
        Tags.of(self).add("CostCenter", "Engineering")

    def _create_outputs(self) -> None:
        """
        Create CloudFormation outputs for important resource information.
        """
        CfnOutput(
            self,
            "KnowledgeTopicArn",
            value=self.knowledge_topic.topic_arn,
            description="ARN of the SNS topic for knowledge base notifications",
            export_name=f"{self.stack_name}-KnowledgeTopicArn"
        )

        CfnOutput(
            self,
            "KnowledgeTopicName",
            value=self.knowledge_topic.topic_name,
            description="Name of the SNS topic for knowledge base notifications",
            export_name=f"{self.stack_name}-KnowledgeTopicName"
        )

        CfnOutput(
            self,
            "RePostPrivateUrl",
            value="https://console.aws.amazon.com/repost-private/",
            description="URL to access AWS re:Post Private console",
            export_name=f"{self.stack_name}-RePostPrivateUrl"
        )


class CommunityKnowledgeBaseApp(cdk.App):
    """
    CDK Application for Community Knowledge Base infrastructure.
    """

    def __init__(self):
        super().__init__()

        # Create the main stack
        knowledge_stack = CommunityKnowledgeBaseStack(
            self,
            "CommunityKnowledgeBaseStack",
            description="Infrastructure for Community Knowledge Base with re:Post Private and SNS notifications",
            env=cdk.Environment(
                account=self.node.try_get_context("account"),
                region=self.node.try_get_context("region")
            )
        )

        # Add stack-level tags
        Tags.of(knowledge_stack).add("Application", "CommunityKnowledgeBase")
        Tags.of(knowledge_stack).add("Version", "1.0")


def main():
    """
    Main entry point for the CDK application.
    """
    app = CommunityKnowledgeBaseApp()
    app.synth()


if __name__ == "__main__":
    main()