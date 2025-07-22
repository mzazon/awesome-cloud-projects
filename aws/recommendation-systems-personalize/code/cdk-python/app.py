#!/usr/bin/env python3
"""
CDK Python application for Real-time Recommendation Systems
using Amazon Personalize and API Gateway.

This application creates a complete serverless recommendation system
that can serve personalized recommendations via REST API.
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_apigateway as apigw,
    aws_lambda as _lambda,
    aws_iam as iam,
    aws_s3 as s3,
    aws_logs as logs,
    aws_cloudwatch as cloudwatch,
    CfnOutput,
    Duration,
    RemovalPolicy,
)
from constructs import Construct
from typing import Dict, Any
import json


class RecommendationSystemStack(Stack):
    """
    CDK Stack for deploying a real-time recommendation system using
    Amazon Personalize and API Gateway.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        unique_suffix = self.node.try_get_context("unique_suffix") or "demo"
        
        # Create S3 bucket for training data
        self.training_data_bucket = self._create_training_data_bucket(unique_suffix)
        
        # Create IAM role for Personalize
        self.personalize_role = self._create_personalize_role(unique_suffix)
        
        # Create Lambda function for recommendation API
        self.recommendation_lambda = self._create_recommendation_lambda(unique_suffix)
        
        # Create API Gateway
        self.api = self._create_api_gateway(unique_suffix)
        
        # Create CloudWatch dashboard
        self._create_monitoring_dashboard(unique_suffix)
        
        # Create outputs
        self._create_outputs()

    def _create_training_data_bucket(self, suffix: str) -> s3.Bucket:
        """Create S3 bucket for storing training data."""
        bucket = s3.Bucket(
            self,
            "TrainingDataBucket",
            bucket_name=f"personalize-training-data-{suffix}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )
        
        # Add bucket policy for Personalize access
        bucket.add_to_resource_policy(
            iam.PolicyStatement(
                sid="AllowPersonalizeAccess",
                effect=iam.Effect.ALLOW,
                principals=[iam.ServicePrincipal("personalize.amazonaws.com")],
                actions=[
                    "s3:GetObject",
                    "s3:ListBucket",
                ],
                resources=[
                    bucket.bucket_arn,
                    f"{bucket.bucket_arn}/*",
                ],
            )
        )
        
        return bucket

    def _create_personalize_role(self, suffix: str) -> iam.Role:
        """Create IAM role for Amazon Personalize service."""
        role = iam.Role(
            self,
            "PersonalizeExecutionRole",
            role_name=f"PersonalizeExecutionRole-{suffix}",
            assumed_by=iam.ServicePrincipal("personalize.amazonaws.com"),
            description="IAM role for Amazon Personalize to access S3 training data",
        )
        
        # Add policy for S3 access
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:ListBucket",
                ],
                resources=[
                    self.training_data_bucket.bucket_arn,
                    f"{self.training_data_bucket.bucket_arn}/*",
                ],
            )
        )
        
        return role

    def _create_recommendation_lambda(self, suffix: str) -> _lambda.Function:
        """Create Lambda function for handling recommendation requests."""
        
        # Create Lambda execution role
        lambda_role = iam.Role(
            self,
            "RecommendationLambdaRole",
            role_name=f"RecommendationLambdaRole-{suffix}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole"),
            ],
        )
        
        # Add Personalize permissions
        lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "personalize:GetRecommendations",
                    "personalize:DescribeCampaign",
                ],
                resources=["*"],  # Will be restricted to specific campaign ARN in production
            )
        )
        
        # Create Lambda function
        lambda_function = _lambda.Function(
            self,
            "RecommendationLambda",
            function_name=f"recommendation-api-{suffix}",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            role=lambda_role,
            code=_lambda.Code.from_inline(self._get_lambda_code()),
            timeout=Duration.seconds(30),
            memory_size=256,
            environment={
                "CAMPAIGN_ARN": "PLACEHOLDER_CAMPAIGN_ARN",  # To be updated after Personalize deployment
                "LOG_LEVEL": "INFO",
            },
            log_retention=logs.RetentionDays.ONE_WEEK,
        )
        
        return lambda_function

    def _get_lambda_code(self) -> str:
        """Get the Lambda function code as a string."""
        return """
import json
import boto3
import os
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

# Initialize Personalize client
personalize = boto3.client('personalize-runtime')

def lambda_handler(event, context):
    \"\"\"
    Lambda handler for processing recommendation requests.
    
    Args:
        event: API Gateway Lambda Proxy Input Format
        context: Lambda context object
        
    Returns:
        API Gateway Lambda Proxy Output Format
    \"\"\"
    
    try:
        # Extract user ID from path parameters
        path_params = event.get('pathParameters', {})
        if not path_params or 'userId' not in path_params:
            return create_error_response(400, 'Missing userId in path parameters')
            
        user_id = path_params['userId']
        
        # Get query parameters
        query_params = event.get('queryStringParameters') or {}
        num_results = int(query_params.get('numResults', 10))
        
        # Validate num_results
        if num_results < 1 or num_results > 100:
            return create_error_response(400, 'numResults must be between 1 and 100')
        
        # Get campaign ARN from environment
        campaign_arn = os.environ.get('CAMPAIGN_ARN')
        if not campaign_arn or campaign_arn == 'PLACEHOLDER_CAMPAIGN_ARN':
            return create_error_response(500, 'Campaign ARN not configured')
        
        logger.info(f"Getting recommendations for user: {user_id}, numResults: {num_results}")
        
        # Get recommendations from Personalize
        response = personalize.get_recommendations(
            campaignArn=campaign_arn,
            userId=user_id,
            numResults=num_results
        )
        
        # Format response
        recommendations = []
        for item in response['itemList']:
            recommendations.append({
                'itemId': item['itemId'],
                'score': round(item['score'], 4)
            })
        
        # Create successful response
        response_body = {
            'userId': user_id,
            'recommendations': recommendations,
            'numResults': len(recommendations),
            'requestId': response['ResponseMetadata']['RequestId'],
            'timestamp': context.aws_request_id
        }
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'GET,OPTIONS',
                'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'
            },
            'body': json.dumps(response_body)
        }
        
    except personalize.exceptions.ResourceNotFoundException as e:
        logger.error(f"Personalize resource not found: {str(e)}")
        return create_error_response(404, 'User not found in recommendation system')
        
    except personalize.exceptions.InvalidInputException as e:
        logger.error(f"Invalid input to Personalize: {str(e)}")
        return create_error_response(400, 'Invalid user ID format')
        
    except Exception as e:
        logger.error(f"Unexpected error getting recommendations: {str(e)}")
        return create_error_response(500, 'Internal server error')

def create_error_response(status_code: int, message: str) -> dict:
    \"\"\"Create standardized error response.\"\"\"
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET,OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'
        },
        'body': json.dumps({
            'error': {
                'message': message,
                'statusCode': status_code
            }
        })
    }
"""

    def _create_api_gateway(self, suffix: str) -> apigw.RestApi:
        """Create API Gateway for the recommendation service."""
        
        # Create REST API
        api = apigw.RestApi(
            self,
            "RecommendationAPI",
            rest_api_name=f"recommendation-api-{suffix}",
            description="Real-time recommendation API using Amazon Personalize",
            default_cors_preflight_options=apigw.CorsOptions(
                allow_origins=apigw.Cors.ALL_ORIGINS,
                allow_methods=apigw.Cors.ALL_METHODS,
                allow_headers=["Content-Type", "X-Amz-Date", "Authorization", "X-Api-Key", "X-Amz-Security-Token"],
            ),
            endpoint_configuration=apigw.EndpointConfiguration(
                types=[apigw.EndpointType.REGIONAL]
            ),
        )
        
        # Create Lambda integration
        lambda_integration = apigw.LambdaIntegration(
            self.recommendation_lambda,
            proxy=True,
            integration_responses=[
                apigw.IntegrationResponse(
                    status_code="200",
                    response_headers={
                        "Access-Control-Allow-Origin": "'*'",
                        "Access-Control-Allow-Methods": "'GET,OPTIONS'",
                    },
                )
            ],
        )
        
        # Create API resources and methods
        recommendations_resource = api.root.add_resource("recommendations")
        user_resource = recommendations_resource.add_resource("{userId}")
        
        # Add GET method for recommendations
        user_resource.add_method(
            "GET",
            lambda_integration,
            method_responses=[
                apigw.MethodResponse(
                    status_code="200",
                    response_headers={
                        "Access-Control-Allow-Origin": True,
                        "Access-Control-Allow-Methods": True,
                        "Content-Type": True,
                    },
                )
            ],
            request_parameters={
                "method.request.path.userId": True,
                "method.request.querystring.numResults": False,
            },
        )
        
        # Add OPTIONS method for CORS
        user_resource.add_method(
            "OPTIONS",
            apigw.MockIntegration(
                integration_responses=[
                    apigw.IntegrationResponse(
                        status_code="200",
                        response_headers={
                            "Access-Control-Allow-Origin": "'*'",
                            "Access-Control-Allow-Methods": "'GET,OPTIONS'",
                            "Access-Control-Allow-Headers": "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
                        },
                    )
                ],
                request_templates={"application/json": '{"statusCode": 200}'},
            ),
            method_responses=[
                apigw.MethodResponse(
                    status_code="200",
                    response_headers={
                        "Access-Control-Allow-Origin": True,
                        "Access-Control-Allow-Methods": True,
                        "Access-Control-Allow-Headers": True,
                    },
                )
            ],
        )
        
        return api

    def _create_monitoring_dashboard(self, suffix: str) -> None:
        """Create CloudWatch dashboard for monitoring."""
        
        # Create CloudWatch dashboard
        dashboard = cloudwatch.Dashboard(
            self,
            "RecommendationSystemDashboard",
            dashboard_name=f"RecommendationSystem-{suffix}",
        )
        
        # Add API Gateway metrics
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="API Gateway Requests",
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/ApiGateway",
                        metric_name="Count",
                        dimensions_map={
                            "ApiName": self.api.rest_api_name,
                        },
                        statistic="Sum",
                    )
                ],
                width=12,
            ),
            cloudwatch.GraphWidget(
                title="API Gateway Latency",
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/ApiGateway",
                        metric_name="Latency",
                        dimensions_map={
                            "ApiName": self.api.rest_api_name,
                        },
                        statistic="Average",
                    )
                ],
                width=12,
            ),
        )
        
        # Add Lambda metrics
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Lambda Function Metrics",
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/Lambda",
                        metric_name="Invocations",
                        dimensions_map={
                            "FunctionName": self.recommendation_lambda.function_name,
                        },
                        statistic="Sum",
                    )
                ],
                right=[
                    cloudwatch.Metric(
                        namespace="AWS/Lambda",
                        metric_name="Errors",
                        dimensions_map={
                            "FunctionName": self.recommendation_lambda.function_name,
                        },
                        statistic="Sum",
                    )
                ],
                width=12,
            ),
            cloudwatch.GraphWidget(
                title="Lambda Duration",
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/Lambda",
                        metric_name="Duration",
                        dimensions_map={
                            "FunctionName": self.recommendation_lambda.function_name,
                        },
                        statistic="Average",
                    )
                ],
                width=12,
            ),
        )
        
        # Create alarms
        cloudwatch.Alarm(
            self,
            "APIGateway4xxErrorAlarm",
            alarm_name=f"RecommendationAPI-4xxErrors-{suffix}",
            alarm_description="Monitor 4xx errors in recommendation API",
            metric=cloudwatch.Metric(
                namespace="AWS/ApiGateway",
                metric_name="4XXError",
                dimensions_map={
                    "ApiName": self.api.rest_api_name,
                },
                statistic="Sum",
            ),
            threshold=5,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        )
        
        cloudwatch.Alarm(
            self,
            "LambdaErrorAlarm",
            alarm_name=f"RecommendationLambda-Errors-{suffix}",
            alarm_description="Monitor Lambda function errors",
            metric=cloudwatch.Metric(
                namespace="AWS/Lambda",
                metric_name="Errors",
                dimensions_map={
                    "FunctionName": self.recommendation_lambda.function_name,
                },
                statistic="Sum",
            ),
            threshold=3,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs."""
        
        CfnOutput(
            self,
            "TrainingDataBucketName",
            value=self.training_data_bucket.bucket_name,
            description="S3 bucket name for training data",
        )
        
        CfnOutput(
            self,
            "PersonalizeRoleArn",
            value=self.personalize_role.role_arn,
            description="IAM role ARN for Amazon Personalize",
        )
        
        CfnOutput(
            self,
            "RecommendationLambdaArn",
            value=self.recommendation_lambda.function_arn,
            description="Lambda function ARN for recommendation API",
        )
        
        CfnOutput(
            self,
            "APIGatewayURL",
            value=self.api.url,
            description="API Gateway endpoint URL",
        )
        
        CfnOutput(
            self,
            "RecommendationEndpoint",
            value=f"{self.api.url}recommendations/{{userId}}",
            description="Complete recommendation endpoint URL template",
        )
        
        CfnOutput(
            self,
            "SampleTestCommand",
            value=f"curl -X GET \"{self.api.url}recommendations/user1?numResults=5\"",
            description="Sample curl command to test the API",
        )


# CDK App
app = cdk.App()

# Get configuration from context
config = {
    "unique_suffix": app.node.try_get_context("unique_suffix") or "demo",
    "environment": app.node.try_get_context("environment") or "dev",
}

# Create stack
stack = RecommendationSystemStack(
    app,
    f"RecommendationSystem-{config['environment']}",
    description=f"Real-time recommendation system using Amazon Personalize and API Gateway ({config['environment']})",
    env=cdk.Environment(
        account=app.node.try_get_context("account"),
        region=app.node.try_get_context("region"),
    ),
)

# Add tags
cdk.Tags.of(stack).add("Project", "RecommendationSystem")
cdk.Tags.of(stack).add("Environment", config["environment"])
cdk.Tags.of(stack).add("ManagedBy", "CDK")

app.synth()