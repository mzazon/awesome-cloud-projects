#!/usr/bin/env python3
"""
AWS CDK Python application for IoT Greengrass Edge Computing Recipe

This CDK application implements edge computing with AWS IoT Greengrass,
including IoT Core setup, Greengrass Core device configuration, Lambda
functions for edge processing, and Stream Manager for data routing.
"""

import aws_cdk as cdk
from aws_cdk import (
    App,
    Environment,
)
from constructs import Construct
from stacks.iot_greengrass_stack import IoTGreengrassStack


def main() -> None:
    """Main CDK application entry point"""
    app = App()
    
    # Get environment configuration from context or environment variables
    env = Environment(
        account=app.node.try_get_context("account") or cdk.Aws.ACCOUNT_ID,
        region=app.node.try_get_context("region") or cdk.Aws.REGION,
    )
    
    # Create the main IoT Greengrass stack
    iot_greengrass_stack = IoTGreengrassStack(
        app,
        "IoTGreengrassStack",
        env=env,
        description="AWS IoT Greengrass edge computing infrastructure for industrial IoT applications",
        tags={
            "Project": "IoTGreengrassEdgeComputing",
            "Environment": app.node.try_get_context("environment") or "development",
            "Recipe": "edge-computing-aws-iot-greengrass",
            "CostCenter": app.node.try_get_context("cost_center") or "iot-development",
        }
    )
    
    app.synth()


if __name__ == "__main__":
    main()