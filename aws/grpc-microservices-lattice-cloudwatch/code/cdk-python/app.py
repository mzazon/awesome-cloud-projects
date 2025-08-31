#!/usr/bin/env python3
"""
gRPC Microservices with VPC Lattice and CloudWatch CDK Application

This CDK application deploys a complete gRPC microservices architecture using
VPC Lattice's native HTTP/2 support and CloudWatch monitoring. The solution
includes three microservices (User, Order, Inventory) with intelligent routing,
health monitoring, and comprehensive observability.

Key Components:
- VPC Lattice Service Network for application-layer service mesh
- HTTP/2 listeners optimized for gRPC communication
- CloudWatch metrics, alarms, and dashboards
- EC2 instances with gRPC services and health endpoints
- Advanced routing rules for API versioning and method-based routing
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    Tags,
)
from constructs import Construct

from stacks.grpc_microservices_stack import GrpcMicroservicesStack


class GrpcMicroservicesApp(cdk.App):
    """
    CDK Application for gRPC Microservices with VPC Lattice and CloudWatch.
    
    This application creates a complete microservices architecture with:
    - VPC Lattice service network for intelligent routing
    - EC2 instances hosting gRPC services
    - CloudWatch monitoring and alerting
    - Advanced traffic management capabilities
    """

    def __init__(self, **kwargs: Any) -> None:
        super().__init__(**kwargs)

        # Get configuration from environment or use defaults
        config = self._get_configuration()
        
        # Create the main stack
        stack = GrpcMicroservicesStack(
            self,
            "GrpcMicroservicesStack",
            env=config["environment"],
            description="gRPC Microservices with VPC Lattice and CloudWatch monitoring",
            **config["stack_props"]
        )

        # Apply common tags to all resources
        self._apply_tags(stack, config["tags"])

    def _get_configuration(self) -> Dict[str, Any]:
        """
        Get application configuration from environment variables or defaults.
        
        Returns:
            Dict containing environment, stack properties, and tags
        """
        # Get AWS environment from CDK context or environment variables
        account = self.node.try_get_context("account") or os.environ.get("CDK_DEFAULT_ACCOUNT")
        region = self.node.try_get_context("region") or os.environ.get("CDK_DEFAULT_REGION", "us-east-1")

        # Get configuration from CDK context
        environment_name = self.node.try_get_context("environment") or "development"
        instance_type = self.node.try_get_context("instance_type") or "t3.micro"
        enable_detailed_monitoring = self.node.try_get_context("enable_detailed_monitoring") or True

        return {
            "environment": Environment(account=account, region=region),
            "stack_props": {
                "environment_name": environment_name,
                "instance_type": instance_type,
                "enable_detailed_monitoring": enable_detailed_monitoring,
            },
            "tags": {
                "Project": "gRPC-Microservices",
                "Environment": environment_name,
                "IaC": "CDK-Python",
                "Recipe": "grpc-microservices-lattice-cloudwatch",
            }
        }

    def _apply_tags(self, stack: Stack, tags: Dict[str, str]) -> None:
        """
        Apply common tags to all resources in the stack.
        
        Args:
            stack: The CDK stack to tag
            tags: Dictionary of tags to apply
        """
        for key, value in tags.items():
            Tags.of(stack).add(key, value)


def main() -> None:
    """Main entry point for the CDK application."""
    app = GrpcMicroservicesApp()
    app.synth()


if __name__ == "__main__":
    main()