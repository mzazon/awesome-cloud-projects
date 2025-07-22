#!/usr/bin/env python3
"""
AWS CDK Application for Serverless Email Processing Systems

This CDK application deploys a complete serverless email processing system using:
- Amazon SES for receiving emails
- AWS Lambda for processing email content
- Amazon S3 for email storage
- Amazon SNS for notifications

Author: AWS CDK Team
Version: 1.0
"""

import os
from aws_cdk import (
    App,
    Environment,
    Tags
)
from email_processing_stack import EmailProcessingStack


def main() -> None:
    """Main application entry point."""
    app = App()
    
    # Get configuration from context or environment
    account = app.node.try_get_context("account") or os.environ.get("CDK_DEFAULT_ACCOUNT")
    region = app.node.try_get_context("region") or os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
    domain_name = app.node.try_get_context("domainName") or "example.com"
    notification_email = app.node.try_get_context("notificationEmail") or "admin@example.com"
    
    # Create the email processing stack
    email_stack = EmailProcessingStack(
        app,
        "EmailProcessingStack",
        domain_name=domain_name,
        notification_email=notification_email,
        env=Environment(account=account, region=region),
        description="Serverless Email Processing System with SES and Lambda"
    )
    
    # Add common tags
    Tags.of(email_stack).add("Project", "EmailProcessingSystem")
    Tags.of(email_stack).add("Environment", "Production")
    Tags.of(email_stack).add("CostCenter", "IT-Operations")
    Tags.of(email_stack).add("Owner", "DevOps-Team")
    
    app.synth()


if __name__ == "__main__":
    main()