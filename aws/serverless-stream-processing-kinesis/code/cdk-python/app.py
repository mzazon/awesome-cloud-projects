#!/usr/bin/env python3
"""
CDK Python application for Real-time Data Processing with Amazon Kinesis and Lambda

This application deploys a serverless real-time data processing pipeline that includes:
- Amazon Kinesis Data Stream with multiple shards
- AWS Lambda function for processing streaming data
- S3 bucket for storing processed data
- IAM roles and policies with least privilege access
- CloudWatch monitoring and logging
"""

import os
from aws_cdk import (
    App,
    Environment,
    Tags,
)
from real_time_data_processing_stack import RealTimeDataProcessingStack


def main() -> None:
    """Main application entry point."""
    app = App()

    # Get account and region from CDK environment or context
    account = app.node.try_get_context("account") or os.environ.get("CDK_DEFAULT_ACCOUNT")
    region = app.node.try_get_context("region") or os.environ.get("CDK_DEFAULT_REGION")

    # Set environment for stack deployment
    env = Environment(account=account, region=region) if account and region else None

    # Create the main stack
    stack = RealTimeDataProcessingStack(
        app,
        "RealTimeDataProcessingStack",
        env=env,
        description="Real-time data processing pipeline with Kinesis and Lambda"
    )

    # Add common tags to all resources
    Tags.of(app).add("Project", "RealTimeDataProcessing")
    Tags.of(app).add("Environment", app.node.try_get_context("environment") or "development")
    Tags.of(app).add("Owner", "aws-recipes")
    Tags.of(app).add("CostCenter", "engineering")

    app.synth()


if __name__ == "__main__":
    main()