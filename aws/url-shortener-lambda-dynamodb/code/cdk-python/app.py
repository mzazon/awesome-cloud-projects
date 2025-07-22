#!/usr/bin/env python3
"""
AWS CDK Python Application for Basic URL Shortener Service

This CDK application deploys a serverless URL shortener service using:
- AWS Lambda for compute
- Amazon DynamoDB for storage
- Amazon API Gateway for HTTP endpoints
- AWS CloudWatch for monitoring

The solution provides a scalable, cost-effective URL shortening service
that automatically handles traffic spikes while maintaining low latency.
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Duration,
    Stack,
    StackProps,
    RemovalPolicy,
    aws_lambda as _lambda,
    aws_dynamodb as dynamodb,
    aws_apigatewayv2 as apigwv2,
    aws_apigatewayv2_integrations as integrations,
    aws_iam as iam,
    aws_logs as logs,
    aws_cloudwatch as cloudwatch,
)
from constructs import Construct


class UrlShortenerStack(Stack):
    """
    CDK Stack for URL Shortener Service
    
    This stack creates all the necessary AWS resources for a serverless
    URL shortener including Lambda functions, DynamoDB table, API Gateway,
    and CloudWatch monitoring.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Create DynamoDB table for URL storage
        self.url_table = self._create_dynamodb_table()
        
        # Create Lambda function for URL operations
        self.lambda_function = self._create_lambda_function()
        
        # Create API Gateway HTTP API
        self.api = self._create_api_gateway()
        
        # Create CloudWatch dashboard
        self.dashboard = self._create_cloudwatch_dashboard()
        
        # Output important values
        self._create_outputs()

    def _create_dynamodb_table(self) -> dynamodb.Table:
        """
        Create DynamoDB table for storing URL mappings
        
        Returns:
            dynamodb.Table: The created DynamoDB table
        """
        table = dynamodb.Table(
            self,
            "UrlTable",
            table_name=f"url-shortener-{self.node.addr}",
            partition_key=dynamodb.Attribute(
                name="short_id",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            removal_policy=RemovalPolicy.DESTROY,  # For development only
            point_in_time_recovery=True,
            encryption=dynamodb.TableEncryption.AWS_MANAGED,
            time_to_live_attribute="ttl",
            tags={
                "Project": "URLShortener",
                "Environment": "Development",
                "Service": "Storage"
            }
        )
        
        return table

    def _create_lambda_function(self) -> _lambda.Function:
        """
        Create Lambda function for URL shortener operations
        
        Returns:
            _lambda.Function: The created Lambda function
        """
        # Create Lambda execution role with specific permissions
        lambda_role = iam.Role(
            self,
            "LambdaExecutionRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
            inline_policies={
                "DynamoDBAccess": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "dynamodb:GetItem",
                                "dynamodb:PutItem",
                                "dynamodb:UpdateItem",
                                "dynamodb:DeleteItem",
                                "dynamodb:Query",
                                "dynamodb:Scan"
                            ],
                            resources=[self.url_table.table_arn]
                        )
                    ]
                )
            }
        )

        # Create Lambda function
        lambda_function = _lambda.Function(
            self,
            "UrlShortenerFunction",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="lambda_function.lambda_handler",
            code=_lambda.Code.from_inline(self._get_lambda_code()),
            timeout=Duration.seconds(30),
            memory_size=256,
            role=lambda_role,
            environment={
                "TABLE_NAME": self.url_table.table_name,
                "LOG_LEVEL": "INFO"
            },
            description="URL Shortener Service Lambda Function",
            log_retention=logs.RetentionDays.ONE_WEEK,
            tracing=_lambda.Tracing.ACTIVE,
            tags={
                "Project": "URLShortener",
                "Environment": "Development",
                "Service": "Compute"
            }
        )

        return lambda_function

    def _create_api_gateway(self) -> apigwv2.HttpApi:
        """
        Create API Gateway HTTP API with Lambda integration
        
        Returns:
            apigwv2.HttpApi: The created HTTP API
        """
        # Create Lambda integration
        lambda_integration = integrations.HttpLambdaIntegration(
            "LambdaIntegration",
            self.lambda_function,
            payload_format_version=apigwv2.PayloadFormatVersion.VERSION_1_0
        )

        # Create HTTP API
        api = apigwv2.HttpApi(
            self,
            "UrlShortenerApi",
            api_name=f"url-shortener-api-{self.node.addr}",
            description="URL Shortener HTTP API",
            cors_preflight=apigwv2.CorsPreflightOptions(
                allow_credentials=False,
                allow_headers=["Content-Type", "X-Amz-Date", "Authorization", 
                              "X-Api-Key", "X-Amz-Security-Token"],
                allow_methods=[apigwv2.CorsHttpMethod.GET, 
                              apigwv2.CorsHttpMethod.POST,
                              apigwv2.CorsHttpMethod.OPTIONS],
                allow_origins=["*"],
                max_age=Duration.days(1)
            ),
            default_integration=lambda_integration
        )

        # Add routes
        api.add_routes(
            path="/shorten",
            methods=[apigwv2.HttpMethod.POST],
            integration=lambda_integration
        )

        api.add_routes(
            path="/{proxy+}",
            methods=[apigwv2.HttpMethod.GET],
            integration=lambda_integration
        )

        return api

    def _create_cloudwatch_dashboard(self) -> cloudwatch.Dashboard:
        """
        Create CloudWatch dashboard for monitoring the URL shortener service
        
        Returns:
            cloudwatch.Dashboard: The created CloudWatch dashboard
        """
        dashboard = cloudwatch.Dashboard(
            self,
            "UrlShortenerDashboard",
            dashboard_name=f"URLShortener-{self.node.addr}",
            widgets=[
                [
                    cloudwatch.GraphWidget(
                        title="Lambda Function Metrics",
                        left=[
                            self.lambda_function.metric_invocations(
                                statistic="Sum"
                            ),
                            self.lambda_function.metric_errors(
                                statistic="Sum"
                            ),
                            self.lambda_function.metric_duration(
                                statistic="Average"
                            )
                        ],
                        period=Duration.minutes(5),
                        width=12,
                        height=6
                    )
                ],
                [
                    cloudwatch.GraphWidget(
                        title="DynamoDB Table Metrics",
                        left=[
                            self.url_table.metric_consumed_read_capacity_units(
                                statistic="Sum"
                            ),
                            self.url_table.metric_consumed_write_capacity_units(
                                statistic="Sum"
                            )
                        ],
                        period=Duration.minutes(5),
                        width=12,
                        height=6
                    )
                ],
                [
                    cloudwatch.GraphWidget(
                        title="API Gateway Metrics",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/ApiGatewayV2",
                                metric_name="Count",
                                dimensions_map={
                                    "ApiId": self.api.api_id
                                },
                                statistic="Sum"
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/ApiGatewayV2",
                                metric_name="4xx",
                                dimensions_map={
                                    "ApiId": self.api.api_id
                                },
                                statistic="Sum"
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/ApiGatewayV2",
                                metric_name="5xx",
                                dimensions_map={
                                    "ApiId": self.api.api_id
                                },
                                statistic="Sum"
                            )
                        ],
                        period=Duration.minutes(5),
                        width=12,
                        height=6
                    )
                ]
            ]
        )

        return dashboard

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource values"""
        cdk.CfnOutput(
            self,
            "ApiUrl",
            value=self.api.api_endpoint,
            description="URL Shortener API Endpoint",
            export_name=f"{self.stack_name}-ApiUrl"
        )

        cdk.CfnOutput(
            self,
            "TableName",
            value=self.url_table.table_name,
            description="DynamoDB Table Name for URL Storage",
            export_name=f"{self.stack_name}-TableName"
        )

        cdk.CfnOutput(
            self,
            "FunctionName",
            value=self.lambda_function.function_name,
            description="Lambda Function Name",
            export_name=f"{self.stack_name}-FunctionName"
        )

        cdk.CfnOutput(
            self,
            "DashboardUrl",
            value=f"https://console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.dashboard.dashboard_name}",
            description="CloudWatch Dashboard URL",
            export_name=f"{self.stack_name}-DashboardUrl"
        )

    def _get_lambda_code(self) -> str:
        """
        Return the Lambda function code as a string
        
        Returns:
            str: Complete Lambda function code
        """
        return '''
import json
import boto3
import base64
import hashlib
import uuid
import logging
import os
from datetime import datetime, timedelta
from urllib.parse import urlparse

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

# Initialize DynamoDB client
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['TABLE_NAME'])

def lambda_handler(event, context):
    """Main Lambda handler for URL shortener operations"""
    
    try:
        # Extract HTTP method and path
        http_method = event['httpMethod']
        path = event['path']
        
        logger.info(f"Processing {http_method} request to {path}")
        
        # Route requests based on method and path
        if http_method == 'POST' and path == '/shorten':
            return create_short_url(event)
        elif http_method == 'GET' and path.startswith('/'):
            return redirect_to_long_url(event)
        else:
            return {
                'statusCode': 404,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'Endpoint not found'})
            }
            
    except Exception as e:
        logger.error(f"Error processing request: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': 'Internal server error'})
        }

def create_short_url(event):
    """Create a new short URL mapping"""
    
    try:
        # Parse request body
        if event.get('isBase64Encoded', False):
            body = base64.b64decode(event['body']).decode('utf-8')
        else:
            body = event['body']
        
        request_data = json.loads(body)
        original_url = request_data.get('url')
        
        if not original_url:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'URL is required'})
            }
        
        # Validate URL format
        parsed_url = urlparse(original_url)
        if not parsed_url.scheme or not parsed_url.netloc:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'Invalid URL format'})
            }
        
        # Generate short ID
        short_id = generate_short_id(original_url)
        
        # Create expiration time (30 days from now)
        expiration_time = datetime.utcnow() + timedelta(days=30)
        ttl = int(expiration_time.timestamp())
        
        # Store in DynamoDB
        table.put_item(
            Item={
                'short_id': short_id,
                'original_url': original_url,
                'created_at': datetime.utcnow().isoformat(),
                'expires_at': expiration_time.isoformat(),
                'ttl': ttl,
                'click_count': 0,
                'is_active': True
            }
        )
        
        logger.info(f"Created short URL: {short_id} -> {original_url}")
        
        # Return success response
        return {
            'statusCode': 201,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'short_id': short_id,
                'short_url': f"https://your-domain.com/{short_id}",
                'original_url': original_url,
                'expires_at': expiration_time.isoformat()
            })
        }
        
    except Exception as e:
        logger.error(f"Error creating short URL: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': 'Could not create short URL'})
        }

def redirect_to_long_url(event):
    """Redirect to original URL using short ID"""
    
    try:
        # Extract short ID from path
        short_id = event['path'][1:]  # Remove leading slash
        
        if not short_id:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'Short ID is required'})
            }
        
        logger.info(f"Looking up short ID: {short_id}")
        
        # Retrieve from DynamoDB
        response = table.get_item(Key={'short_id': short_id})
        
        if 'Item' not in response:
            return {
                'statusCode': 404,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'Short URL not found'})
            }
        
        item = response['Item']
        
        # Check if URL is still active
        if not item.get('is_active', True):
            return {
                'statusCode': 410,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'Short URL has been disabled'})
            }
        
        # Check expiration
        expires_at = datetime.fromisoformat(item['expires_at'])
        if datetime.utcnow() > expires_at:
            return {
                'statusCode': 410,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'Short URL has expired'})
            }
        
        # Increment click count
        table.update_item(
            Key={'short_id': short_id},
            UpdateExpression='SET click_count = click_count + :inc',
            ExpressionAttributeValues={':inc': 1}
        )
        
        logger.info(f"Redirecting {short_id} to {item['original_url']}")
        
        # Return redirect response
        return {
            'statusCode': 302,
            'headers': {
                'Location': item['original_url'],
                'Access-Control-Allow-Origin': '*'
            },
            'body': ''
        }
        
    except Exception as e:
        logger.error(f"Error redirecting URL: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': 'Could not redirect to URL'})
        }

def generate_short_id(url):
    """Generate a short ID from URL using hash"""
    
    # Create a hash of the URL with timestamp for uniqueness
    hash_input = f"{url}{datetime.utcnow().isoformat()}{uuid.uuid4().hex[:8]}"
    hash_object = hashlib.sha256(hash_input.encode())
    hash_hex = hash_object.hexdigest()
    
    # Convert to base62 for URL-safe short ID
    short_id = base62_encode(int(hash_hex[:16], 16))[:8]
    
    return short_id

def base62_encode(num):
    """Encode number to base62 string"""
    
    alphabet = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
    if num == 0:
        return alphabet[0]
    
    result = []
    while num:
        result.append(alphabet[num % 62])
        num //= 62
    
    return ''.join(reversed(result))
'''


class UrlShortenerApp(cdk.App):
    """CDK Application for URL Shortener Service"""

    def __init__(self) -> None:
        super().__init__()

        # Create the main stack
        UrlShortenerStack(
            self,
            "UrlShortenerStack",
            description="Basic URL Shortener Service with Lambda and DynamoDB",
            tags={
                "Project": "URLShortener",
                "Environment": "Development",
                "Owner": "CDK",
                "Recipe": "basic-url-shortener-service-lambda-dynamodb"
            }
        )


# Create and run the application
app = UrlShortenerApp()
app.synth()