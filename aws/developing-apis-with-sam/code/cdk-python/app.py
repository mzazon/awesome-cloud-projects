#!/usr/bin/env python3
"""
CDK Python application for Serverless API Development with API Gateway and Lambda.

This application creates a complete serverless API using API Gateway, Lambda functions,
and DynamoDB, following AWS best practices for production deployments.
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
    aws_lambda as _lambda,
    aws_dynamodb as dynamodb,
    aws_iam as iam,
    aws_logs as logs,
)
from constructs import Construct


class ServerlessApiStack(Stack):
    """
    CDK Stack for Serverless API Development with API Gateway and Lambda.
    
    This stack creates:
    - API Gateway REST API with CORS configuration
    - Lambda functions for CRUD operations
    - DynamoDB table for data storage
    - CloudWatch log groups for monitoring
    - IAM roles with least privilege access
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Stack parameters
        self.api_name = "ServerlessUsersAPI"
        self.table_name = f"{construct_id}-users-table"
        
        # Create DynamoDB table
        self.users_table = self._create_dynamodb_table()
        
        # Create Lambda functions
        self.lambda_functions = self._create_lambda_functions()
        
        # Create API Gateway
        self.api = self._create_api_gateway()
        
        # Create API resources and methods
        self._create_api_resources()
        
        # Create outputs
        self._create_outputs()

    def _create_dynamodb_table(self) -> dynamodb.Table:
        """
        Create DynamoDB table for storing user data.
        
        Returns:
            dynamodb.Table: The created DynamoDB table
        """
        table = dynamodb.Table(
            self, "UsersTable",
            table_name=self.table_name,
            partition_key=dynamodb.Attribute(
                name="id",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            removal_policy=RemovalPolicy.DESTROY,  # Use RETAIN for production
            point_in_time_recovery=True,
            encryption=dynamodb.TableEncryption.AWS_MANAGED,
        )
        
        # Add tags
        cdk.Tags.of(table).add("Environment", "Development")
        cdk.Tags.of(table).add("Application", "ServerlessAPI")
        
        return table

    def _create_lambda_functions(self) -> Dict[str, _lambda.Function]:
        """
        Create Lambda functions for CRUD operations.
        
        Returns:
            Dict[str, _lambda.Function]: Dictionary of Lambda functions
        """
        functions = {}
        
        # Common Lambda configuration
        common_props = {
            "runtime": _lambda.Runtime.PYTHON_3_9,
            "timeout": Duration.seconds(30),
            "memory_size": 128,
            "environment": {
                "DYNAMODB_TABLE": self.users_table.table_name,
                "CORS_ALLOW_ORIGIN": "*",
                "LOG_LEVEL": "INFO"
            },
            "tracing": _lambda.Tracing.ACTIVE,  # Enable X-Ray tracing
        }
        
        # Function definitions
        function_configs = {
            "ListUsers": {
                "description": "List all users from DynamoDB",
                "code": self._get_list_users_code(),
                "actions": ["dynamodb:Scan"]
            },
            "CreateUser": {
                "description": "Create a new user in DynamoDB",
                "code": self._get_create_user_code(),
                "actions": ["dynamodb:PutItem"]
            },
            "GetUser": {
                "description": "Get a specific user from DynamoDB",
                "code": self._get_get_user_code(),
                "actions": ["dynamodb:GetItem"]
            },
            "UpdateUser": {
                "description": "Update an existing user in DynamoDB",
                "code": self._get_update_user_code(),
                "actions": ["dynamodb:GetItem", "dynamodb:UpdateItem"]
            },
            "DeleteUser": {
                "description": "Delete a user from DynamoDB",
                "code": self._get_delete_user_code(),
                "actions": ["dynamodb:GetItem", "dynamodb:DeleteItem"]
            }
        }
        
        # Create each Lambda function
        for func_name, config in function_configs.items():
            # Create CloudWatch log group
            log_group = logs.LogGroup(
                self, f"{func_name}LogGroup",
                log_group_name=f"/aws/lambda/{self.stack_name}-{func_name}",
                retention=logs.RetentionDays.ONE_WEEK,
                removal_policy=RemovalPolicy.DESTROY
            )
            
            # Create Lambda function
            function = _lambda.Function(
                self, f"{func_name}Function",
                function_name=f"{self.stack_name}-{func_name}",
                description=config["description"],
                code=_lambda.Code.from_inline(config["code"]),
                handler="index.lambda_handler",
                log_group=log_group,
                **common_props
            )
            
            # Grant DynamoDB permissions
            self._grant_dynamodb_permissions(function, config["actions"])
            
            functions[func_name] = function
        
        return functions

    def _grant_dynamodb_permissions(self, function: _lambda.Function, actions: list) -> None:
        """
        Grant specific DynamoDB permissions to a Lambda function.
        
        Args:
            function: The Lambda function to grant permissions to
            actions: List of DynamoDB actions to allow
        """
        function.add_to_role_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=actions,
                resources=[self.users_table.table_arn]
            )
        )

    def _create_api_gateway(self) -> apigateway.RestApi:
        """
        Create API Gateway with CORS configuration.
        
        Returns:
            apigateway.RestApi: The created API Gateway
        """
        # Create CloudWatch log group for API Gateway
        api_log_group = logs.LogGroup(
            self, "ApiGatewayLogGroup",
            log_group_name=f"/aws/apigateway/{self.api_name}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY
        )
        
        # Create API Gateway
        api = apigateway.RestApi(
            self, "UsersApi",
            rest_api_name=self.api_name,
            description="Serverless API for user management",
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
            deploy_options=apigateway.StageOptions(
                stage_name="dev",
                throttling_rate_limit=100,
                throttling_burst_limit=200,
                logging_level=apigateway.MethodLoggingLevel.INFO,
                access_log_destination=apigateway.LogGroupLogDestination(api_log_group),
                access_log_format=apigateway.AccessLogFormat.json_with_standard_fields()
            ),
            endpoint_configuration=apigateway.EndpointConfiguration(
                types=[apigateway.EndpointType.REGIONAL]
            )
        )
        
        return api

    def _create_api_resources(self) -> None:
        """Create API Gateway resources and methods."""
        # Create /users resource
        users_resource = self.api.root.add_resource("users")
        
        # Add methods to /users resource
        self._add_method(
            users_resource, "GET", self.lambda_functions["ListUsers"],
            "List all users"
        )
        self._add_method(
            users_resource, "POST", self.lambda_functions["CreateUser"],
            "Create a new user"
        )
        
        # Create /users/{id} resource
        user_resource = users_resource.add_resource("{id}")
        
        # Add methods to /users/{id} resource
        self._add_method(
            user_resource, "GET", self.lambda_functions["GetUser"],
            "Get a specific user"
        )
        self._add_method(
            user_resource, "PUT", self.lambda_functions["UpdateUser"],
            "Update a user"
        )
        self._add_method(
            user_resource, "DELETE", self.lambda_functions["DeleteUser"],
            "Delete a user"
        )

    def _add_method(
        self, 
        resource: apigateway.Resource, 
        method: str, 
        function: _lambda.Function,
        description: str
    ) -> None:
        """
        Add a method to an API Gateway resource.
        
        Args:
            resource: The API Gateway resource
            method: HTTP method (GET, POST, etc.)
            function: Lambda function to integrate with
            description: Method description
        """
        integration = apigateway.LambdaIntegration(
            function,
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
        
        resource.add_method(
            method,
            integration,
            method_responses=[
                apigateway.MethodResponse(
                    status_code="200",
                    response_parameters={
                        "method.response.header.Access-Control-Allow-Origin": True
                    }
                )
            ]
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs."""
        CfnOutput(
            self, "ApiGatewayUrl",
            value=self.api.url,
            description="API Gateway endpoint URL",
            export_name=f"{self.stack_name}-ApiUrl"
        )
        
        CfnOutput(
            self, "UsersTableName",
            value=self.users_table.table_name,
            description="DynamoDB table name",
            export_name=f"{self.stack_name}-TableName"
        )
        
        CfnOutput(
            self, "ApiGatewayId",
            value=self.api.rest_api_id,
            description="API Gateway ID",
            export_name=f"{self.stack_name}-ApiId"
        )

    def _get_list_users_code(self) -> str:
        """Get the Lambda function code for listing users."""
        return '''
import json
import boto3
from botocore.exceptions import ClientError
import os
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

dynamodb = boto3.resource('dynamodb')

def create_response(status_code, body, headers=None):
    """Create HTTP response with CORS headers."""
    default_headers = {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
        'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS'
    }
    
    if headers:
        default_headers.update(headers)
    
    return {
        'statusCode': status_code,
        'headers': default_headers,
        'body': json.dumps(body) if isinstance(body, (dict, list)) else body
    }

def lambda_handler(event, context):
    """List all users from DynamoDB."""
    try:
        table_name = os.environ['DYNAMODB_TABLE']
        table = dynamodb.Table(table_name)
        
        logger.info(f"Scanning table: {table_name}")
        
        # Scan table for all users
        response = table.scan()
        users = response.get('Items', [])
        
        # Handle pagination if needed
        while 'LastEvaluatedKey' in response:
            response = table.scan(ExclusiveStartKey=response['LastEvaluatedKey'])
            users.extend(response.get('Items', []))
        
        logger.info(f"Found {len(users)} users")
        return create_response(200, users)
        
    except ClientError as e:
        logger.error(f"DynamoDB error: {e}")
        if e.response['Error']['Code'] == 'ResourceNotFoundException':
            return create_response(404, {'error': 'Table not found'})
        else:
            return create_response(500, {'error': 'Internal server error'})
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        return create_response(500, {'error': 'Internal server error'})
'''

    def _get_create_user_code(self) -> str:
        """Get the Lambda function code for creating users."""
        return '''
import json
import boto3
from botocore.exceptions import ClientError
import os
import uuid
from datetime import datetime
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

dynamodb = boto3.resource('dynamodb')

def create_response(status_code, body, headers=None):
    """Create HTTP response with CORS headers."""
    default_headers = {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
        'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS'
    }
    
    if headers:
        default_headers.update(headers)
    
    return {
        'statusCode': status_code,
        'headers': default_headers,
        'body': json.dumps(body) if isinstance(body, (dict, list)) else body
    }

def lambda_handler(event, context):
    """Create a new user in DynamoDB."""
    try:
        # Parse request body
        body = json.loads(event.get('body', '{}'))
        
        # Validate required fields
        if not body.get('name') or not body.get('email'):
            return create_response(400, {'error': 'Name and email are required'})
        
        # Generate user ID and timestamp
        user_id = str(uuid.uuid4())
        timestamp = datetime.utcnow().isoformat()
        
        # Create user item
        user_item = {
            'id': user_id,
            'name': body['name'],
            'email': body['email'],
            'created_at': timestamp,
            'updated_at': timestamp
        }
        
        # Optional fields
        if body.get('age'):
            try:
                user_item['age'] = int(body['age'])
            except ValueError:
                return create_response(400, {'error': 'Age must be a number'})
        
        # Put item in DynamoDB
        table_name = os.environ['DYNAMODB_TABLE']
        table = dynamodb.Table(table_name)
        
        logger.info(f"Creating user: {user_id}")
        table.put_item(Item=user_item)
        
        logger.info(f"User created successfully: {user_id}")
        return create_response(201, user_item)
        
    except json.JSONDecodeError:
        return create_response(400, {'error': 'Invalid JSON in request body'})
    except ClientError as e:
        logger.error(f"DynamoDB error: {e}")
        return create_response(500, {'error': 'Internal server error'})
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        return create_response(500, {'error': 'Internal server error'})
'''

    def _get_get_user_code(self) -> str:
        """Get the Lambda function code for getting a user."""
        return '''
import json
import boto3
from botocore.exceptions import ClientError
import os
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

dynamodb = boto3.resource('dynamodb')

def create_response(status_code, body, headers=None):
    """Create HTTP response with CORS headers."""
    default_headers = {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
        'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS'
    }
    
    if headers:
        default_headers.update(headers)
    
    return {
        'statusCode': status_code,
        'headers': default_headers,
        'body': json.dumps(body) if isinstance(body, (dict, list)) else body
    }

def lambda_handler(event, context):
    """Get a specific user from DynamoDB."""
    try:
        # Get user ID from path parameters
        user_id = event['pathParameters']['id']
        
        # Get item from DynamoDB
        table_name = os.environ['DYNAMODB_TABLE']
        table = dynamodb.Table(table_name)
        
        logger.info(f"Getting user: {user_id}")
        response = table.get_item(Key={'id': user_id})
        
        if 'Item' not in response:
            logger.warning(f"User not found: {user_id}")
            return create_response(404, {'error': 'User not found'})
        
        logger.info(f"User retrieved successfully: {user_id}")
        return create_response(200, response['Item'])
        
    except ClientError as e:
        logger.error(f"DynamoDB error: {e}")
        return create_response(500, {'error': 'Internal server error'})
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        return create_response(500, {'error': 'Internal server error'})
'''

    def _get_update_user_code(self) -> str:
        """Get the Lambda function code for updating a user."""
        return '''
import json
import boto3
from botocore.exceptions import ClientError
import os
from datetime import datetime
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

dynamodb = boto3.resource('dynamodb')

def create_response(status_code, body, headers=None):
    """Create HTTP response with CORS headers."""
    default_headers = {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
        'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS'
    }
    
    if headers:
        default_headers.update(headers)
    
    return {
        'statusCode': status_code,
        'headers': default_headers,
        'body': json.dumps(body) if isinstance(body, (dict, list)) else body
    }

def lambda_handler(event, context):
    """Update an existing user in DynamoDB."""
    try:
        # Get user ID from path parameters
        user_id = event['pathParameters']['id']
        
        # Parse request body
        body = json.loads(event.get('body', '{}'))
        
        # Check if user exists
        table_name = os.environ['DYNAMODB_TABLE']
        table = dynamodb.Table(table_name)
        
        logger.info(f"Checking if user exists: {user_id}")
        response = table.get_item(Key={'id': user_id})
        
        if 'Item' not in response:
            logger.warning(f"User not found: {user_id}")
            return create_response(404, {'error': 'User not found'})
        
        # Build update expression
        update_expression = "SET updated_at = :timestamp"
        expression_values = {':timestamp': datetime.utcnow().isoformat()}
        expression_names = {}
        
        if body.get('name'):
            update_expression += ", #name = :name"
            expression_values[':name'] = body['name']
            expression_names['#name'] = 'name'
        
        if body.get('email'):
            update_expression += ", email = :email"
            expression_values[':email'] = body['email']
        
        if body.get('age'):
            try:
                update_expression += ", age = :age"
                expression_values[':age'] = int(body['age'])
            except ValueError:
                return create_response(400, {'error': 'Age must be a number'})
        
        # Update item
        logger.info(f"Updating user: {user_id}")
        kwargs = {
            'Key': {'id': user_id},
            'UpdateExpression': update_expression,
            'ExpressionAttributeValues': expression_values,
            'ReturnValues': 'ALL_NEW'
        }
        
        if expression_names:
            kwargs['ExpressionAttributeNames'] = expression_names
        
        response = table.update_item(**kwargs)
        
        logger.info(f"User updated successfully: {user_id}")
        return create_response(200, response['Attributes'])
        
    except json.JSONDecodeError:
        return create_response(400, {'error': 'Invalid JSON in request body'})
    except ClientError as e:
        logger.error(f"DynamoDB error: {e}")
        return create_response(500, {'error': 'Internal server error'})
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        return create_response(500, {'error': 'Internal server error'})
'''

    def _get_delete_user_code(self) -> str:
        """Get the Lambda function code for deleting a user."""
        return '''
import json
import boto3
from botocore.exceptions import ClientError
import os
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

dynamodb = boto3.resource('dynamodb')

def create_response(status_code, body, headers=None):
    """Create HTTP response with CORS headers."""
    default_headers = {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
        'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS'
    }
    
    if headers:
        default_headers.update(headers)
    
    return {
        'statusCode': status_code,
        'headers': default_headers,
        'body': json.dumps(body) if isinstance(body, (dict, list)) else body
    }

def lambda_handler(event, context):
    """Delete a user from DynamoDB."""
    try:
        # Get user ID from path parameters
        user_id = event['pathParameters']['id']
        
        # Check if user exists
        table_name = os.environ['DYNAMODB_TABLE']
        table = dynamodb.Table(table_name)
        
        logger.info(f"Checking if user exists: {user_id}")
        response = table.get_item(Key={'id': user_id})
        
        if 'Item' not in response:
            logger.warning(f"User not found: {user_id}")
            return create_response(404, {'error': 'User not found'})
        
        # Delete item
        logger.info(f"Deleting user: {user_id}")
        table.delete_item(Key={'id': user_id})
        
        logger.info(f"User deleted successfully: {user_id}")
        return create_response(204, '')
        
    except ClientError as e:
        logger.error(f"DynamoDB error: {e}")
        return create_response(500, {'error': 'Internal server error'})
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        return create_response(500, {'error': 'Internal server error'})
'''


def main():
    """Main application entry point."""
    app = cdk.App()
    
    # Get stack name from context or use default
    stack_name = app.node.try_get_context("stackName") or "ServerlessApiStack"
    
    # Create the stack
    ServerlessApiStack(
        app, stack_name,
        description="CDK Python stack for Serverless API Development with API Gateway and Lambda",
        env=cdk.Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION")
        )
    )
    
    app.synth()


if __name__ == "__main__":
    main()