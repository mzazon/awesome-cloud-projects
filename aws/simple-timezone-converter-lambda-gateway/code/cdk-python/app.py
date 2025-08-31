#!/usr/bin/env python3
"""
AWS CDK Python application for Simple Timezone Converter with Lambda and API Gateway.

This CDK application creates a serverless REST API that converts timestamps between 
different timezones using AWS Lambda and API Gateway. The solution provides a 
centralized, scalable timezone conversion service with automatic daylight saving 
time handling.

Architecture Components:
- AWS Lambda function for timezone conversion logic
- API Gateway REST API with /convert endpoint  
- IAM role with CloudWatch Logs permissions
- CloudWatch Log Group for Lambda function logs

Author: AWS CDK Python Generator
Version: 1.0
"""

import os
from typing import Dict, Any

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


class TimezoneConverterStack(Stack):
    """
    CDK Stack for the Timezone Converter serverless application.
    
    This stack creates all the necessary AWS resources for a timezone
    conversion REST API including Lambda function, API Gateway, and
    appropriate IAM permissions.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Create CloudWatch Log Group for Lambda function
        log_group = logs.LogGroup(
            self,
            "TimezoneConverterLogGroup",
            log_group_name=f"/aws/lambda/timezone-converter-{self.stack_name.lower()}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=cdk.RemovalPolicy.DESTROY,
        )

        # Create IAM role for Lambda execution
        lambda_role = iam.Role(
            self,
            "TimezoneConverterLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Execution role for timezone converter Lambda function",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
        )

        # Grant permissions to write to the specific log group
        log_group.grant_write(lambda_role)

        # Create Lambda function for timezone conversion
        timezone_function = _lambda.Function(
            self,
            "TimezoneConverterFunction",
            runtime=_lambda.Runtime.PYTHON_3_12,
            handler="lambda_function.lambda_handler",
            role=lambda_role,
            code=_lambda.Code.from_inline(self._get_lambda_code()),
            timeout=Duration.seconds(30),
            memory_size=128,
            description="Simple timezone converter API function",
            environment={
                "LOG_LEVEL": "INFO",
            },
            log_group=log_group,
        )

        # Create API Gateway REST API
        api = apigateway.RestApi(
            self,
            "TimezoneConverterApi",
            rest_api_name="timezone-converter-api",
            description="Timezone converter REST API",
            endpoint_configuration=apigateway.EndpointConfiguration(
                types=[apigateway.EndpointType.REGIONAL]
            ),
            default_cors_preflight_options=apigateway.CorsOptions(
                allow_origins=apigateway.Cors.ALL_ORIGINS,
                allow_methods=apigateway.Cors.ALL_METHODS,
                allow_headers=["Content-Type", "Authorization"],
            ),
            deploy_options=apigateway.StageOptions(
                stage_name="prod",
                description="Production stage for timezone converter API",
                throttling_rate_limit=100,
                throttling_burst_limit=200,
            ),
        )

        # Create /convert resource
        convert_resource = api.root.add_resource("convert")

        # Create Lambda integration
        convert_integration = apigateway.LambdaIntegration(
            timezone_function,
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

        # Add POST method to /convert resource
        convert_resource.add_method(
            "POST",
            convert_integration,
            method_responses=[
                apigateway.MethodResponse(
                    status_code="200",
                    response_parameters={
                        "method.response.header.Access-Control-Allow-Origin": True
                    },
                )
            ],
        )

        # Output the API endpoint URL
        CfnOutput(
            self,
            "ApiEndpoint",
            value=f"{api.url}convert",
            description="API Gateway endpoint URL for timezone conversion",
            export_name=f"{self.stack_name}-ApiEndpoint",
        )

        # Output the Lambda function name
        CfnOutput(
            self,
            "LambdaFunctionName",
            value=timezone_function.function_name,
            description="Name of the timezone converter Lambda function",
            export_name=f"{self.stack_name}-LambdaFunctionName",
        )

        # Output the API Gateway REST API ID
        CfnOutput(
            self,
            "ApiId",
            value=api.rest_api_id,
            description="API Gateway REST API ID",
            export_name=f"{self.stack_name}-ApiId",
        )

    def _get_lambda_code(self) -> str:
        """
        Return the Lambda function code as an inline string.
        
        This method contains the complete timezone conversion logic
        that handles timezone conversions using Python's built-in
        zoneinfo module for accurate IANA timezone database support.
        
        Returns:
            str: Complete Lambda function code
        """
        return '''import json
import logging
from datetime import datetime
from zoneinfo import ZoneInfo

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Convert timestamp between timezones
    
    Expected event format:
    {
      "timestamp": "2025-07-12T15:30:00",
      "from_timezone": "UTC",
      "to_timezone": "America/New_York"
    }
    """
    try:
        # Parse the request body
        if 'body' in event:
            body = json.loads(event['body'])
        else:
            body = event
        
        # Extract required parameters
        timestamp_str = body.get('timestamp')
        from_tz = body.get('from_timezone', 'UTC')
        to_tz = body.get('to_timezone')
        
        # Validate required parameters
        if not timestamp_str or not to_tz:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'error': 'Missing required parameters: timestamp and to_timezone'
                })
            }
        
        # Parse the timestamp
        try:
            # Try parsing with timezone info first
            if 'T' in timestamp_str and ('+' in timestamp_str or 'Z' in timestamp_str):
                dt = datetime.fromisoformat(timestamp_str.replace('Z', '+00:00'))
            else:
                # Parse as naive datetime and assign source timezone
                dt_naive = datetime.fromisoformat(timestamp_str)
                dt = dt_naive.replace(tzinfo=ZoneInfo(from_tz))
        except ValueError as e:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'error': f'Invalid timestamp format: {str(e)}'
                })
            }
        
        # Convert to target timezone
        try:
            target_tz = ZoneInfo(to_tz)
            converted_dt = dt.astimezone(target_tz)
        except Exception as e:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'error': f'Invalid timezone: {str(e)}'
                })
            }
        
        # Format response
        response_data = {
            'original_timestamp': timestamp_str,
            'original_timezone': from_tz,
            'converted_timestamp': converted_dt.isoformat(),
            'target_timezone': to_tz,
            'timezone_offset': converted_dt.strftime('%z'),
            'timezone_name': converted_dt.tzname()
        }
        
        logger.info(f"Converted {timestamp_str} from {from_tz} to {to_tz}")
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps(response_data)
        }
        
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Internal server error'
            })
        }
'''


def main() -> None:
    """
    Main entry point for the CDK application.
    
    Creates the CDK app and instantiates the TimezoneConverter stack
    with appropriate environment configuration and stack properties.
    """
    app = cdk.App()
    
    # Get environment configuration
    env = cdk.Environment(
        account=os.getenv('CDK_DEFAULT_ACCOUNT'),
        region=os.getenv('CDK_DEFAULT_REGION', 'us-east-1')
    )
    
    # Create the timezone converter stack
    TimezoneConverterStack(
        app,
        "TimezoneConverterStack",
        env=env,
        description="Simple timezone converter with Lambda and API Gateway",
        tags={
            "Project": "TimezoneConverter",
            "Environment": "Production",
            "ManagedBy": "CDK",
            "Service": "Serverless",
        }
    )
    
    # Synthesize the CloudFormation template
    app.synth()


if __name__ == "__main__":
    main()