#!/usr/bin/env python3
"""
AWS CDK Python application for Amazon Lex Chatbot Development Recipe

This CDK app deploys a complete customer service chatbot solution using:
- Amazon Lex V2 for conversational AI
- AWS Lambda for business logic fulfillment
- Amazon DynamoDB for order data storage
- Amazon S3 for product catalog storage
- IAM roles with least privilege access

Author: AWS CDK Generator
Version: 1.0
Recipe: Chatbot Development with Amazon Lex
"""

import os
from aws_cdk import App, Environment
from chatbot_stack import ChatbotStack

def main() -> None:
    """Main application entry point."""
    app = App()
    
    # Get environment from context or environment variables
    account = app.node.try_get_context("account") or os.environ.get("CDK_DEFAULT_ACCOUNT")
    region = app.node.try_get_context("region") or os.environ.get("CDK_DEFAULT_REGION")
    
    if not account or not region:
        raise ValueError("Account and region must be specified")
    
    env = Environment(account=account, region=region)
    
    # Deploy the chatbot stack
    ChatbotStack(
        app,
        "CustomerServiceChatbotStack",
        description="Complete Amazon Lex chatbot solution for customer service automation",
        env=env,
        stack_name=app.node.try_get_context("stack_name") or "customer-service-chatbot",
    )
    
    app.synth()

if __name__ == "__main__":
    main()