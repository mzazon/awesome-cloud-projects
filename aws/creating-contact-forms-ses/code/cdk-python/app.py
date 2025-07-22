#!/usr/bin/env python3
"""
Contact Form CDK Application

This CDK application deploys a serverless contact form backend using:
- AWS Lambda for form processing
- Amazon SES for email delivery
- API Gateway for HTTP endpoints
- IAM roles with least privilege permissions
"""

import os
import aws_cdk as cdk
from contact_form.contact_form_stack import ContactFormStack


def main() -> None:
    """Initialize and deploy the Contact Form CDK application."""
    app = cdk.App()

    # Get configuration from CDK context or environment variables
    account = app.node.try_get_context("account") or os.environ.get("CDK_DEFAULT_ACCOUNT")
    region = app.node.try_get_context("region") or os.environ.get("CDK_DEFAULT_REGION") or "us-east-1"
    
    # Create the Contact Form stack
    ContactFormStack(
        app,
        "ContactFormStack",
        env=cdk.Environment(account=account, region=region),
        description="Serverless contact form backend with SES, Lambda, and API Gateway",
        tags={
            "Project": "ContactForm",
            "Environment": "Production",
            "ManagedBy": "CDK",
        },
    )

    # Synthesize the CDK app
    app.synth()


if __name__ == "__main__":
    main()