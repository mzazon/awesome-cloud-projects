#!/usr/bin/env python3
"""
Amazon Neptune Graph Database CDK Application

This CDK application deploys a complete Amazon Neptune cluster for building
recommendation engines with graph databases. The infrastructure includes:
- VPC with public and private subnets across multiple AZs
- Neptune cluster with primary and replica instances
- EC2 instance as Gremlin client
- S3 bucket for sample data storage
- Security groups and IAM roles with least privilege access

Usage:
    cdk deploy --all
"""

import aws_cdk as cdk
from aws_cdk import (
    App,
    Environment,
    Tags,
)
from stacks.networking_stack import NetworkingStack
from stacks.storage_stack import StorageStack
from stacks.neptune_stack import NeptuneStack
from stacks.compute_stack import ComputeStack
import os


def main() -> None:
    """Main application entry point."""
    app = App()
    
    # Get environment configuration
    env = Environment(
        account=os.environ.get('CDK_DEFAULT_ACCOUNT'),
        region=os.environ.get('CDK_DEFAULT_REGION', 'us-east-1')
    )
    
    # Create networking infrastructure first
    networking_stack = NetworkingStack(
        app, "NeptuneNetworkingStack",
        env=env,
        description="VPC and networking infrastructure for Neptune cluster"
    )
    
    # Create storage infrastructure
    storage_stack = StorageStack(
        app, "NeptuneStorageStack",
        env=env,
        description="S3 bucket for Neptune sample data storage"
    )
    
    # Create Neptune cluster (depends on networking)
    neptune_stack = NeptuneStack(
        app, "NeptuneClusterStack",
        vpc=networking_stack.vpc,
        neptune_security_group=networking_stack.neptune_security_group,
        subnet_group=networking_stack.subnet_group,
        env=env,
        description="Amazon Neptune cluster for graph database recommendations"
    )
    neptune_stack.add_dependency(networking_stack)
    
    # Create compute infrastructure (depends on networking and Neptune)
    compute_stack = ComputeStack(
        app, "NeptuneComputeStack",
        vpc=networking_stack.vpc,
        public_subnet=networking_stack.public_subnet,
        neptune_security_group=networking_stack.neptune_security_group,
        neptune_endpoint=neptune_stack.neptune_endpoint,
        s3_bucket=storage_stack.sample_data_bucket,
        env=env,
        description="EC2 instance for Gremlin client access to Neptune"
    )
    compute_stack.add_dependency(networking_stack)
    compute_stack.add_dependency(neptune_stack)
    compute_stack.add_dependency(storage_stack)
    
    # Add common tags to all stacks
    for stack in [networking_stack, storage_stack, neptune_stack, compute_stack]:
        Tags.of(stack).add("Application", "Neptune-Recommendations")
        Tags.of(stack).add("Environment", "Development")
        Tags.of(stack).add("ManagedBy", "CDK")
        Tags.of(stack).add("Recipe", "graph-databases-recommendation-engines-amazon-neptune")
    
    app.synth()


if __name__ == "__main__":
    main()