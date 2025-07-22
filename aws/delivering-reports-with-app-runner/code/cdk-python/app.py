#!/usr/bin/env python3
"""
CDK Python Application for Scheduled Email Reports with App Runner and SES

This application creates a serverless email reporting system using:
- AWS App Runner for containerized application hosting
- Amazon SES for reliable email delivery
- EventBridge Scheduler for automated scheduling
- CloudWatch for monitoring and logging
- IAM roles with least-privilege permissions

The architecture follows AWS best practices for security, scalability,
and operational excellence.
"""

import os
from typing import Optional

import aws_cdk as cdk
from aws_cdk import (
    Aspects,
    Environment,
    Tags
)
from cdk_nag import AwsSolutionsChecks, NagSuppressions

from scheduled_email_reports.scheduled_email_reports_stack import ScheduledEmailReportsStack


def get_environment() -> Optional[Environment]:
    """
    Get the CDK environment configuration from environment variables.
    
    Returns:
        Environment configuration with account and region, or None for environment-agnostic deployment
    """
    account = os.environ.get("CDK_DEFAULT_ACCOUNT")
    region = os.environ.get("CDK_DEFAULT_REGION")
    
    if account and region:
        return Environment(account=account, region=region)
    return None


def main() -> None:
    """
    Main function to initialize and deploy the CDK application.
    
    Creates the CDK app, instantiates the stack, applies security checks,
    and adds global tags for resource management.
    """
    # Initialize CDK application
    app = cdk.App()
    
    # Get environment configuration
    env = get_environment()
    
    # Create the main stack
    stack = ScheduledEmailReportsStack(
        app,
        "ScheduledEmailReportsStack",
        env=env,
        description="Serverless email reporting system using App Runner, SES, and EventBridge Scheduler"
    )
    
    # Apply AWS Solutions best practices checks
    Aspects.of(app).add(AwsSolutionsChecks(verbose=True))
    
    # Add global suppressions for CDK Nag rules that don't apply to this architecture
    NagSuppressions.add_stack_suppressions(
        stack,
        suppressions=[
            {
                "id": "AwsSolutions-IAM4",
                "reason": "AWS managed policies are used for service roles which is appropriate for this use case"
            },
            {
                "id": "AwsSolutions-IAM5", 
                "reason": "Wildcard permissions are necessary for SES and CloudWatch operations within the application scope"
            }
        ]
    )
    
    # Add tags for resource management and cost allocation
    Tags.of(stack).add("Project", "ScheduledEmailReports")
    Tags.of(stack).add("Environment", app.node.try_get_context("environment") or "dev")
    Tags.of(stack).add("Owner", "DevOps")
    Tags.of(stack).add("CostCenter", "Engineering")
    
    # Synthesize the application
    app.synth()


if __name__ == "__main__":
    main()