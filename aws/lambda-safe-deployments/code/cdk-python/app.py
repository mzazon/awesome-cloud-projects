#!/usr/bin/env python3
"""
CDK Python application for Lambda Function Deployment Patterns with Blue-Green and Canary Releases.

This application demonstrates advanced Lambda deployment patterns using function versions,
aliases, and weighted traffic routing combined with API Gateway integration.
"""

import json
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    CfnOutput,
    aws_lambda as lambda_,
    aws_apigateway as apigateway,
    aws_iam as iam,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
)
from constructs import Construct


class LambdaDeploymentPatternsStack(Stack):
    """
    CDK Stack for implementing Lambda deployment patterns with blue-green and canary releases.
    
    This stack creates:
    - Lambda function with multiple versions
    - Production alias with weighted routing
    - API Gateway integration with Lambda proxy
    - CloudWatch monitoring and alarms
    - IAM roles with least privilege access
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs: Any) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Create Lambda execution role with CloudWatch Logs permissions
        self.lambda_role = self._create_lambda_execution_role()

        # Create Lambda function with initial version
        self.lambda_function = self._create_lambda_function()

        # Create function versions for blue-green deployment
        self.version_1 = self._create_function_version_1()
        self.version_2 = self._create_function_version_2()

        # Create production alias with weighted routing
        self.production_alias = self._create_production_alias()

        # Create API Gateway with Lambda integration
        self.api_gateway = self._create_api_gateway()

        # Create CloudWatch monitoring
        self._create_cloudwatch_monitoring()

        # Create stack outputs
        self._create_outputs()

    def _create_lambda_execution_role(self) -> iam.Role:
        """
        Create IAM role for Lambda function execution with CloudWatch Logs permissions.
        
        Returns:
            iam.Role: Lambda execution role with appropriate permissions
        """
        return iam.Role(
            self,
            "LambdaExecutionRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
            description="Execution role for Lambda deployment patterns demo function",
        )

    def _create_lambda_function(self) -> lambda_.Function:
        """
        Create Lambda function with initial code (Version 1).
        
        Returns:
            lambda_.Function: Lambda function with blue environment code
        """
        # Initial function code (Version 1 - Blue Environment)
        initial_code = '''
import json
import os

def lambda_handler(event, context):
    """Lambda handler for Version 1 - Blue Environment."""
    version = "1.0.0"
    message = "Hello from Lambda Version 1 - Blue Environment"
    
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps({
            'version': version,
            'message': message,
            'timestamp': context.aws_request_id,
            'environment': 'blue'
        })
    }
'''

        return lambda_.Function(
            self,
            "DeploymentPatternsFunction",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            role=self.lambda_role,
            code=lambda_.Code.from_inline(initial_code),
            description="Demo function for Lambda deployment patterns",
            timeout=Duration.seconds(30),
            memory_size=256,
            log_retention=logs.RetentionDays.ONE_WEEK,
            environment={
                "DEPLOYMENT_PATTERN": "blue-green-canary",
                "ENVIRONMENT": "production"
            },
        )

    def _create_function_version_1(self) -> lambda_.Version:
        """
        Create Version 1 of the Lambda function (Blue Environment).
        
        Returns:
            lambda_.Version: Immutable version 1 of the function
        """
        return lambda_.Version(
            self,
            "Version1",
            lambda_=self.lambda_function,
            description="Version 1 - Blue Environment (Initial Production)",
        )

    def _create_function_version_2(self) -> lambda_.Version:
        """
        Create Version 2 of the Lambda function (Green Environment).
        
        Returns:
            lambda_.Version: Immutable version 2 of the function
        """
        # Update function code for Version 2 (Green Environment)
        version_2_code = '''
import json
import os

def lambda_handler(event, context):
    """Lambda handler for Version 2 - Green Environment with new features."""
    version = "2.0.0"
    message = "Hello from Lambda Version 2 - Green Environment with NEW FEATURES!"
    
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps({
            'version': version,
            'message': message,
            'timestamp': context.aws_request_id,
            'environment': 'green',
            'features': ['enhanced_logging', 'improved_performance']
        })
    }
'''

        # Create a new function with Version 2 code
        version_2_function = lambda_.Function(
            self,
            "DeploymentPatternsFunctionV2",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            role=self.lambda_role,
            code=lambda_.Code.from_inline(version_2_code),
            description="Version 2 - Green Environment with enhanced features",
            timeout=Duration.seconds(30),
            memory_size=256,
            log_retention=logs.RetentionDays.ONE_WEEK,
            environment={
                "DEPLOYMENT_PATTERN": "blue-green-canary",
                "ENVIRONMENT": "production",
                "VERSION": "2.0.0"
            },
        )

        return lambda_.Version(
            self,
            "Version2",
            lambda_=version_2_function,
            description="Version 2 - Green Environment with new features",
        )

    def _create_production_alias(self) -> lambda_.Alias:
        """
        Create production alias with weighted routing for blue-green deployments.
        
        Returns:
            lambda_.Alias: Production alias with configurable traffic routing
        """
        return lambda_.Alias(
            self,
            "ProductionAlias",
            alias_name="production",
            version=self.version_2,
            description="Production alias for blue-green deployments",
            # Configure weighted routing for canary deployment
            # 90% traffic to version 1, 10% to version 2 (canary)
            additional_versions=[
                lambda_.VersionWeight(
                    version=self.version_1,
                    weight=0.9
                )
            ],
        )

    def _create_api_gateway(self) -> apigateway.RestApi:
        """
        Create API Gateway with Lambda integration using production alias.
        
        Returns:
            apigateway.RestApi: REST API integrated with Lambda alias
        """
        # Create REST API
        api = apigateway.RestApi(
            self,
            "DeploymentPatternsApi",
            rest_api_name="Lambda Deployment Patterns API",
            description="API Gateway for Lambda deployment patterns demo",
            default_cors_preflight_options=apigateway.CorsOptions(
                allow_origins=apigateway.Cors.ALL_ORIGINS,
                allow_methods=apigateway.Cors.ALL_METHODS,
                allow_headers=["Content-Type", "X-Amz-Date", "Authorization", "X-Api-Key"],
            ),
        )

        # Create /demo resource
        demo_resource = api.root.add_resource("demo")

        # Create Lambda integration using production alias
        lambda_integration = apigateway.LambdaIntegration(
            self.production_alias,
            proxy=True,
            integration_responses=[
                apigateway.IntegrationResponse(
                    status_code="200",
                )
            ],
        )

        # Add GET method to /demo resource
        demo_resource.add_method(
            "GET",
            lambda_integration,
            method_responses=[
                apigateway.MethodResponse(
                    status_code="200",
                    response_models={
                        "application/json": apigateway.Model.EMPTY_MODEL
                    },
                )
            ],
        )

        # Grant API Gateway permission to invoke Lambda function
        self.production_alias.grant_invoke(
            iam.ServicePrincipal("apigateway.amazonaws.com")
        )

        return api

    def _create_cloudwatch_monitoring(self) -> None:
        """
        Create CloudWatch alarms for monitoring Lambda function performance.
        
        Sets up monitoring for:
        - Function error rate
        - Function duration
        - Function invocations
        """
        # Create alarm for Lambda function error rate
        error_alarm = cloudwatch.Alarm(
            self,
            "LambdaErrorRateAlarm",
            metric=self.lambda_function.metric_errors(
                period=Duration.minutes(5),
                statistic="Sum",
            ),
            threshold=5,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            alarm_description="Lambda function error rate exceeds threshold",
            alarm_name=f"{self.lambda_function.function_name}-error-rate",
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

        # Create alarm for Lambda function duration
        duration_alarm = cloudwatch.Alarm(
            self,
            "LambdaDurationAlarm",
            metric=self.lambda_function.metric_duration(
                period=Duration.minutes(5),
                statistic="Average",
            ),
            threshold=10000,  # 10 seconds
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            alarm_description="Lambda function duration exceeds threshold",
            alarm_name=f"{self.lambda_function.function_name}-duration",
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

        # Create custom metric for deployment monitoring
        deployment_metric = cloudwatch.Metric(
            namespace="AWS/Lambda",
            metric_name="Invocations",
            dimensions_map={
                "FunctionName": self.lambda_function.function_name,
            },
            period=Duration.minutes(5),
            statistic="Sum",
        )

        # Store alarms as instance variables for potential use in outputs
        self.error_alarm = error_alarm
        self.duration_alarm = duration_alarm

    def _create_outputs(self) -> None:
        """
        Create CloudFormation outputs for key resources and endpoints.
        """
        # API Gateway endpoint URL
        CfnOutput(
            self,
            "ApiGatewayUrl",
            value=f"{self.api_gateway.url}demo",
            description="API Gateway endpoint URL for testing deployments",
            export_name=f"{self.stack_name}-ApiUrl",
        )

        # Lambda function name
        CfnOutput(
            self,
            "LambdaFunctionName",
            value=self.lambda_function.function_name,
            description="Lambda function name for CLI operations",
            export_name=f"{self.stack_name}-FunctionName",
        )

        # Lambda function ARN
        CfnOutput(
            self,
            "LambdaFunctionArn",
            value=self.lambda_function.function_arn,
            description="Lambda function ARN",
            export_name=f"{self.stack_name}-FunctionArn",
        )

        # Production alias ARN
        CfnOutput(
            self,
            "ProductionAliasArn",
            value=self.production_alias.function_arn,
            description="Production alias ARN for deployment operations",
            export_name=f"{self.stack_name}-AliasArn",
        )

        # API Gateway REST API ID
        CfnOutput(
            self,
            "ApiGatewayId",
            value=self.api_gateway.rest_api_id,
            description="API Gateway REST API ID",
            export_name=f"{self.stack_name}-ApiId",
        )

        # Version 1 ARN
        CfnOutput(
            self,
            "Version1Arn",
            value=self.version_1.function_arn,
            description="Version 1 ARN (Blue Environment)",
            export_name=f"{self.stack_name}-Version1Arn",
        )

        # Version 2 ARN
        CfnOutput(
            self,
            "Version2Arn",
            value=self.version_2.function_arn,
            description="Version 2 ARN (Green Environment)",
            export_name=f"{self.stack_name}-Version2Arn",
        )

        # CloudWatch alarm names
        CfnOutput(
            self,
            "ErrorAlarmName",
            value=self.error_alarm.alarm_name,
            description="CloudWatch alarm name for error monitoring",
            export_name=f"{self.stack_name}-ErrorAlarm",
        )

        CfnOutput(
            self,
            "DurationAlarmName",
            value=self.duration_alarm.alarm_name,
            description="CloudWatch alarm name for duration monitoring",
            export_name=f"{self.stack_name}-DurationAlarm",
        )


class LambdaDeploymentPatternsApp(cdk.App):
    """
    CDK Application for Lambda deployment patterns demonstration.
    
    This application creates a complete stack demonstrating:
    - Blue-green deployment patterns
    - Canary deployment strategies
    - API Gateway integration
    - CloudWatch monitoring
    """

    def __init__(self) -> None:
        super().__init__()

        # Create the main stack
        LambdaDeploymentPatternsStack(
            self,
            "LambdaDeploymentPatternsStack",
            description="Lambda Function Deployment Patterns with Blue-Green and Canary Releases",
            env=cdk.Environment(
                account=self.node.try_get_context("account"),
                region=self.node.try_get_context("region"),
            ),
        )


def main() -> None:
    """
    Main entry point for the CDK application.
    """
    app = LambdaDeploymentPatternsApp()
    app.synth()


if __name__ == "__main__":
    main()