#!/usr/bin/env python3
"""
CDK Python application for CodeCommit Git Workflows with Branch Policies and Triggers

This application creates a comprehensive Git workflow automation system including:
- CodeCommit repository with branch protection
- Lambda functions for pull request and quality gate automation
- SNS topics for notifications
- EventBridge rules for event-driven automation
- CloudWatch dashboard for monitoring
- IAM roles and policies with least privilege access
"""

import os
from aws_cdk import (
    App,
    Environment,
    Tags,
)
from codecommit_git_workflows.codecommit_git_workflows_stack import CodeCommitGitWorkflowsStack


def main() -> None:
    """Main entry point for the CDK application."""
    app = App()
    
    # Get configuration from CDK context or environment variables
    account_id = app.node.try_get_context("account") or os.environ.get("CDK_DEFAULT_ACCOUNT")
    region = app.node.try_get_context("region") or os.environ.get("CDK_DEFAULT_REGION")
    
    # Validate required parameters
    if not account_id or not region:
        raise ValueError(
            "Account ID and region must be specified either through CDK context "
            "or environment variables (CDK_DEFAULT_ACCOUNT, CDK_DEFAULT_REGION)"
        )
    
    # Environment configuration
    env = Environment(account=account_id, region=region)
    
    # Get stack configuration from context with defaults
    stack_config = {
        "repository_name": app.node.try_get_context("repository_name") or "enterprise-app",
        "repository_description": app.node.try_get_context("repository_description") or 
                                 "Enterprise application with Git workflow automation",
        "notification_email": app.node.try_get_context("notification_email"),
        "team_lead_user": app.node.try_get_context("team_lead_user") or "team-lead",
        "senior_developers": app.node.try_get_context("senior_developers") or 
                           ["senior-dev-1", "senior-dev-2"],
        "environment_name": app.node.try_get_context("environment") or "development",
        "enable_monitoring": app.node.try_get_context("enable_monitoring") != "false",
        "enable_email_notifications": app.node.try_get_context("enable_email_notifications") == "true",
    }
    
    # Create the main stack
    codecommit_stack = CodeCommitGitWorkflowsStack(
        app,
        "CodeCommitGitWorkflowsStack",
        env=env,
        description="CodeCommit Git workflows with branch policies, triggers, and automation",
        **stack_config
    )
    
    # Add tags to all resources in the stack
    Tags.of(codecommit_stack).add("Project", "CodeCommitGitWorkflows")
    Tags.of(codecommit_stack).add("Environment", stack_config["environment_name"])
    Tags.of(codecommit_stack).add("ManagedBy", "CDK")
    Tags.of(codecommit_stack).add("Purpose", "GitWorkflowAutomation")
    
    # Synthesize the application
    app.synth()


if __name__ == "__main__":
    main()