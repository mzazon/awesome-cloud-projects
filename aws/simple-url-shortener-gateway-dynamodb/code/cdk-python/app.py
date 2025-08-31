#!/usr/bin/env python3
"""
AWS CDK Python Application for Simple URL Shortener

This CDK application creates a serverless URL shortening service using:
- AWS API Gateway (REST API)
- AWS Lambda Functions (URL creation and redirection)
- Amazon DynamoDB (URL storage)

The application follows AWS Well-Architected Framework principles for
serverless applications with automatic scaling and cost optimization.
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    CfnOutput,
    RemovalPolicy,
    Duration,
    Tags
)
from aws_cdk import aws_lambda as _lambda
from aws_cdk import aws_dynamodb as dynamodb
from aws_cdk import aws_apigateway as apigateway
from aws_cdk import aws_iam as iam
from aws_cdk import aws_logs as logs
from constructs import Construct


class UrlShortenerStack(Stack):
    """
    CDK Stack for the URL Shortener application.
    
    Creates all necessary infrastructure including DynamoDB table,
    Lambda functions, IAM roles, and API Gateway configuration.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Add tags to all resources in this stack
        Tags.of(self).add("Project", "URLShortener")
        Tags.of(self).add("Environment", "Development")
        Tags.of(self).add("ManagedBy", "CDK")

        # Create DynamoDB table for URL storage
        self.url_table = self._create_dynamodb_table()

        # Create Lambda execution role
        self.lambda_role = self._create_lambda_role()

        # Create Lambda functions
        self.create_function = self._create_url_creation_function()
        self.redirect_function = self._create_url_redirect_function()

        # Create API Gateway
        self.api = self._create_api_gateway()

        # Configure API Gateway resources and methods
        self._configure_api_resources()

        # Create outputs
        self._create_outputs()

    def _create_dynamodb_table(self) -> dynamodb.Table:
        """
        Create DynamoDB table for storing URL mappings.
        
        Uses on-demand billing mode for automatic scaling and cost optimization.
        The table uses shortCode as the partition key for fast lookups.
        
        Returns:
            dynamodb.Table: The created DynamoDB table
        """
        table = dynamodb.Table(
            self, "UrlMappingsTable",
            table_name="url-shortener-mappings",
            partition_key=dynamodb.Attribute(
                name="shortCode",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            removal_policy=RemovalPolicy.DESTROY,  # For development - use RETAIN in production
            point_in_time_recovery=True,  # Enable point-in-time recovery for data protection
            deletion_protection=False  # Set to True in production
        )

        # Add a GSI for potential future enhancements (e.g., lookup by original URL)
        # This is commented out to keep the beginner recipe simple
        # table.add_global_secondary_index(
        #     partition_key=dynamodb.Attribute(
        #         name="originalUrl",
        #         type=dynamodb.AttributeType.STRING
        #     ),
        #     index_name="OriginalUrlIndex"
        # )

        return table

    def _create_lambda_role(self) -> iam.Role:
        """
        Create IAM role for Lambda functions with least privilege permissions.
        
        The role includes basic Lambda execution permissions and specific
        DynamoDB permissions for the URL shortener table.
        
        Returns:
            iam.Role: The created IAM role
        """
        role = iam.Role(
            self, "UrlShortenerLambdaRole",
            role_name="url-shortener-lambda-role",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Execution role for URL Shortener Lambda functions",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ]
        )

        # Add DynamoDB permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "dynamodb:GetItem",
                    "dynamodb:PutItem"
                ],
                resources=[self.url_table.table_arn]
            )
        )

        return role

    def _create_url_creation_function(self) -> _lambda.Function:
        """
        Create Lambda function for URL creation.
        
        This function handles POST requests to create new short URLs.
        It includes comprehensive error handling, URL validation, and CORS support.
        
        Returns:
            _lambda.Function: The created Lambda function
        """
        # Create log group with retention policy
        log_group = logs.LogGroup(
            self, "CreateFunctionLogGroup",
            log_group_name="/aws/lambda/url-shortener-create",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY
        )

        function = _lambda.Function(
            self, "UrlCreateFunction",
            function_name="url-shortener-create",
            runtime=_lambda.Runtime.PYTHON_3_12,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline(self._get_create_function_code()),
            role=self.lambda_role,
            environment={
                "TABLE_NAME": self.url_table.table_name,
                "POWERTOOLS_SERVICE_NAME": "url-shortener-create",
                "LOG_LEVEL": "INFO"
            },
            timeout=Duration.seconds(10),
            memory_size=256,
            description="Creates short URLs and stores mappings in DynamoDB",
            log_group=log_group,
            # Enable tracing for observability
            tracing=_lambda.Tracing.ACTIVE
        )

        return function

    def _create_url_redirect_function(self) -> _lambda.Function:
        """
        Create Lambda function for URL redirection.
        
        This function handles GET requests to redirect users to original URLs.
        It includes error handling for invalid/expired codes and comprehensive logging.
        
        Returns:
            _lambda.Function: The created Lambda function
        """
        # Create log group with retention policy
        log_group = logs.LogGroup(
            self, "RedirectFunctionLogGroup",
            log_group_name="/aws/lambda/url-shortener-redirect",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY
        )

        function = _lambda.Function(
            self, "UrlRedirectFunction",
            function_name="url-shortener-redirect",
            runtime=_lambda.Runtime.PYTHON_3_12,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline(self._get_redirect_function_code()),
            role=self.lambda_role,
            environment={
                "TABLE_NAME": self.url_table.table_name,
                "POWERTOOLS_SERVICE_NAME": "url-shortener-redirect",
                "LOG_LEVEL": "INFO"
            },
            timeout=Duration.seconds(10),
            memory_size=256,
            description="Redirects short URLs to original URLs using DynamoDB lookups",
            log_group=log_group,
            # Enable tracing for observability
            tracing=_lambda.Tracing.ACTIVE
        )

        return function

    def _create_api_gateway(self) -> apigateway.RestApi:
        """
        Create API Gateway REST API.
        
        Configures the API with CORS support, request validation,
        and proper error handling for production use.
        
        Returns:
            apigateway.RestApi: The created REST API
        """
        # Create log group for API Gateway access logs
        api_log_group = logs.LogGroup(
            self, "ApiGatewayLogGroup",
            log_group_name="/aws/apigateway/url-shortener-api",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY
        )

        api = apigateway.RestApi(
            self, "UrlShortenerApi",
            rest_api_name="url-shortener-api",
            description="Serverless URL Shortener REST API",
            endpoint_configuration=apigateway.EndpointConfiguration(
                types=[apigateway.EndpointType.REGIONAL]
            ),
            deploy_options=apigateway.StageOptions(
                stage_name="prod",
                throttling_rate_limit=100,  # requests per second
                throttling_burst_limit=200,  # burst capacity
                logging_level=apigateway.MethodLoggingLevel.INFO,
                access_log_destination=apigateway.LogGroupLogDestination(api_log_group),
                access_log_format=apigateway.AccessLogFormat.json_with_standard_fields(),
                tracing_enabled=True  # Enable X-Ray tracing
            ),
            # Enable CORS for all resources
            default_cors_preflight_options=apigateway.CorsOptions(
                allow_origins=apigateway.Cors.ALL_ORIGINS,
                allow_methods=apigateway.Cors.ALL_METHODS,
                allow_headers=["Content-Type", "X-Amz-Date", "Authorization", "X-Api-Key", "X-Amz-Security-Token"]
            ),
            # Default method options
            default_method_options=apigateway.MethodOptions(
                throttling=apigateway.ThrottleSettings(
                    rate_limit=50,
                    burst_limit=100
                )
            )
        )

        return api

    def _configure_api_resources(self) -> None:
        """
        Configure API Gateway resources and methods.
        
        Creates the /shorten endpoint for URL creation and the /{shortCode}
        endpoint for URL redirection with proper integrations.
        """
        # Create /shorten resource for URL creation
        shorten_resource = self.api.root.add_resource("shorten")
        
        # Create Lambda integration for URL creation
        create_integration = apigateway.LambdaIntegration(
            self.create_function,
            proxy=True,
            allow_test_invoke=False,
            # Configure integration for better error handling
            integration_responses=[
                apigateway.IntegrationResponse(
                    status_code="200",
                    response_parameters={
                        "method.response.header.Access-Control-Allow-Origin": "'*'"
                    }
                )
            ]
        )

        # Add POST method to /shorten
        shorten_resource.add_method(
            "POST",
            create_integration,
            method_responses=[
                apigateway.MethodResponse(
                    status_code="200",
                    response_parameters={
                        "method.response.header.Access-Control-Allow-Origin": False
                    },
                    response_models={
                        "application/json": apigateway.Model.EMPTY_MODEL
                    }
                ),
                apigateway.MethodResponse(
                    status_code="400",
                    response_parameters={
                        "method.response.header.Access-Control-Allow-Origin": False
                    }
                ),
                apigateway.MethodResponse(
                    status_code="500",
                    response_parameters={
                        "method.response.header.Access-Control-Allow-Origin": False
                    }
                )
            ]
        )

        # Create {shortCode} resource for URL redirection
        shortcode_resource = self.api.root.add_resource("{shortCode}")

        # Create Lambda integration for URL redirection
        redirect_integration = apigateway.LambdaIntegration(
            self.redirect_function,
            proxy=True,
            allow_test_invoke=False
        )

        # Add GET method to /{shortCode}
        shortcode_resource.add_method(
            "GET",
            redirect_integration,
            request_parameters={
                "method.request.path.shortCode": True
            },
            method_responses=[
                apigateway.MethodResponse(status_code="302"),
                apigateway.MethodResponse(status_code="404"),
                apigateway.MethodResponse(status_code="400"),
                apigateway.MethodResponse(status_code="500")
            ]
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource values."""
        CfnOutput(
            self, "ApiUrl",
            value=self.api.url,
            description="URL of the API Gateway endpoint",
            export_name="UrlShortenerApiUrl"
        )

        CfnOutput(
            self, "ApiId",
            value=self.api.rest_api_id,
            description="ID of the API Gateway REST API",
            export_name="UrlShortenerApiId"
        )

        CfnOutput(
            self, "DynamoDBTableName",
            value=self.url_table.table_name,
            description="Name of the DynamoDB table storing URL mappings",
            export_name="UrlShortenerTableName"
        )

        CfnOutput(
            self, "CreateFunctionName",
            value=self.create_function.function_name,
            description="Name of the Lambda function that creates short URLs",
            export_name="UrlShortenerCreateFunctionName"
        )

        CfnOutput(
            self, "RedirectFunctionName",
            value=self.redirect_function.function_name,
            description="Name of the Lambda function that handles redirects",
            export_name="UrlShortenerRedirectFunctionName"
        )

        # Output example usage
        CfnOutput(
            self, "ExampleCreateUrl",
            value=f"curl -X POST {self.api.url}shorten -H 'Content-Type: application/json' -d '{{\"url\": \"https://example.com\"}}'",
            description="Example command to create a short URL",
            export_name="UrlShortenerExampleCreateCommand"
        )

    def _get_create_function_code(self) -> str:
        """
        Get the Python code for the URL creation Lambda function.
        
        Returns:
            str: The Lambda function code as a string
        """
        return """
import json
import boto3
import string
import random
import os
import logging
from urllib.parse import urlparse
from botocore.exceptions import ClientError

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

# Initialize DynamoDB resource
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['TABLE_NAME'])

