#!/usr/bin/env python3
"""
AWS CDK Python application for Security Hub Incident Response
This application deploys a comprehensive security incident response system using AWS Security Hub.
"""

import os
from aws_cdk import (
    App,
    Environment,
    Tags
)
from security_incident_response_stack import SecurityIncidentResponseStack


def main() -> None:
    """Main application entry point"""
    app = App()
    
    # Get environment from context or use defaults
    account = app.node.try_get_context("account") or os.environ.get("CDK_DEFAULT_ACCOUNT")
    region = app.node.try_get_context("region") or os.environ.get("CDK_DEFAULT_REGION")
    
    if not account or not region:
        raise ValueError("Account and region must be specified via context or environment variables")
    
    env = Environment(account=account, region=region)
    
    # Create the main stack
    stack = SecurityIncidentResponseStack(
        app,
        "SecurityIncidentResponseStack",
        env=env,
        description="Automated Security Incident Response system with AWS Security Hub, EventBridge, and Lambda"
    )
    
    # Add tags to all resources in the stack
    Tags.of(stack).add("Project", "SecurityIncidentResponse")
    Tags.of(stack).add("Environment", "Production")
    Tags.of(stack).add("ManagedBy", "CDK")
    Tags.of(stack).add("CostCenter", "Security")
    
    app.synth()


if __name__ == "__main__":
    main()