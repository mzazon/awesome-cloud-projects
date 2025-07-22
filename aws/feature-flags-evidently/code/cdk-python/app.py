#!/usr/bin/env python3
"""
AWS CDK application for Feature Flags with CloudWatch Evidently.

This application creates:
- IAM role for Lambda function
- CloudWatch Evidently project and feature flag
- Lambda function for feature evaluation
- Launch configuration for gradual rollout

Author: AWS CDK Recipe Generator
Version: 1.0
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_iam as iam,
    aws_lambda as lambda_,
    aws_evidently as evidently,
    aws_logs as logs,
    Duration,
    CfnOutput,
    RemovalPolicy
)
from constructs import Construct
import json


class FeatureFlagsEvidentlyStack(Stack):
    """
    Stack that implements feature flags using CloudWatch Evidently.
    
    This stack demonstrates how to use CloudWatch Evidently for safe feature
    deployments through controlled exposure and gradual rollouts.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique resource names using stack name
        stack_name = self.stack_name.lower()
        
        # Create CloudWatch Log Group for Evidently evaluations
        evidently_log_group = logs.LogGroup(
            self,
            "EvidentlyLogGroup",
            log_group_name="/aws/evidently/evaluations",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY
        )

        # Create Evidently project
        evidently_project = evidently.CfnProject(
            self,
            "FeatureDemoProject",
            name=f"feature-demo-{stack_name}",
            description="Feature flag demonstration project for CDK deployment",
            data_delivery=evidently.CfnProject.DataDeliveryProperty(
                cloud_watch_logs=evidently.CfnProject.CloudWatchLogsProperty(
                    log_group=evidently_log_group.log_group_name
                )
            )
        )

        # Create feature flag with boolean variations
        checkout_feature = evidently.CfnFeature(
            self,
            "CheckoutFeature",
            name="new-checkout-flow",
            project=evidently_project.name,
            description="Controls visibility of the new checkout experience",
            variations=[
                evidently.CfnFeature.VariationProperty(
                    variation_name="enabled",
                    boolean_value=True
                ),
                evidently.CfnFeature.VariationProperty(
                    variation_name="disabled",
                    boolean_value=False
                )
            ],
            default_variation="disabled"
        )
        
        # Ensure feature depends on project
        checkout_feature.add_dependency(evidently_project)

        # Create IAM role for Lambda function
        lambda_role = iam.Role(
            self,
            "EvidentlyLambdaRole",
            role_name=f"evidently-lambda-role-{stack_name}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="IAM role for Lambda function to evaluate Evidently features",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
            inline_policies={
                "EvidentlyAccess": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "evidently:EvaluateFeature",
                                "evidently:GetProject",
                                "evidently:GetFeature"
                            ],
                            resources=[
                                f"arn:aws:evidently:{self.region}:{self.account}:project/{evidently_project.name}",
                                f"arn:aws:evidently:{self.region}:{self.account}:project/{evidently_project.name}/feature/*"
                            ]
                        )
                    ]
                )
            }
        )

        # Create Lambda function for feature evaluation
        lambda_function = lambda_.Function(
            self,
            "EvidentlyDemoFunction",
            function_name=f"evidently-demo-{stack_name}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            role=lambda_role,
            timeout=Duration.seconds(30),
            description="Lambda function to demonstrate Evidently feature evaluation",
            environment={
                "PROJECT_NAME": evidently_project.name
            },
            code=lambda_.Code.from_inline("""
import json
import boto3
import os

def lambda_handler(event, context):
    \"\"\"
    Lambda function to evaluate feature flags using CloudWatch Evidently.
    
    Args:
        event: Lambda event containing userId
        context: Lambda context object
        
    Returns:
        dict: Response with feature evaluation result
    \"\"\"
    # Initialize Evidently client
    evidently = boto3.client('evidently')
    
    # Extract user information from event
    user_id = event.get('userId', 'anonymous-user')
    project_name = os.environ['PROJECT_NAME']
    
    try:
        # Evaluate feature flag for user
        response = evidently.evaluate_feature(
            project=project_name,
            feature='new-checkout-flow',
            entityId=user_id
        )
        
        feature_enabled = response['variation'] == 'enabled'
        
        # Log evaluation for debugging
        print(f"Feature evaluation for user {user_id}: {response['variation']}")
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'userId': user_id,
                'featureEnabled': feature_enabled,
                'variation': response['variation'],
                'reason': response.get('reason', 'default'),
                'project': project_name
            })
        }
        
    except Exception as e:
        print(f"Error evaluating feature: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Feature evaluation failed',
                'userId': user_id,
                'featureEnabled': False,  # Safe default
                'message': str(e)
            })
        }
""")
        )

        # Create launch configuration for gradual rollout
        # Note: Using current timestamp for immediate start
        launch_config = evidently.CfnLaunch(
            self,
            "CheckoutGradualRollout",
            name="checkout-gradual-rollout",
            project=evidently_project.name,
            description="Gradual rollout of new checkout flow to 10% of users",
            groups=[
                evidently.CfnLaunch.LaunchGroupProperty(
                    group_name="control-group",
                    description="Users with existing checkout flow",
                    feature="new-checkout-flow",
                    variation="disabled"
                ),
                evidently.CfnLaunch.LaunchGroupProperty(
                    group_name="treatment-group",
                    description="Users with new checkout flow", 
                    feature="new-checkout-flow",
                    variation="enabled"
                )
            ],
            scheduled_splits_config=evidently.CfnLaunch.ScheduledSplitsConfigProperty(
                steps=[
                    evidently.CfnLaunch.ScheduledSplitProperty(
                        group_weights={
                            "control-group": 90,
                            "treatment-group": 10
                        },
                        start_time="2024-01-01T00:00:00Z"  # Will be updated manually
                    )
                ]
            )
        )
        
        # Ensure launch depends on feature
        launch_config.add_dependency(checkout_feature)

        # Stack outputs for reference and testing
        CfnOutput(
            self,
            "EvidentlyProjectName",
            value=evidently_project.name,
            description="Name of the CloudWatch Evidently project",
            export_name=f"{self.stack_name}-ProjectName"
        )

        CfnOutput(
            self,
            "LambdaFunctionName", 
            value=lambda_function.function_name,
            description="Name of the Lambda function for feature evaluation",
            export_name=f"{self.stack_name}-LambdaFunction"
        )

        CfnOutput(
            self,
            "FeatureName",
            value=checkout_feature.name,
            description="Name of the feature flag",
            export_name=f"{self.stack_name}-FeatureName"
        )

        CfnOutput(
            self,
            "LaunchName",
            value=launch_config.name,
            description="Name of the launch configuration",
            export_name=f"{self.stack_name}-LaunchName"
        )

        CfnOutput(
            self,
            "TestCommand",
            value=f"aws lambda invoke --function-name {lambda_function.function_name} --payload '{{\"userId\": \"test-user-123\"}}' response.json",
            description="Command to test the Lambda function",
            export_name=f"{self.stack_name}-TestCommand"
        )


app = cdk.App()

# Create the stack with a descriptive name
FeatureFlagsEvidentlyStack(
    app, 
    "FeatureFlagsEvidentlyStack",
    description="Implementation of feature flags using CloudWatch Evidently with Lambda evaluation"
)

app.synth()