def lambda_handler(event, context):
    \"\"\"
    Lambda handler for creating short URLs.
    
    Processes POST requests to create new short URLs by generating unique
    short codes and storing URL mappings in DynamoDB.
    
    Args:
        event: API Gateway event object
        context: Lambda context object
        
    Returns:
        dict: HTTP response with short URL details or error message
    \"\"\"
    try:
        logger.info(f"Received event: {json.dumps(event, default=str)}")
        
        # CORS headers for all responses
        cors_headers = {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
            'Access-Control-Allow-Methods': 'POST,OPTIONS'
        }
        
        # Parse request body
        if not event.get('body'):
            logger.warning("Request body is missing")
            return {
                'statusCode': 400,
                'headers': cors_headers,
                'body': json.dumps({'error': 'Request body is required'})
            }
        
        try:
            body = json.loads(event['body'])
        except json.JSONDecodeError as e:
            logger.error(f"Invalid JSON in request body: {str(e)}")
            return {
                'statusCode': 400,
                'headers': cors_headers,
                'body': json.dumps({'error': 'Invalid JSON in request body'})
            }
        
        original_url = body.get('url')
        
        # Validate URL presence
        if not original_url:
            logger.warning("URL parameter is missing")
            return {
                'statusCode': 400,
                'headers': cors_headers,
                'body': json.dumps({'error': 'URL parameter is required'})
            }
        
        # Validate URL format
        try:
            parsed_url = urlparse(original_url)
            if not all([parsed_url.scheme, parsed_url.netloc]):
                logger.warning(f"Invalid URL format: {original_url}")
                return {
                    'statusCode': 400,
                    'headers': cors_headers,
                    'body': json.dumps({'error': 'Invalid URL format. URL must include scheme (http/https) and domain'})
                }
            
            # Ensure scheme is http or https
            if parsed_url.scheme not in ['http', 'https']:
                logger.warning(f"Unsupported URL scheme: {parsed_url.scheme}")
                return {
                    'statusCode': 400,
                    'headers': cors_headers,
                    'body': json.dumps({'error': 'URL must use http or https scheme'})
                }
                
        except Exception as e:
            logger.error(f"URL parsing error: {str(e)}")
            return {
                'statusCode': 400,
                'headers': cors_headers,
                'body': json.dumps({'error': 'Invalid URL format'})
            }
        
        # Generate short code with collision handling
        short_code = generate_unique_short_code(original_url)
        
        # Get API Gateway domain from event context
        api_domain = event.get('requestContext', {}).get('domainName', 'your-api-domain')
        api_stage = event.get('requestContext', {}).get('stage', 'prod')
        short_url = f"https://{api_domain}/{api_stage}/{short_code}"
        
        logger.info(f"Created short URL: {short_code} -> {original_url}")
        
        return {
            'statusCode': 201,
            'headers': cors_headers,
            'body': json.dumps({
                'shortCode': short_code,
                'shortUrl': short_url,
                'originalUrl': original_url,
                'createdAt': context.aws_request_id,
                'message': 'Short URL created successfully'
            })
        }
        
    except Exception as e:
        logger.error(f"Unexpected error creating short URL: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Internal server error',
                'requestId': context.aws_request_id
            })
        }

