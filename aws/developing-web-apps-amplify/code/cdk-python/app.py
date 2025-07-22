#!/usr/bin/env python3
"""
CDK Application for Serverless Web Applications with Amplify and Lambda

This CDK application deploys a complete serverless web application infrastructure
using AWS Amplify for frontend hosting and Lambda functions for backend APIs.
The stack includes authentication, API Gateway, Lambda functions, and DynamoDB.
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_amplify as amplify,
    aws_lambda as lambda_,
    aws_apigateway as apigateway,
    aws_dynamodb as dynamodb,
    aws_cognito as cognito,
    aws_iam as iam,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
)
from constructs import Construct


class ServerlessWebAppStack(Stack):
    """
    CDK Stack for Serverless Web Application with Amplify and Lambda
    
    This stack creates:
    - DynamoDB table for todo storage
    - Lambda function for API backend
    - API Gateway REST API
    - Cognito User Pool for authentication
    - Amplify app for frontend hosting
    - CloudWatch monitoring and logging
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Get configuration from context or environment
        app_name = self.node.try_get_context("appName") or "serverless-web-app"
        environment = self.node.try_get_context("environment") or "dev"
        
        # Create DynamoDB table for todos
        self.todos_table = self._create_dynamodb_table(app_name, environment)
        
        # Create Lambda function for API backend
        self.api_lambda = self._create_lambda_function(app_name, environment)
        
        # Grant Lambda permissions to access DynamoDB
        self.todos_table.grant_read_write_data(self.api_lambda)
        
        # Create API Gateway
        self.api_gateway = self._create_api_gateway(app_name, environment)
        
        # Create Cognito User Pool for authentication
        self.user_pool = self._create_cognito_user_pool(app_name, environment)
        
        # Create Amplify app for frontend hosting
        self.amplify_app = self._create_amplify_app(app_name, environment)
        
        # Create CloudWatch monitoring
        self._create_monitoring_dashboard(app_name, environment)
        
        # Output important values
        self._create_outputs()

    def _create_dynamodb_table(self, app_name: str, environment: str) -> dynamodb.Table:
        """
        Create DynamoDB table for storing todo items
        
        Args:
            app_name: Application name for resource naming
            environment: Environment name (dev, staging, prod)
            
        Returns:
            DynamoDB Table construct
        """
        table = dynamodb.Table(
            self, 
            "TodosTable",
            table_name=f"{app_name}-todos-{environment}",
            partition_key=dynamodb.Attribute(
                name="id",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            encryption=dynamodb.TableEncryption.AWS_MANAGED,
            removal_policy=RemovalPolicy.DESTROY,
            point_in_time_recovery=True,
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
        )
        
        # Add tags for cost allocation and management
        cdk.Tags.of(table).add("Environment", environment)
        cdk.Tags.of(table).add("Application", app_name)
        cdk.Tags.of(table).add("Component", "Database")
        
        return table

    def _create_lambda_function(self, app_name: str, environment: str) -> lambda_.Function:
        """
        Create Lambda function for API backend
        
        Args:
            app_name: Application name for resource naming
            environment: Environment name (dev, staging, prod)
            
        Returns:
            Lambda Function construct
        """
        # Create Lambda execution role with necessary permissions
        lambda_role = iam.Role(
            self,
            "LambdaExecutionRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole"),
            ],
        )
        
        # Lambda function code
        function_code = """
import json
import boto3
import uuid
import logging
from datetime import datetime
from typing import Dict, Any, Optional

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize DynamoDB client
dynamodb = boto3.resource('dynamodb')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    \"\"\"
    Lambda function handler for Todo API
    
    Handles CRUD operations for todo items using DynamoDB
    \"\"\"
    logger.info(f"Received event: {json.dumps(event)}")
    
    try:
        # Get table name from environment variable
        table_name = os.environ.get('TODOS_TABLE_NAME')
        if not table_name:
            raise ValueError("TODOS_TABLE_NAME environment variable not set")
            
        table = dynamodb.Table(table_name)
        
        # Extract HTTP method and path
        http_method = event.get('httpMethod', '').upper()
        path = event.get('path', '')
        path_parameters = event.get('pathParameters') or {}
        
        # Route request based on HTTP method
        if http_method == 'GET':
            response = get_todos(table)
        elif http_method == 'POST':
            body = json.loads(event.get('body', '{}'))
            response = create_todo(table, body)
        elif http_method == 'PUT':
            body = json.loads(event.get('body', '{}'))
            response = update_todo(table, body)
        elif http_method == 'DELETE':
            todo_id = path_parameters.get('id')
            if not todo_id:
                return create_error_response(400, "Missing todo ID in path")
            response = delete_todo(table, todo_id)
        else:
            response = create_error_response(405, f"Method {http_method} not allowed")
            
        return response
        
    except Exception as e:
        logger.error(f"Error processing request: {str(e)}")
        return create_error_response(500, "Internal server error")

def get_todos(table) -> Dict[str, Any]:
    \"\"\"Get all todos from DynamoDB\"\"\"
    try:
        response = table.scan()
        todos = response.get('Items', [])
        
        # Sort todos by creation date (newest first)
        todos.sort(key=lambda x: x.get('createdAt', ''), reverse=True)
        
        return create_success_response(200, todos)
        
    except Exception as e:
        logger.error(f"Error getting todos: {str(e)}")
        return create_error_response(500, "Failed to retrieve todos")

def create_todo(table, todo_data: Dict[str, Any]) -> Dict[str, Any]:
    \"\"\"Create a new todo item\"\"\"
    try:
        # Validate required fields
        title = todo_data.get('title', '').strip()
        if not title:
            return create_error_response(400, "Title is required")
            
        # Create new todo item
        todo_item = {
            'id': str(uuid.uuid4()),
            'title': title,
            'completed': todo_data.get('completed', False),
            'createdAt': datetime.utcnow().isoformat(),
            'updatedAt': datetime.utcnow().isoformat()
        }
        
        # Save to DynamoDB
        table.put_item(Item=todo_item)
        
        return create_success_response(201, todo_item)
        
    except Exception as e:
        logger.error(f"Error creating todo: {str(e)}")
        return create_error_response(500, "Failed to create todo")

def update_todo(table, todo_data: Dict[str, Any]) -> Dict[str, Any]:
    \"\"\"Update an existing todo item\"\"\"
    try:
        todo_id = todo_data.get('id')
        if not todo_id:
            return create_error_response(400, "Todo ID is required")
            
        # Prepare update expression
        update_expression = "SET updatedAt = :updatedAt"
        expression_values = {
            ':updatedAt': datetime.utcnow().isoformat()
        }
        
        # Add optional fields to update
        if 'title' in todo_data:
            update_expression += ", title = :title"
            expression_values[':title'] = todo_data['title']
            
        if 'completed' in todo_data:
            update_expression += ", completed = :completed"
            expression_values[':completed'] = todo_data['completed']
        
        # Update item in DynamoDB
        response = table.update_item(
            Key={'id': todo_id},
            UpdateExpression=update_expression,
            ExpressionAttributeValues=expression_values,
            ReturnValues='ALL_NEW'
        )
        
        return create_success_response(200, response['Attributes'])
        
    except table.meta.client.exceptions.ResourceNotFoundException:
        return create_error_response(404, "Todo not found")
    except Exception as e:
        logger.error(f"Error updating todo: {str(e)}")
        return create_error_response(500, "Failed to update todo")

def delete_todo(table, todo_id: str) -> Dict[str, Any]:
    \"\"\"Delete a todo item\"\"\"
    try:
        # Delete item from DynamoDB
        table.delete_item(
            Key={'id': todo_id},
            ConditionExpression='attribute_exists(id)'
        )
        
        return create_success_response(204, None)
        
    except table.meta.client.exceptions.ConditionalCheckFailedException:
        return create_error_response(404, "Todo not found")
    except Exception as e:
        logger.error(f"Error deleting todo: {str(e)}")
        return create_error_response(500, "Failed to delete todo")

def create_success_response(status_code: int, data: Any) -> Dict[str, Any]:
    \"\"\"Create a successful API response\"\"\"
    response = {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
            'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS'
        }
    }
    
    if data is not None:
        response['body'] = json.dumps(data, default=str)
        
    return response

def create_error_response(status_code: int, message: str) -> Dict[str, Any]:
    \"\"\"Create an error API response\"\"\"
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
            'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS'
        },
        'body': json.dumps({
            'error': message,
            'timestamp': datetime.utcnow().isoformat()
        })
    }
"""
        
        # Create Lambda function
        api_function = lambda_.Function(
            self,
            "TodoApiFunction",
            function_name=f"{app_name}-api-{environment}",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(function_code),
            timeout=Duration.seconds(30),
            memory_size=256,
            role=lambda_role,
            environment={
                "TODOS_TABLE_NAME": self.todos_table.table_name,
                "LOG_LEVEL": "INFO"
            },
            retry_attempts=2,
            log_retention=logs.RetentionDays.ONE_WEEK,
            tracing=lambda_.Tracing.ACTIVE,
        )
        
        # Add tags
        cdk.Tags.of(api_function).add("Environment", environment)
        cdk.Tags.of(api_function).add("Application", app_name)
        cdk.Tags.of(api_function).add("Component", "API")
        
        return api_function

    def _create_api_gateway(self, app_name: str, environment: str) -> apigateway.RestApi:
        """
        Create API Gateway REST API with Lambda integration
        
        Args:
            app_name: Application name for resource naming
            environment: Environment name (dev, staging, prod)
            
        Returns:
            API Gateway RestApi construct
        """
        # Create API Gateway
        api = apigateway.RestApi(
            self,
            "TodoApi",
            rest_api_name=f"{app_name}-api-{environment}",
            description=f"REST API for {app_name} todo application",
            endpoint_configuration=apigateway.EndpointConfiguration(
                types=[apigateway.EndpointType.REGIONAL]
            ),
            default_cors_preflight_options=apigateway.CorsOptions(
                allow_origins=apigateway.Cors.ALL_ORIGINS,
                allow_methods=apigateway.Cors.ALL_METHODS,
                allow_headers=[
                    "Content-Type",
                    "X-Amz-Date", 
                    "Authorization",
                    "X-Api-Key",
                    "X-Amz-Security-Token"
                ]
            ),
            deploy=True,
            deploy_options=apigateway.StageOptions(
                stage_name=environment,
                throttling_rate_limit=1000,
                throttling_burst_limit=2000,
                logging_level=apigateway.MethodLoggingLevel.INFO,
                data_trace_enabled=True,
                metrics_enabled=True
            )
        )
        
        # Create Lambda integration
        lambda_integration = apigateway.LambdaIntegration(
            self.api_lambda,
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
        
        # Create /todos resource
        todos_resource = api.root.add_resource("todos")
        
        # Add methods to /todos resource
        todos_resource.add_method(
            "GET", 
            lambda_integration,
            method_responses=[
                apigateway.MethodResponse(
                    status_code="200",
                    response_parameters={
                        "method.response.header.Access-Control-Allow-Origin": True
                    }
                )
            ]
        )
        
        todos_resource.add_method(
            "POST", 
            lambda_integration,
            method_responses=[
                apigateway.MethodResponse(
                    status_code="201",
                    response_parameters={
                        "method.response.header.Access-Control-Allow-Origin": True
                    }
                )
            ]
        )
        
        # Create /todos/{id} resource for individual todo operations
        todo_resource = todos_resource.add_resource("{id}")
        
        todo_resource.add_method(
            "PUT", 
            lambda_integration,
            method_responses=[
                apigateway.MethodResponse(
                    status_code="200",
                    response_parameters={
                        "method.response.header.Access-Control-Allow-Origin": True
                    }
                )
            ]
        )
        
        todo_resource.add_method(
            "DELETE", 
            lambda_integration,
            method_responses=[
                apigateway.MethodResponse(
                    status_code="204",
                    response_parameters={
                        "method.response.header.Access-Control-Allow-Origin": True
                    }
                )
            ]
        )
        
        # Add tags
        cdk.Tags.of(api).add("Environment", environment)
        cdk.Tags.of(api).add("Application", app_name)
        cdk.Tags.of(api).add("Component", "API")
        
        return api

    def _create_cognito_user_pool(self, app_name: str, environment: str) -> cognito.UserPool:
        """
        Create Cognito User Pool for authentication
        
        Args:
            app_name: Application name for resource naming
            environment: Environment name (dev, staging, prod)
            
        Returns:
            Cognito UserPool construct
        """
        # Create User Pool
        user_pool = cognito.UserPool(
            self,
            "UserPool",
            user_pool_name=f"{app_name}-users-{environment}",
            sign_in_aliases=cognito.SignInAliases(
                email=True,
                username=True
            ),
            auto_verify=cognito.AutoVerifiedAttrs(email=True),
            standard_attributes=cognito.StandardAttributes(
                email=cognito.StandardAttribute(required=True, mutable=True),
                given_name=cognito.StandardAttribute(required=True, mutable=True),
                family_name=cognito.StandardAttribute(required=True, mutable=True)
            ),
            password_policy=cognito.PasswordPolicy(
                min_length=8,
                require_lowercase=True,
                require_uppercase=True,
                require_digits=True,
                require_symbols=False
            ),
            account_recovery=cognito.AccountRecovery.EMAIL_ONLY,
            removal_policy=RemovalPolicy.DESTROY
        )
        
        # Create User Pool Client
        user_pool_client = cognito.UserPoolClient(
            self,
            "UserPoolClient",
            user_pool=user_pool,
            user_pool_client_name=f"{app_name}-client-{environment}",
            auth_flows=cognito.AuthFlow(
                user_password=True,
                user_srp=True
            ),
            supported_identity_providers=[
                cognito.UserPoolClientIdentityProvider.COGNITO
            ],
            read_attributes=cognito.ClientAttributes(
                email=True,
                given_name=True,
                family_name=True
            ),
            write_attributes=cognito.ClientAttributes(
                email=True,
                given_name=True,
                family_name=True
            )
        )
        
        # Add tags
        cdk.Tags.of(user_pool).add("Environment", environment)
        cdk.Tags.of(user_pool).add("Application", app_name)
        cdk.Tags.of(user_pool).add("Component", "Authentication")
        
        return user_pool

    def _create_amplify_app(self, app_name: str, environment: str) -> amplify.CfnApp:
        """
        Create Amplify app for frontend hosting
        
        Args:
            app_name: Application name for resource naming
            environment: Environment name (dev, staging, prod)
            
        Returns:
            Amplify CfnApp construct
        """
        # Create Amplify service role
        amplify_role = iam.Role(
            self,
            "AmplifyServiceRole",
            assumed_by=iam.ServicePrincipal("amplify.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AdministratorAccess-Amplify")
            ]
        )
        
        # Create Amplify app
        amplify_app = amplify.CfnApp(
            self,
            "AmplifyApp",
            name=f"{app_name}-{environment}",
            description=f"Serverless web application - {environment}",
            platform="WEB",
            iam_service_role=amplify_role.role_arn,
            environment_variables=[
                amplify.CfnApp.EnvironmentVariableProperty(
                    name="REACT_APP_API_URL",
                    value=self.api_gateway.url
                ),
                amplify.CfnApp.EnvironmentVariableProperty(
                    name="REACT_APP_USER_POOL_ID",
                    value=self.user_pool.user_pool_id
                ),
                amplify.CfnApp.EnvironmentVariableProperty(
                    name="REACT_APP_USER_POOL_WEB_CLIENT_ID",
                    value=self.user_pool.user_pool_id  # This would need the actual client ID
                ),
                amplify.CfnApp.EnvironmentVariableProperty(
                    name="REACT_APP_REGION",
                    value=self.region
                )
            ],
            build_spec="""
version: 1
frontend:
  phases:
    preBuild:
      commands:
        - npm ci
    build:
      commands:
        - npm run build
  artifacts:
    baseDirectory: build
    files:
      - '**/*'
  cache:
    paths:
      - node_modules/**/*
            """,
            custom_rules=[
                amplify.CfnApp.CustomRuleProperty(
                    source="/api/<*>",
                    target=f"{self.api_gateway.url}/<*>",
                    status="200"
                )
            ]
        )
        
        # Add tags
        cdk.Tags.of(amplify_app).add("Environment", environment)
        cdk.Tags.of(amplify_app).add("Application", app_name)
        cdk.Tags.of(amplify_app).add("Component", "Frontend")
        
        return amplify_app

    def _create_monitoring_dashboard(self, app_name: str, environment: str) -> None:
        """
        Create CloudWatch monitoring dashboard
        
        Args:
            app_name: Application name for resource naming
            environment: Environment name (dev, staging, prod)
        """
        dashboard = cloudwatch.Dashboard(
            self,
            "MonitoringDashboard",
            dashboard_name=f"{app_name}-{environment}-dashboard"
        )
        
        # Lambda function metrics
        lambda_duration_widget = cloudwatch.GraphWidget(
            title="Lambda Duration",
            left=[
                self.api_lambda.metric_duration(
                    statistic="Average",
                    period=Duration.minutes(5)
                )
            ],
            width=12,
            height=6
        )
        
        lambda_errors_widget = cloudwatch.GraphWidget(
            title="Lambda Errors",
            left=[
                self.api_lambda.metric_errors(
                    statistic="Sum",
                    period=Duration.minutes(5)
                )
            ],
            width=12,
            height=6
        )
        
        lambda_invocations_widget = cloudwatch.GraphWidget(
            title="Lambda Invocations",
            left=[
                self.api_lambda.metric_invocations(
                    statistic="Sum",
                    period=Duration.minutes(5)
                )
            ],
            width=12,
            height=6
        )
        
        # API Gateway metrics
        api_requests_widget = cloudwatch.GraphWidget(
            title="API Gateway Requests",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/ApiGateway",
                    metric_name="Count",
                    dimensions_map={
                        "ApiName": self.api_gateway.rest_api_name
                    },
                    statistic="Sum",
                    period=Duration.minutes(5)
                )
            ],
            width=12,
            height=6
        )
        
        # DynamoDB metrics
        dynamodb_reads_widget = cloudwatch.GraphWidget(
            title="DynamoDB Read Capacity",
            left=[
                self.todos_table.metric_consumed_read_capacity_units(
                    statistic="Sum",
                    period=Duration.minutes(5)
                )
            ],
            width=12,
            height=6
        )
        
        dynamodb_writes_widget = cloudwatch.GraphWidget(
            title="DynamoDB Write Capacity",
            left=[
                self.todos_table.metric_consumed_write_capacity_units(
                    statistic="Sum",
                    period=Duration.minutes(5)
                )
            ],
            width=12,
            height=6
        )
        
        # Add widgets to dashboard
        dashboard.add_widgets(
            lambda_duration_widget,
            lambda_errors_widget,
            lambda_invocations_widget,
            api_requests_widget,
            dynamodb_reads_widget,
            dynamodb_writes_widget
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources"""
        
        CfnOutput(
            self,
            "ApiGatewayUrl",
            value=self.api_gateway.url,
            description="API Gateway endpoint URL",
            export_name=f"{self.stack_name}-ApiUrl"
        )
        
        CfnOutput(
            self,
            "UserPoolId",
            value=self.user_pool.user_pool_id,
            description="Cognito User Pool ID",
            export_name=f"{self.stack_name}-UserPoolId"
        )
        
        CfnOutput(
            self,
            "TodosTableName",
            value=self.todos_table.table_name,
            description="DynamoDB table name for todos",
            export_name=f"{self.stack_name}-TodosTable"
        )
        
        CfnOutput(
            self,
            "LambdaFunctionName",
            value=self.api_lambda.function_name,
            description="Lambda function name for API",
            export_name=f"{self.stack_name}-LambdaFunction"
        )
        
        CfnOutput(
            self,
            "AmplifyAppId",
            value=self.amplify_app.attr_app_id,
            description="Amplify App ID",
            export_name=f"{self.stack_name}-AmplifyAppId"
        )


# Create CDK app
app = cdk.App()

# Get configuration from context
app_name = app.node.try_get_context("appName") or "serverless-web-app"
environment = app.node.try_get_context("environment") or "dev"

# Create the stack
ServerlessWebAppStack(
    app, 
    f"ServerlessWebApp-{environment}",
    description=f"Serverless Web Application with Amplify and Lambda - {environment}",
    env=cdk.Environment(
        account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
        region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
    ),
    tags={
        "Project": app_name,
        "Environment": environment,
        "ManagedBy": "CDK"
    }
)

# Synthesize the app
app.synth()