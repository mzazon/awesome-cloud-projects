#!/usr/bin/env python3
"""
CDK Python application for API Throttling and Rate Limiting.

This application creates a complete API Gateway infrastructure with:
- REST API with Lambda integration
- Multiple usage plans for different customer tiers
- API keys with tier-specific throttling limits
- CloudWatch monitoring and alarms
- Comprehensive IAM roles and permissions

Author: AWS CDK Generator
Version: 1.0
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_apigateway as apigateway,
    aws_lambda as lambda_,
    aws_iam as iam,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
)
from constructs import Construct


class ApiThrottlingStack(Stack):
    """
    CDK Stack for API throttling and rate limiting implementation.
    
    This stack creates a comprehensive API Gateway setup with multi-tier
    throttling capabilities, demonstrating enterprise-grade rate limiting
    and customer tier management.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Stack parameters
        self.api_name = f"throttling-demo-{cdk.Aws.STACK_NAME.lower()}"
        self.stage_name = "prod"
        
        # Create Lambda backend function
        self.backend_function = self._create_backend_function()
        
        # Create REST API with throttling
        self.api = self._create_rest_api()
        
        # Create usage plans and API keys
        self.usage_plans = self._create_usage_plans()
        self.api_keys = self._create_api_keys()
        
        # Associate API keys with usage plans
        self._associate_keys_with_plans()
        
        # Create CloudWatch monitoring
        self._create_monitoring()
        
        # Create stack outputs
        self._create_outputs()

    def _create_backend_function(self) -> lambda_.Function:
        """
        Create the Lambda function that serves as the API backend.
        
        Returns:
            lambda_.Function: The created Lambda function
        """
        # Create Lambda execution role
        lambda_role = iam.Role(
            self,
            "LambdaExecutionRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
            description="Execution role for API throttling demo Lambda function"
        )

        # Create Lambda function
        backend_function = lambda_.Function(
            self,
            "ApiBackendFunction",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            role=lambda_role,
            code=lambda_.Code.from_inline("""
import json
import time
import os

def lambda_handler(event, context):
    \"\"\"
    Simple API backend that returns a JSON response with request metadata.
    Includes artificial processing delay to simulate real workload.
    \"\"\"
    # Simulate some processing time
    time.sleep(0.1)
    
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'X-Request-ID': context.aws_request_id
        },
        'body': json.dumps({
            'message': 'Hello from throttled API!',
            'timestamp': int(time.time()),
            'requestId': context.aws_request_id,
            'region': os.environ.get('AWS_REGION', 'unknown'),
            'functionName': context.function_name,
            'remainingTime': context.get_remaining_time_in_millis()
        })
    }
            """),
            timeout=Duration.seconds(30),
            memory_size=128,
            description="Backend function for API throttling demonstration",
            environment={
                "API_NAME": self.api_name,
                "STAGE_NAME": self.stage_name
            },
            # Create log group with retention
            log_retention=logs.RetentionDays.ONE_WEEK
        )

        return backend_function

    def _create_rest_api(self) -> apigateway.RestApi:
        """
        Create the REST API with Lambda integration and throttling configuration.
        
        Returns:
            apigateway.RestApi: The created REST API
        """
        # Create REST API
        api = apigateway.RestApi(
            self,
            "ThrottlingDemoApi",
            rest_api_name=self.api_name,
            description="Demo API for throttling and rate limiting implementation",
            deploy=True,
            deploy_options=apigateway.StageOptions(
                stage_name=self.stage_name,
                description="Production stage with comprehensive throttling controls",
                # Stage-level throttling (default limits for all methods)
                throttle_rate_limit=1000,
                throttle_burst_limit=2000,
                # Enable detailed CloudWatch metrics
                metrics_enabled=True,
                logging_level=apigateway.MethodLoggingLevel.INFO,
                data_trace_enabled=True,
                # Create access log group
                access_log_destination=apigateway.LogGroupLogDestination(
                    logs.LogGroup(
                        self,
                        "ApiAccessLogs",
                        log_group_name=f"/aws/apigateway/{self.api_name}",
                        retention=logs.RetentionDays.ONE_WEEK,
                        removal_policy=RemovalPolicy.DESTROY
                    )
                ),
                access_log_format=apigateway.AccessLogFormat.json_with_standard_fields()
            ),
            # Global API configuration
            endpoint_configuration=apigateway.EndpointConfiguration(
                types=[apigateway.EndpointType.REGIONAL]
            ),
            # Default 4xx and 5xx response templates
            default_cors_preflight_options=apigateway.CorsOptions(
                allow_origins=["*"],
                allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
                allow_headers=["Content-Type", "X-Amz-Date", "Authorization", "X-Api-Key"]
            )
        )

        # Create Lambda integration
        lambda_integration = apigateway.LambdaIntegration(
            self.backend_function,
            proxy=True,
            integration_responses=[
                apigateway.IntegrationResponse(
                    status_code="200",
                    response_parameters={
                        "method.response.header.Access-Control-Allow-Origin": "'*'"
                    }
                )
            ]
        )

        # Create /data resource
        data_resource = api.root.add_resource("data")
        
        # Add GET method with API key requirement
        data_resource.add_method(
            "GET",
            lambda_integration,
            api_key_required=True,
            authorization_type=apigateway.AuthorizationType.NONE,
            method_responses=[
                apigateway.MethodResponse(
                    status_code="200",
                    response_parameters={
                        "method.response.header.Access-Control-Allow-Origin": True
                    }
                )
            ]
        )

        return api

    def _create_usage_plans(self) -> Dict[str, apigateway.UsagePlan]:
        """
        Create usage plans for different customer tiers with varying throttling limits.
        
        Returns:
            Dict[str, apigateway.UsagePlan]: Dictionary of usage plans by tier name
        """
        usage_plans = {}

        # Premium Usage Plan - High limits for enterprise customers
        usage_plans["premium"] = apigateway.UsagePlan(
            self,
            "PremiumUsagePlan",
            name=f"Premium-Plan-{cdk.Aws.STACK_NAME}",
            description="Premium tier with high rate limits and generous quotas",
            throttle=apigateway.ThrottleSettings(
                rate_limit=2000,  # 2000 requests per second
                burst_limit=5000  # 5000 burst capacity
            ),
            quota=apigateway.QuotaSettings(
                limit=1000000,  # 1 million requests per month
                period=apigateway.Period.MONTH
            ),
            api_stages=[
                apigateway.UsagePlanPerApiStage(
                    api=self.api,
                    stage=self.api.deployment_stage
                )
            ]
        )

        # Standard Usage Plan - Moderate limits for regular customers
        usage_plans["standard"] = apigateway.UsagePlan(
            self,
            "StandardUsagePlan",
            name=f"Standard-Plan-{cdk.Aws.STACK_NAME}",
            description="Standard tier with moderate rate limits and quotas",
            throttle=apigateway.ThrottleSettings(
                rate_limit=500,   # 500 requests per second
                burst_limit=1000  # 1000 burst capacity
            ),
            quota=apigateway.QuotaSettings(
                limit=100000,  # 100,000 requests per month
                period=apigateway.Period.MONTH
            ),
            api_stages=[
                apigateway.UsagePlanPerApiStage(
                    api=self.api,
                    stage=self.api.deployment_stage
                )
            ]
        )

        # Basic Usage Plan - Low limits for free tier customers
        usage_plans["basic"] = apigateway.UsagePlan(
            self,
            "BasicUsagePlan",
            name=f"Basic-Plan-{cdk.Aws.STACK_NAME}",
            description="Basic tier with low rate limits suitable for development and testing",
            throttle=apigateway.ThrottleSettings(
                rate_limit=100,  # 100 requests per second
                burst_limit=200  # 200 burst capacity
            ),
            quota=apigateway.QuotaSettings(
                limit=10000,  # 10,000 requests per month
                period=apigateway.Period.MONTH
            ),
            api_stages=[
                apigateway.UsagePlanPerApiStage(
                    api=self.api,
                    stage=self.api.deployment_stage
                )
            ]
        )

        return usage_plans

    def _create_api_keys(self) -> Dict[str, apigateway.ApiKey]:
        """
        Create API keys for different customer tiers.
        
        Returns:
            Dict[str, apigateway.ApiKey]: Dictionary of API keys by tier name
        """
        api_keys = {}

        # Premium API Key
        api_keys["premium"] = apigateway.ApiKey(
            self,
            "PremiumApiKey",
            api_key_name=f"premium-customer-{cdk.Aws.STACK_NAME}",
            description="API key for premium tier customers with high rate limits",
            enabled=True
        )

        # Standard API Key
        api_keys["standard"] = apigateway.ApiKey(
            self,
            "StandardApiKey",
            api_key_name=f"standard-customer-{cdk.Aws.STACK_NAME}",
            description="API key for standard tier customers with moderate rate limits",
            enabled=True
        )

        # Basic API Key
        api_keys["basic"] = apigateway.ApiKey(
            self,
            "BasicApiKey",
            api_key_name=f"basic-customer-{cdk.Aws.STACK_NAME}",
            description="API key for basic tier customers with limited rate limits",
            enabled=True
        )

        return api_keys

    def _associate_keys_with_plans(self) -> None:
        """
        Associate API keys with their corresponding usage plans to enable throttling.
        """
        for tier in ["premium", "standard", "basic"]:
            apigateway.UsagePlanKey(
                self,
                f"{tier.capitalize()}UsagePlanKey",
                usage_plan=self.usage_plans[tier],
                api_key=self.api_keys[tier]
            )

    def _create_monitoring(self) -> None:
        """
        Create CloudWatch alarms for monitoring API performance and throttling events.
        """
        # Alarm for high throttling events
        cloudwatch.Alarm(
            self,
            "HighThrottlingAlarm",
            alarm_name=f"API-High-Throttling-{cdk.Aws.STACK_NAME}",
            alarm_description="Alert when API throttling events exceed threshold",
            metric=cloudwatch.Metric(
                namespace="AWS/ApiGateway",
                metric_name="Count",
                dimensions_map={
                    "ApiName": self.api_name,
                    "Stage": self.stage_name
                },
                statistic="Sum",
                period=Duration.minutes(5)
            ),
            threshold=100,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD
        )

        # Alarm for high 4xx error rate
        cloudwatch.Alarm(
            self,
            "High4xxErrorsAlarm",
            alarm_name=f"API-High-4xx-Errors-{cdk.Aws.STACK_NAME}",
            alarm_description="Alert when 4xx errors exceed threshold indicating potential abuse",
            metric=cloudwatch.Metric(
                namespace="AWS/ApiGateway",
                metric_name="4XXError",
                dimensions_map={
                    "ApiName": self.api_name,
                    "Stage": self.stage_name
                },
                statistic="Sum",
                period=Duration.minutes(5)
            ),
            threshold=50,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD
        )

        # Alarm for high latency indicating backend stress
        cloudwatch.Alarm(
            self,
            "HighLatencyAlarm",
            alarm_name=f"API-High-Latency-{cdk.Aws.STACK_NAME}",
            alarm_description="Alert when API latency is consistently high",
            metric=cloudwatch.Metric(
                namespace="AWS/ApiGateway",
                metric_name="Latency",
                dimensions_map={
                    "ApiName": self.api_name,
                    "Stage": self.stage_name
                },
                statistic="Average",
                period=Duration.minutes(5)
            ),
            threshold=5000,  # 5 seconds
            evaluation_periods=3,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD
        )

    def _create_outputs(self) -> None:
        """
        Create CloudFormation outputs for important resource identifiers and API information.
        """
        # API Gateway outputs
        CfnOutput(
            self,
            "ApiGatewayId",
            value=self.api.rest_api_id,
            description="REST API Gateway ID"
        )

        CfnOutput(
            self,
            "ApiGatewayUrl",
            value=f"https://{self.api.rest_api_id}.execute-api.{self.region}.amazonaws.com/{self.stage_name}",
            description="API Gateway base URL"
        )

        CfnOutput(
            self,
            "ApiEndpointUrl",
            value=f"https://{self.api.rest_api_id}.execute-api.{self.region}.amazonaws.com/{self.stage_name}/data",
            description="API data endpoint URL (requires X-API-Key header)"
        )

        # Lambda function outputs
        CfnOutput(
            self,
            "LambdaFunctionName",
            value=self.backend_function.function_name,
            description="Backend Lambda function name"
        )

        CfnOutput(
            self,
            "LambdaFunctionArn",
            value=self.backend_function.function_arn,
            description="Backend Lambda function ARN"
        )

        # Usage plan outputs
        for tier in ["premium", "standard", "basic"]:
            CfnOutput(
                self,
                f"{tier.capitalize()}UsagePlanId",
                value=self.usage_plans[tier].usage_plan_id,
                description=f"{tier.capitalize()} tier usage plan ID"
            )

        # API key outputs (values are sensitive and not exposed in outputs)
        for tier in ["premium", "standard", "basic"]:
            CfnOutput(
                self,
                f"{tier.capitalize()}ApiKeyId",
                value=self.api_keys[tier].key_id,
                description=f"{tier.capitalize()} tier API key ID (use AWS CLI to get value)"
            )

        # Usage instructions
        CfnOutput(
            self,
            "UsageInstructions",
            value="Use 'aws apigateway get-api-key --api-key <key-id> --include-value' to retrieve API key values",
            description="Instructions for retrieving API key values"
        )


class ApiThrottlingApp(cdk.App):
    """
    CDK Application for API throttling and rate limiting demonstration.
    """

    def __init__(self):
        super().__init__()

        # Get environment configuration
        env = cdk.Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
        )

        # Create the main stack
        ApiThrottlingStack(
            self,
            "ApiThrottlingStack",
            env=env,
            description="Complete API Gateway throttling and rate limiting implementation with multi-tier customer access controls"
        )


# Application entry point
if __name__ == "__main__":
    app = ApiThrottlingApp()
    app.synth()