def generate_unique_short_code(original_url: str, max_retries: int = 5) -> str:
    \"\"\"
    Generate a unique short code for the given URL.
    
    Args:
        original_url: The original URL to create a short code for
        max_retries: Maximum number of retry attempts for collision resolution
        
    Returns:
        str: A unique 6-character short code
        
    Raises:
        Exception: If unable to generate unique code after max retries
    \"\"\"
    for attempt in range(max_retries):
        # Generate 6-character alphanumeric code
        short_code = ''.join(random.choices(string.ascii_letters + string.digits, k=6))
        
        try:
            # Attempt to store with condition to prevent overwrites
            table.put_item(
                Item={
                    'shortCode': short_code,
                    'originalUrl': original_url,
                    'createdAt': boto3.dynamodb.conditions.Key('shortCode').gt('')  # placeholder for timestamp
                },
                ConditionExpression='attribute_not_exists(shortCode)'
            )
            return short_code
            
        except ClientError as e:
            if e.response['Error']['Code'] == 'ConditionalCheckFailedException':
                # Short code already exists, try again
                logger.info(f"Short code collision on attempt {attempt + 1}: {short_code}")
                if attempt == max_retries - 1:
                    logger.error(f"Unable to generate unique short code after {max_retries} attempts")
                    raise Exception("Unable to generate unique short code after multiple attempts")
                continue
            else:
                # Other DynamoDB error
                logger.error(f"DynamoDB error: {str(e)}")
                raise
    
    raise Exception("Unexpected error in short code generation")
