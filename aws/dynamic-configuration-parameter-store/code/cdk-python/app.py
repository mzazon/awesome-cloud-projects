#!/usr/bin/env python3
"""
Dynamic Configuration with Parameter Store
AWS CDK Python Implementation

This CDK application implements a serverless configuration management system using:
- AWS Systems Manager Parameter Store for centralized configuration storage
- Lambda functions with AWS Parameters and Secrets Extension for cached retrieval
- EventBridge for automatic configuration invalidation
- CloudWatch for monitoring and alerting
"""

import os
from aws_cdk import (
    App,
    Environment,
    Tags,
)
from dynamic_config_management.dynamic_config_management_stack import DynamicConfigManagementStack


def main() -> None:
    """Main CDK application entry point."""
    app = App()
    
    # Get environment variables
    account = os.getenv('CDK_DEFAULT_ACCOUNT') or app.node.try_get_context("account")
    region = os.getenv('CDK_DEFAULT_REGION') or app.node.try_get_context("region")
    
    # Default environment
    env = Environment(
        account=account,
        region=region
    )
    
    # Create the main stack
    stack = DynamicConfigManagementStack(
        app, 
        "DynamicConfigManagementStack",
        env=env,
        description="Dynamic Configuration with Parameter Store"
    )
    
    # Add common tags
    Tags.of(stack).add("Project", "DynamicConfigManagement")
    Tags.of(stack).add("Component", "ConfigurationManagement")
    Tags.of(stack).add("CostCenter", "Engineering")
    Tags.of(stack).add("Environment", app.node.try_get_context("environment") or "development")
    
    app.synth()


if __name__ == "__main__":
    main()