#!/usr/bin/env python3
"""
Secure Database Access with VPC Lattice Resource Gateway CDK Application

This CDK application creates a complete infrastructure stack for secure cross-account
database access using AWS VPC Lattice Resource Gateway. The solution includes:
- RDS MySQL database in private subnets with encryption
- VPC Lattice Service Network for secure communication
- Resource Gateway for database access abstraction
- Resource Configuration mapping database endpoints
- Security Groups with least privilege access
- IAM policies for cross-account authentication
- AWS RAM resource sharing configuration

Author: AWS Solutions Architecture Team
Version: 1.0
"""

import os
from typing import Optional

import aws_cdk as cdk
from aws_cdk import (
    App,
    Environment,
    Stack,
    StackProps,
    Tags,
)

from stacks.secure_database_access_stack import SecureDatabaseAccessStack


def main() -> None:
    """
    Main application entry point.
    
    Creates and deploys the Secure Database Access stack with VPC Lattice
    Resource Gateway configuration for cross-account database sharing.
    """
    app = App()
    
    # Get configuration from environment variables or CDK context
    account_id = app.node.try_get_context("account") or os.environ.get("CDK_DEFAULT_ACCOUNT")
    region = app.node.try_get_context("region") or os.environ.get("CDK_DEFAULT_REGION") or "us-east-1"
    
    if not account_id:
        raise ValueError("AWS Account ID must be provided via CDK_DEFAULT_ACCOUNT or context")
    
    # Consumer account ID for cross-account sharing
    consumer_account_id = app.node.try_get_context("consumer_account_id")
    if not consumer_account_id:
        consumer_account_id = "123456789012"  # Default placeholder - replace in production
        print(f"Warning: Using default consumer account ID: {consumer_account_id}")
        print("Set consumer_account_id in cdk.json or via context for production deployment")
    
    # Environment configuration
    env = Environment(
        account=account_id,
        region=region
    )
    
    # Stack configuration
    stack_props = StackProps(
        env=env,
        description="Secure Database Access with VPC Lattice Resource Gateway",
        tags={
            "Purpose": "VPCLatticeDemo",
            "Environment": app.node.try_get_context("environment") or "development",
            "Owner": "aws-solutions-architecture",
            "CostCenter": app.node.try_get_context("cost_center") or "engineering",
        }
    )
    
    # Create the main stack
    stack = SecureDatabaseAccessStack(
        app,
        "SecureDatabaseAccessStack",
        consumer_account_id=consumer_account_id,
        props=stack_props,
        **stack_props.__dict__
    )
    
    # Add common tags to all resources
    Tags.of(app).add("Project", "VPCLatticeResourceGateway")
    Tags.of(app).add("GeneratedBy", "CDKPython")
    
    # Synthesize the application
    app.synth()


if __name__ == "__main__":
    main()