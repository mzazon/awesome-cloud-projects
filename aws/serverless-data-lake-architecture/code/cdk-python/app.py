#!/usr/bin/env python3
"""
Advanced Serverless Data Lake Architecture CDK Application

This CDK application implements an enterprise-grade serverless data lake architecture
with Lambda layers, AWS Glue, and EventBridge integration for scalable data processing.

Architecture Components:
- Lambda Layer for shared utilities and dependencies
- S3 buckets for raw, processed, and quarantine data
- Lambda functions for data ingestion, validation, and quality monitoring
- Custom EventBridge bus for event-driven orchestration
- AWS Glue for ETL processing and data cataloging
- DynamoDB for metadata storage
- CloudWatch for monitoring and observability
"""

import os
from aws_cdk import (
    App,
    Environment,
    Tags
)
from serverless_datalake_stack import ServerlessDataLakeStack


def main() -> None:
    """Main CDK application entry point."""
    app = App()
    
    # Get environment configuration
    account = app.node.try_get_context("account") or os.environ.get("CDK_DEFAULT_ACCOUNT")
    region = app.node.try_get_context("region") or os.environ.get("CDK_DEFAULT_REGION")
    
    # Application configuration
    project_name = app.node.try_get_context("project_name") or "advanced-serverless-datalake"
    environment_name = app.node.try_get_context("environment") or "dev"
    
    # Create the main stack
    stack = ServerlessDataLakeStack(
        app,
        f"{project_name}-{environment_name}",
        project_name=project_name,
        environment_name=environment_name,
        env=Environment(account=account, region=region),
        description="Advanced Serverless Data Lake Architecture with Lambda Layers, Glue, and EventBridge"
    )
    
    # Add common tags
    Tags.of(stack).add("Project", project_name)
    Tags.of(stack).add("Environment", environment_name)
    Tags.of(stack).add("Architecture", "ServerlessDataLake")
    Tags.of(stack).add("ManagedBy", "CDK")
    
    app.synth()


if __name__ == "__main__":
    main()