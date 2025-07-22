#!/usr/bin/env python3
"""
AWS CDK Python application for Cross-Account Data Sharing with Data Exchange.

This CDK application creates the infrastructure for securely sharing data assets
across AWS accounts using AWS Data Exchange, S3, IAM, and Lambda functions.
"""

import os
from aws_cdk import (
    App,
    Environment,
    Tags,
)

from stacks.data_exchange_stack import DataExchangeStack


def main() -> None:
    """Main application entry point."""
    app = App()

    # Get environment configuration
    account = app.node.try_get_context("account") or os.environ.get("CDK_DEFAULT_ACCOUNT")
    region = app.node.try_get_context("region") or os.environ.get("CDK_DEFAULT_REGION")

    # Create the main stack
    stack = DataExchangeStack(
        app,
        "DataExchangeStack",
        env=Environment(account=account, region=region),
        description="Cross-account data sharing infrastructure using AWS Data Exchange",
    )

    # Add common tags to all resources
    Tags.of(stack).add("Project", "CrossAccountDataSharing")
    Tags.of(stack).add("Environment", "Production")
    Tags.of(stack).add("Owner", "DataEngineering")
    Tags.of(stack).add("CostCenter", "Analytics")

    app.synth()


if __name__ == "__main__":
    main()