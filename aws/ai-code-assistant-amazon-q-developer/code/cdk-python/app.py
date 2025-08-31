#!/usr/bin/env python3
"""
CDK Application for Amazon Q Developer AI Code Assistant Setup

This CDK application creates the necessary IAM infrastructure to support
Amazon Q Developer usage in development environments. It provides proper
permissions for developers to use Amazon Q with AWS Builder ID authentication.
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_iam as iam,
    CfnOutput,
    Tags
)
from constructs import Construct
from typing import Dict, Any


class AmazonQDeveloperStack(Stack):
    """
    Stack for Amazon Q Developer infrastructure setup.
    
    This stack creates IAM roles and policies that enable proper integration
    between Amazon Q Developer and AWS services. It follows AWS security
    best practices with least privilege access principles.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs: Dict[str, Any]) -> None:
        super().__init__(scope, construct_id, **kwargs)
        
        # Create IAM role for Amazon Q Developer service integration
        self.q_developer_role = self._create_q_developer_role()
        
        # Create IAM policy for enhanced Q Developer capabilities
        self.q_developer_policy = self._create_q_developer_policy()
        
        # Attach policy to role
        self.q_developer_role.attach_inline_policy(self.q_developer_policy)
        
        # Create IAM group for developers using Amazon Q
        self.developer_group = self._create_developer_group()
        
        # Create outputs for reference
        self._create_outputs()
        
        # Add tags to all resources
        self._add_tags()

    def _create_q_developer_role(self) -> iam.Role:
        """
        Create IAM role for Amazon Q Developer service integration.
        
        Returns:
            iam.Role: The created IAM role for Amazon Q Developer
        """
        # Define trust policy for Amazon Q service
        trust_policy = iam.PolicyDocument(
            statements=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    principals=[
                        iam.ServicePrincipal("amazon-q.amazonaws.com"),
                        iam.ServicePrincipal("bedrock.amazonaws.com")
                    ],
                    actions=["sts:AssumeRole"],
                    conditions={
                        "StringEquals": {
                            "aws:SourceAccount": self.account
                        }
                    }
                )
            ]
        )
        
        return iam.Role(
            self,
            "AmazonQDeveloperRole",
            role_name="AmazonQDeveloperServiceRole",
            description="IAM role for Amazon Q Developer service integration",
            assumed_by=iam.CompositePrincipal(
                iam.ServicePrincipal("amazon-q.amazonaws.com"),
                iam.ServicePrincipal("bedrock.amazonaws.com")
            ),
            inline_policies={
                "AmazonQDeveloperBasePolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "bedrock:InvokeModel",
                                "bedrock:InvokeModelWithResponseStream",
                                "bedrock:GetFoundationModel",
                                "bedrock:ListFoundationModels"
                            ],
                            resources=["*"],
                            conditions={
                                "StringEquals": {
                                    "aws:RequestedRegion": [
                                        "us-east-1",
                                        "us-west-2"
                                    ]
                                }
                            }
                        )
                    ]
                )
            },
            max_session_duration=cdk.Duration.hours(12)
        )

    def _create_q_developer_policy(self) -> iam.Policy:
        """
        Create IAM policy for enhanced Amazon Q Developer capabilities.
        
        Returns:
            iam.Policy: The created IAM policy for Amazon Q Developer
        """
        policy_statements = [
            # CloudWatch Logs access for code analysis
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents",
                    "logs:DescribeLogGroups",
                    "logs:DescribeLogStreams"
                ],
                resources=[
                    f"arn:aws:logs:{self.region}:{self.account}:log-group:/aws/amazon-q/*"
                ]
            ),
            # CodeWhisperer integration (legacy service name for Q Developer)
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "codewhisperer:GenerateRecommendations",
                    "codewhisperer:GetRecommendations"
                ],
                resources=["*"]
            ),
            # Basic AWS service information access
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "iam:GetRole",
                    "iam:GetPolicy",
                    "iam:ListRoles",
                    "iam:ListPolicies",
                    "sts:GetCallerIdentity"
                ],
                resources=["*"]
            )
        ]
        
        return iam.Policy(
            self,
            "AmazonQDeveloperEnhancedPolicy",
            policy_name="AmazonQDeveloperEnhancedAccess",
            statements=policy_statements,
            description="Enhanced policy for Amazon Q Developer capabilities"
        )

    def _create_developer_group(self) -> iam.Group:
        """
        Create IAM group for developers using Amazon Q Developer.
        
        Returns:
            iam.Group: The created IAM group for developers
        """
        # Create policy for developers to assume the Q Developer role
        assume_role_policy = iam.PolicyDocument(
            statements=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=["sts:AssumeRole"],
                    resources=[self.q_developer_role.role_arn],
                    conditions={
                        "StringEquals": {
                            "aws:RequestedRegion": [
                                "us-east-1",
                                "us-west-2"
                            ]
                        }
                    }
                ),
                # Allow developers to access their own AWS Builder ID information
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "sts:GetCallerIdentity",
                        "iam:GetUser",
                        "iam:ListAttachedUserPolicies"
                    ],
                    resources=["*"]
                )
            ]
        )
        
        return iam.Group(
            self,
            "AmazonQDevelopersGroup",
            group_name="AmazonQDevelopers",
            inline_policies={
                "AmazonQDeveloperAccess": assume_role_policy
            }
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information."""
        CfnOutput(
            self,
            "QDeveloperRoleArn",
            value=self.q_developer_role.role_arn,
            description="ARN of the Amazon Q Developer service role",
            export_name=f"{self.stack_name}-QDeveloperRoleArn"
        )
        
        CfnOutput(
            self,
            "QDeveloperRoleName",
            value=self.q_developer_role.role_name,
            description="Name of the Amazon Q Developer service role",
            export_name=f"{self.stack_name}-QDeveloperRoleName"
        )
        
        CfnOutput(
            self,
            "DeveloperGroupName",
            value=self.developer_group.group_name,
            description="Name of the IAM group for Amazon Q Developer users",
            export_name=f"{self.stack_name}-DeveloperGroupName"
        )
        
        CfnOutput(
            self,
            "DeveloperGroupArn",
            value=self.developer_group.group_arn,
            description="ARN of the IAM group for Amazon Q Developer users",
            export_name=f"{self.stack_name}-DeveloperGroupArn"
        )

    def _add_tags(self) -> None:
        """Add tags to all resources in the stack."""
        Tags.of(self).add("Project", "AmazonQDeveloper")
        Tags.of(self).add("Purpose", "AI-Code-Assistant")
        Tags.of(self).add("Environment", "Development")
        Tags.of(self).add("ManagedBy", "CDK")


class AmazonQDeveloperApp(cdk.App):
    """
    CDK Application for Amazon Q Developer setup.
    
    This application creates the necessary infrastructure for Amazon Q Developer
    integration with proper IAM roles and permissions.
    """
    
    def __init__(self) -> None:
        super().__init__()
        
        # Get environment configuration
        env = cdk.Environment(
            account=self.node.try_get_context("account") or None,
            region=self.node.try_get_context("region") or "us-east-1"
        )
        
        # Create the main stack
        AmazonQDeveloperStack(
            self,
            "AmazonQDeveloperStack",
            env=env,
            description="Infrastructure for Amazon Q Developer AI Code Assistant setup",
            stack_name="amazon-q-developer-stack"
        )


# Main application entry point
app = AmazonQDeveloperApp()
app.synth()