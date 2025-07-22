#!/usr/bin/env python3
"""
AWS CDK Python Application for Multi-Agent AI Workflows with Amazon Bedrock AgentCore

This application deploys a complete multi-agent AI system using Amazon Bedrock agents,
AWS Lambda for orchestration, Amazon EventBridge for event-driven coordination,
and DynamoDB for shared memory management.
"""

import os
from typing import Optional

import aws_cdk as cdk
from constructs import Construct

from multi_agent_workflow.multi_agent_workflow_stack import MultiAgentWorkflowStack


class MultiAgentWorkflowApp(cdk.App):
    """Main CDK application for the multi-agent AI workflow system."""

    def __init__(self) -> None:
        super().__init__()

        # Get configuration from environment variables or context
        env_account: Optional[str] = os.environ.get('CDK_DEFAULT_ACCOUNT')
        env_region: Optional[str] = os.environ.get('CDK_DEFAULT_REGION')

        # Environment configuration
        env = cdk.Environment(
            account=env_account or self.node.try_get_context('account'),
            region=env_region or self.node.try_get_context('region') or 'us-east-1'
        )

        # Create the multi-agent workflow stack
        MultiAgentWorkflowStack(
            self,
            "MultiAgentWorkflowStack",
            env=env,
            description="Multi-Agent AI Workflows with Amazon Bedrock AgentCore, EventBridge, and Lambda orchestration"
        )


def main() -> None:
    """Main entry point for the CDK application."""
    app = MultiAgentWorkflowApp()
    
    # Add common tags to all resources
    cdk.Tags.of(app).add("Project", "MultiAgentWorkflow")
    cdk.Tags.of(app).add("Environment", "Production")
    cdk.Tags.of(app).add("ManagedBy", "CDK")
    cdk.Tags.of(app).add("Recipe", "multi-agent-ai-workflows-bedrock-agentcore")
    
    app.synth()


if __name__ == "__main__":
    main()