"""

    def _get_redirect_function_code(self) -> str:
        """
        Get the Python code for the URL redirection Lambda function.
        
        Returns:
            str: The Lambda function code as a string
        """
        return """
import json
import boto3
import os
import logging
from botocore.exceptions import ClientError

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

# Initialize DynamoDB resource
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['TABLE_NAME'])

def lambda_handler(event, context):
    \"\"\"
    Lambda handler for URL redirection.
    
    Processes GET requests with short codes to redirect users to original URLs.
    
    Args:
        event: API Gateway event object
        context: Lambda context object
        
    Returns:
        dict: HTTP redirect response or error page
    \"\"\"
    try:
        logger.info(f"Received event: {json.dumps(event, default=str)}")
        
        # Get short code from path parameters
        path_params = event.get('pathParameters') or {}
        short_code = path_params.get('shortCode')
        
        if not short_code:
            logger.warning("Short code parameter is missing")
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'text/html'},
                'body': '''
                <!DOCTYPE html>
                <html>
                <head><title>400 - Bad Request</title></head>
                <body>
                    <h1>400 - Bad Request</h1>
                    <p>Short code parameter is required</p>
                    <p>Please check your URL and try again.</p>
                </body>
                </html>
                '''
            }
        
        # Validate short code format
        if not short_code or len(short_code) != 6 or not short_code.isalnum():
            logger.warning(f"Invalid short code format: {short_code}")
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'text/html'},
                'body': '''
                <!DOCTYPE html>
                <html>
                <head><title>400 - Bad Request</title></head>
                <body>
                    <h1>400 - Bad Request</h1>
                    <p>Invalid short code format</p>
                    <p>Short codes must be exactly 6 alphanumeric characters.</p>
                </body>
                </html>
                '''
            }
        
        # Lookup original URL in DynamoDB
        try:
            response = table.get_item(
                Key={'shortCode': short_code},
                ProjectionExpression='originalUrl'  # Only fetch what we need
            )
            
            if 'Item' in response:
                original_url = response['Item']['originalUrl']
                logger.info(f"Redirecting {short_code} to {original_url}")
                
                # Return 302 redirect with security headers
                return {
                    'statusCode': 302,
                    'headers': {
                        'Location': original_url,
                        'Cache-Control': 'no-cache, no-store, must-revalidate',
                        'Pragma': 'no-cache',
                        'Expires': '0',
                        'X-Frame-Options': 'DENY',
                        'X-Content-Type-Options': 'nosniff'
                    }
                }
            else:
                logger.warning(f"Short code not found: {short_code}")
                return {
                    'statusCode': 404,
                    'headers': {'Content-Type': 'text/html'},
                    'body': '''
                    <!DOCTYPE html>
                    <html>
                    <head><title>404 - Short URL Not Found</title></head>
                    <body>
                        <h1>404 - Short URL Not Found</h1>
                        <p>The requested short URL does not exist or has expired.</p>
                        <p>Please check the URL and try again, or contact the person who shared this link.</p>
                    </body>
                    </html>
                    '''
                }
                
        except ClientError as e:
            logger.error(f"DynamoDB error: {str(e)}")
            return {
                'statusCode': 500,
                'headers': {'Content-Type': 'text/html'},
                'body': '''
                <!DOCTYPE html>
                <html>
                <head><title>500 - Internal Server Error</title></head>
                <body>
                    <h1>500 - Internal Server Error</h1>
                    <p>A database error occurred while processing your request.</p>
                    <p>Please try again later.</p>
                </body>
                </html>
                '''
            }
            
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}", exc_info=True)
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'text/html'},
            'body': f'''
            <!DOCTYPE html>
            <html>
            <head><title>500 - Internal Server Error</title></head>
            <body>
                <h1>500 - Internal Server Error</h1>
                <p>An unexpected error occurred while processing your request.</p>
                <p>Request ID: {context.aws_request_id if 'context' in locals() else 'unknown'}</p>
                <p>Please try again later.</p>
            </body>
            </html>
            '''
        }
"""


class UrlShortenerApp(cdk.App):
    """Main CDK Application class."""
    
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        
        # Create the main stack
        UrlShortenerStack(
            self, "UrlShortenerStack",
            description="Serverless URL Shortener with API Gateway, Lambda, and DynamoDB",
            env=cdk.Environment(
                account=os.environ.get('CDK_DEFAULT_ACCOUNT'),
                region=os.environ.get('CDK_DEFAULT_REGION')
            )
        )


# Create and synthesize the application
app = UrlShortenerApp()
app.synth()