#!/usr/bin/env python3
"""
CDK Python application for Simple Random Data API with Lambda and API Gateway

This application creates a serverless REST API using AWS Lambda and API Gateway
that generates random data including quotes, numbers, and colors.

Author: AWS CDK Generator
Version: 1.0
"""

import os
from typing import Any, Dict

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    CfnOutput,
    aws_lambda as _lambda,
    aws_apigateway as apigateway,
    aws_iam as iam,
    aws_logs as logs,
)
from constructs import Construct


class SimpleRandomDataApiStack(Stack):
    """
    CDK Stack for Simple Random Data API
    
    Creates a serverless REST API using Lambda and API Gateway that generates
    random quotes, numbers, and colors based on query parameters.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs: Any) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Create Lambda execution role with basic execution permissions
        lambda_role = iam.Role(
            self,
            "RandomDataApiLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="IAM role for Random Data API Lambda function",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
        )

        # Create CloudWatch Log Group for Lambda function
        log_group = logs.LogGroup(
            self,
            "RandomDataApiLogGroup",
            log_group_name=f"/aws/lambda/random-data-api-{construct_id.lower()}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=cdk.RemovalPolicy.DESTROY,
        )

        # Create Lambda function for random data generation
        random_data_function = _lambda.Function(
            self,
            "RandomDataFunction",
            runtime=_lambda.Runtime.PYTHON_3_12,
            handler="index.lambda_handler",
            role=lambda_role,
            code=_lambda.Code.from_inline(self._get_lambda_code()),
            description="Generates random quotes, numbers, and colors via REST API",
            timeout=Duration.seconds(30),
            memory_size=128,
            environment={
                "LOG_LEVEL": "INFO",
            },
            log_group=log_group,
        )

        # Create API Gateway REST API
        api = apigateway.RestApi(
            self,
            "RandomDataApi",
            rest_api_name="Random Data API",
            description="Serverless API for generating random data",
            endpoint_configuration=apigateway.EndpointConfiguration(
                types=[apigateway.EndpointType.REGIONAL]
            ),
            default_cors_preflight_options=apigateway.CorsOptions(
                allow_origins=["*"],
                allow_methods=["GET", "OPTIONS"],
                allow_headers=["Content-Type", "Authorization"],
            ),
            cloud_watch_role=True,
        )

        # Create /random resource
        random_resource = api.root.add_resource("random")

        # Create Lambda integration with proxy integration
        lambda_integration = apigateway.LambdaIntegration(
            random_data_function,
            proxy=True,
            integration_responses=[
                apigateway.IntegrationResponse(
                    status_code="200",
                    response_parameters={
                        "method.response.header.Access-Control-Allow-Origin": "'*'"
                    },
                )
            ],
        )

        # Add GET method to /random resource
        random_resource.add_method(
            "GET",
            lambda_integration,
            method_responses=[
                apigateway.MethodResponse(
                    status_code="200",
                    response_parameters={
                        "method.response.header.Access-Control-Allow-Origin": True
                    },
                )
            ],
        )

        # Create deployment and stage
        deployment = apigateway.Deployment(
            self,
            "RandomDataApiDeployment",
            api=api,
            description="Initial deployment of Random Data API",
        )

        stage = apigateway.Stage(
            self,
            "DevStage",
            deployment=deployment,
            stage_name="dev",
            description="Development stage for Random Data API",
            throttle=apigateway.ThrottleSettings(
                rate_limit=1000,
                burst_limit=2000,
            ),
        )

        # Output the API endpoint URL
        CfnOutput(
            self,
            "ApiEndpointUrl",
            value=f"{api.url}random",
            description="URL of the Random Data API endpoint",
        )

        # Output the Lambda function name
        CfnOutput(
            self,
            "LambdaFunctionName",
            value=random_data_function.function_name,
            description="Name of the Lambda function",
        )

        # Output the API Gateway ID
        CfnOutput(
            self,
            "ApiGatewayId",
            value=api.rest_api_id,
            description="ID of the API Gateway REST API",
        )

        # Output the CloudWatch Log Group
        CfnOutput(
            self,
            "LogGroupName",
            value=log_group.log_group_name,
            description="Name of the CloudWatch Log Group",
        )

    def _get_lambda_code(self) -> str:
        """
        Returns the Lambda function code as an inline string.
        
        Returns:
            str: The complete Lambda function code
        """
        return '''
import json
import random
import logging
import os

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

def lambda_handler(event, context):
    """
    AWS Lambda handler for random data API
    Returns random quotes, numbers, or colors based on query parameter
    """
    
    try:
        # Log the incoming request
        logger.info(f"Received event: {json.dumps(event)}")
        
        # Parse query parameters
        query_params = event.get('queryStringParameters') or {}
        data_type = query_params.get('type', 'quote').lower()
        
        # Random data collections
        quotes = [
            "The only way to do great work is to love what you do. - Steve Jobs",
            "Innovation distinguishes between a leader and a follower. - Steve Jobs",
            "Life is what happens to you while you're busy making other plans. - John Lennon",
            "The future belongs to those who believe in the beauty of their dreams. - Eleanor Roosevelt",
            "Success is not final, failure is not fatal: it is the courage to continue that counts. - Winston Churchill"
        ]
        
        colors = [
            {"name": "Ocean Blue", "hex": "#006994", "rgb": "rgb(0, 105, 148)"},
            {"name": "Sunset Orange", "hex": "#FF6B35", "rgb": "rgb(255, 107, 53)"},
            {"name": "Forest Green", "hex": "#2E8B57", "rgb": "rgb(46, 139, 87)"},
            {"name": "Purple Haze", "hex": "#9370DB", "rgb": "rgb(147, 112, 219)"},
            {"name": "Golden Yellow", "hex": "#FFD700", "rgb": "rgb(255, 215, 0)"}
        ]
        
        # Generate response based on type
        if data_type == 'quote':
            data = random.choice(quotes)
        elif data_type == 'number':
            data = random.randint(1, 1000)
        elif data_type == 'color':
            data = random.choice(colors)
        else:
            # Default to quote for unknown types
            data = random.choice(quotes)
            data_type = 'quote'
        
        # Create response
        response_body = {
            'type': data_type,
            'data': data,
            'timestamp': context.aws_request_id,
            'message': f'Random {data_type} generated successfully'
        }
        
        # Return successful response with CORS headers
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'GET',
                'Access-Control-Allow-Headers': 'Content-Type'
            },
            'body': json.dumps(response_body)
        }
        
    except Exception as e:
        logger.error(f"Error processing request: {str(e)}")
        
        # Return error response
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Internal server error',
                'message': 'Failed to generate random data'
            })
        }
'''


app = cdk.App()

# Get stack name from context or use default
stack_name = app.node.try_get_context("stack_name") or "SimpleRandomDataApiStack"

# Create the stack
SimpleRandomDataApiStack(
    app, 
    stack_name,
    description="Simple Random Data API using Lambda and API Gateway",
    env=cdk.Environment(
        account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
        region=os.environ.get("CDK_DEFAULT_REGION"),
    ),
)

app.synth()