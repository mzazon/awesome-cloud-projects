#!/usr/bin/env python3
"""
AWS CDK Python application for implementing distributed tracing 
with X-Ray and EventBridge across microservices architecture.

This application creates:
- Custom EventBridge bus for event routing
- Lambda functions for order, payment, inventory, and notification services
- API Gateway with X-Ray tracing enabled
- EventBridge rules and targets for event-driven communication
- IAM roles and policies with least privilege access
"""

import os
from aws_cdk import (
    App,
    Environment,
    Tags
)
from distributed_tracing_stack import DistributedTracingStack

# Get environment variables or use defaults
account = os.environ.get('CDK_DEFAULT_ACCOUNT')
region = os.environ.get('CDK_DEFAULT_REGION', 'us-east-1')

app = App()

# Create the main stack
stack = DistributedTracingStack(
    app, 
    "DistributedTracingStack",
    env=Environment(account=account, region=region),
    description="Distributed tracing implementation with X-Ray and EventBridge for microservices observability"
)

# Add tags to all resources
Tags.of(app).add("Project", "DistributedTracing")
Tags.of(app).add("Environment", "Demo")
Tags.of(app).add("Recipe", "distributed-tracing-x-ray-eventbridge")

app.synth()