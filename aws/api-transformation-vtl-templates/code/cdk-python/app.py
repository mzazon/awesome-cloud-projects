#!/usr/bin/env python3
"""
CDK Application for Request/Response Transformation with VTL Templates and Custom Models

This application demonstrates advanced API Gateway transformation capabilities using
Velocity Template Language (VTL) mapping templates, custom JSON Schema models,
and comprehensive error handling patterns.

Features:
- Request/response transformation with VTL templates
- JSON Schema validation models
- Custom error handling with gateway responses
- Multi-integration patterns (Lambda, S3)
- CloudWatch logging and monitoring
- Best practices for enterprise API design

Author: AWS CDK Team
Version: 1.0.0
"""

import json
import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Duration,
    Stack,
    CfnOutput,
    RemovalPolicy,
    aws_apigateway as apigw,
    aws_lambda as lambda_,
    aws_s3 as s3,
    aws_iam as iam,
    aws_logs as logs,
)
from constructs import Construct


class RequestResponseTransformationStack(Stack):
    """
    CDK Stack for implementing request/response transformation with VTL templates.
    
    This stack creates:
    - Lambda function for data processing
    - S3 bucket for data storage
    - API Gateway with custom models and VTL transformations
    - CloudWatch logging and monitoring
    - IAM roles with least privilege access
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        unique_suffix = self.node.try_get_context("unique_suffix") or "dev"
        
        # Create S3 bucket for data operations
        self.data_bucket = self._create_data_bucket(unique_suffix)
        
        # Create Lambda function for data processing
        self.processor_function = self._create_processor_function(unique_suffix)
        
        # Create API Gateway with transformations
        self.api = self._create_api_gateway(unique_suffix)
        
        # Create custom models for validation
        self._create_custom_models()
        
        # Create resources and methods
        self._create_api_resources()
        
        # Configure request/response transformations
        self._configure_transformations()
        
        # Create custom error responses
        self._create_custom_error_responses()
        
        # Create outputs
        self._create_outputs()

    def _create_data_bucket(self, unique_suffix: str) -> s3.Bucket:
        """Create S3 bucket for data storage with proper security configuration."""
        return s3.Bucket(
            self,
            "DataBucket",
            bucket_name=f"api-data-store-{unique_suffix}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteOldVersions",
                    enabled=True,
                    noncurrent_version_expiration=Duration.days(30),
                )
            ],
        )

    def _create_processor_function(self, unique_suffix: str) -> lambda_.Function:
        """Create Lambda function for processing transformed requests."""
        # Create IAM role for Lambda function
        lambda_role = iam.Role(
            self,
            "ProcessorFunctionRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                ),
            ],
        )
        
        # Grant S3 permissions to Lambda
        self.data_bucket.grant_read_write(lambda_role)
        
        # Create Lambda function
        processor_function = lambda_.Function(
            self,
            "ProcessorFunction",
            function_name=f"data-processor-{unique_suffix}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            role=lambda_role,
            code=lambda_.Code.from_inline(self._get_lambda_code()),
            description="Data processor with transformation support",
            timeout=Duration.seconds(30),
            memory_size=256,
            environment={
                "BUCKET_NAME": self.data_bucket.bucket_name,
                "LOG_LEVEL": "INFO",
            },
            log_retention=logs.RetentionDays.ONE_WEEK,
        )
        
        return processor_function

    def _get_lambda_code(self) -> str:
        """Return the Lambda function code as a string."""
        return '''
import json
import boto3
import uuid
from datetime import datetime
import os
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

s3 = boto3.client('s3')
bucket_name = os.environ.get('BUCKET_NAME')

def lambda_handler(event, context):
    """
    Process transformed requests from API Gateway.
    
    Args:
        event: API Gateway event with transformed data
        context: Lambda context object
    
    Returns:
        dict: Processed response data
    """
    try:
        # Log the transformed request for debugging
        logger.info(f"Received event: {json.dumps(event, default=str)}")
        
        # Process based on event structure
        if 'user_data' in event:
            response_data = _process_user_data(event, context)
        elif 'operation' in event:
            response_data = _process_operation(event, context)
        else:
            response_data = _process_generic_data(event, context)
        
        # Store processed data in S3 if configured
        if bucket_name and response_data.get('id'):
            _store_in_s3(response_data)
        
        return {
            'statusCode': 200,
            'body': response_data
        }
        
    except Exception as e:
        logger.error(f"Error processing request: {str(e)}")
        return {
            'statusCode': 500,
            'body': {
                'error': 'Internal processing error',
                'message': str(e),
                'request_id': context.aws_request_id
            }
        }

def _process_user_data(event, context):
    """Process user data from transformed request."""
    user_data = event['user_data']
    
    return {
        'id': str(uuid.uuid4()),
        'processed_at': datetime.utcnow().isoformat(),
        'user_id': user_data.get('id'),
        'full_name': f"{user_data.get('first_name', '')} {user_data.get('last_name', '')}".strip(),
        'profile': {
            'email': user_data.get('email'),
            'phone': user_data.get('phone'),
            'preferences': user_data.get('preferences', {})
        },
        'status': 'processed',
        'metadata': {
            'source': 'api_gateway_transformation',
            'version': '2.0',
            'request_context': event.get('request_context', {})
        }
    }

def _process_operation(event, context):
    """Process operation-based requests (like list operations)."""
    operation = event.get('operation')
    
    if operation == 'list_users':
        return {
            'id': str(uuid.uuid4()),
            'processed_at': datetime.utcnow().isoformat(),
            'operation': operation,
            'pagination': event.get('pagination', {}),
            'filters': event.get('filters', {}),
            'sorting': event.get('sorting', {}),
            'results': [
                {
                    'id': str(uuid.uuid4()),
                    'name': 'Sample User',
                    'email': 'user@example.com',
                    'created_at': datetime.utcnow().isoformat()
                }
            ],
            'total_count': 1,
            'status': 'success'
        }
    
    return {
        'id': str(uuid.uuid4()),
        'processed_at': datetime.utcnow().isoformat(),
        'operation': operation,
        'status': 'unknown_operation'
    }

def _process_generic_data(event, context):
    """Process generic data requests."""
    return {
        'id': str(uuid.uuid4()),
        'processed_at': datetime.utcnow().isoformat(),
        'input_data': event,
        'status': 'processed',
        'transformation_applied': True
    }

def _store_in_s3(data):
    """Store processed data in S3 bucket."""
    try:
        key = f"processed-data/{data['id']}.json"
        s3.put_object(
            Bucket=bucket_name,
            Key=key,
            Body=json.dumps(data, default=str),
            ContentType='application/json'
        )
        logger.info(f"Stored data in S3: {key}")
    except Exception as e:
        logger.error(f"Failed to store data in S3: {str(e)}")
'''

    def _create_api_gateway(self, unique_suffix: str) -> apigw.RestApi:
        """Create API Gateway with comprehensive configuration."""
        return apigw.RestApi(
            self,
            "TransformationAPI",
            rest_api_name=f"transformation-api-{unique_suffix}",
            description="API with advanced request/response transformation using VTL templates",
            deploy_options=apigw.StageOptions(
                stage_name="staging",
                logging_level=apigw.MethodLoggingLevel.INFO,
                data_trace_enabled=True,
                metrics_enabled=True,
                tracing_enabled=True,
            ),
            cloud_watch_role=True,
            endpoint_configuration=apigw.EndpointConfiguration(
                types=[apigw.EndpointType.REGIONAL]
            ),
            policy=iam.PolicyDocument(
                statements=[
                    iam.PolicyStatement(
                        effect=iam.Effect.ALLOW,
                        principals=[iam.AnyPrincipal()],
                        actions=["execute-api:Invoke"],
                        resources=["*"],
                    )
                ]
            ),
        )

    def _create_custom_models(self) -> None:
        """Create JSON Schema models for request/response validation."""
        # User creation request model
        self.user_request_model = self.api.add_model(
            "UserCreateRequest",
            content_type="application/json",
            schema=apigw.JsonSchema(
                schema=apigw.JsonSchemaVersion.DRAFT4,
                title="User Creation Request",
                type=apigw.JsonSchemaType.OBJECT,
                required=["firstName", "lastName", "email"],
                properties={
                    "firstName": apigw.JsonSchema(
                        type=apigw.JsonSchemaType.STRING,
                        min_length=1,
                        max_length=50,
                        pattern="^[a-zA-Z\\s]+$",
                    ),
                    "lastName": apigw.JsonSchema(
                        type=apigw.JsonSchemaType.STRING,
                        min_length=1,
                        max_length=50,
                        pattern="^[a-zA-Z\\s]+$",
                    ),
                    "email": apigw.JsonSchema(
                        type=apigw.JsonSchemaType.STRING,
                        format="email",
                        max_length=100,
                    ),
                    "phoneNumber": apigw.JsonSchema(
                        type=apigw.JsonSchemaType.STRING,
                        pattern="^\\+?[1-9]\\d{1,14}$",
                    ),
                    "preferences": apigw.JsonSchema(
                        type=apigw.JsonSchemaType.OBJECT,
                        properties={
                            "notifications": apigw.JsonSchema(
                                type=apigw.JsonSchemaType.BOOLEAN
                            ),
                            "theme": apigw.JsonSchema(
                                type=apigw.JsonSchemaType.STRING,
                                enum=["light", "dark"],
                            ),
                            "language": apigw.JsonSchema(
                                type=apigw.JsonSchemaType.STRING,
                                pattern="^[a-z]{2}$",
                            ),
                        },
                    ),
                    "metadata": apigw.JsonSchema(
                        type=apigw.JsonSchemaType.OBJECT,
                        additional_properties=True,
                    ),
                },
                additional_properties=False,
            ),
        )

        # User response model
        self.user_response_model = self.api.add_model(
            "UserResponse",
            content_type="application/json",
            schema=apigw.JsonSchema(
                schema=apigw.JsonSchemaVersion.DRAFT4,
                title="User Response",
                type=apigw.JsonSchemaType.OBJECT,
                properties={
                    "success": apigw.JsonSchema(type=apigw.JsonSchemaType.BOOLEAN),
                    "data": apigw.JsonSchema(
                        type=apigw.JsonSchemaType.OBJECT,
                        properties={
                            "userId": apigw.JsonSchema(type=apigw.JsonSchemaType.STRING),
                            "displayName": apigw.JsonSchema(type=apigw.JsonSchemaType.STRING),
                            "contactInfo": apigw.JsonSchema(
                                type=apigw.JsonSchemaType.OBJECT,
                                properties={
                                    "email": apigw.JsonSchema(type=apigw.JsonSchemaType.STRING),
                                    "phone": apigw.JsonSchema(type=apigw.JsonSchemaType.STRING),
                                },
                            ),
                            "createdAt": apigw.JsonSchema(type=apigw.JsonSchemaType.STRING),
                            "profileComplete": apigw.JsonSchema(type=apigw.JsonSchemaType.BOOLEAN),
                        },
                    ),
                    "links": apigw.JsonSchema(
                        type=apigw.JsonSchemaType.OBJECT,
                        properties={
                            "self": apigw.JsonSchema(type=apigw.JsonSchemaType.STRING),
                            "profile": apigw.JsonSchema(type=apigw.JsonSchemaType.STRING),
                        },
                    ),
                },
            ),
        )

        # Error response model
        self.error_response_model = self.api.add_model(
            "ErrorResponse",
            content_type="application/json",
            schema=apigw.JsonSchema(
                schema=apigw.JsonSchemaVersion.DRAFT4,
                title="Error Response",
                type=apigw.JsonSchemaType.OBJECT,
                required=["error", "message"],
                properties={
                    "error": apigw.JsonSchema(type=apigw.JsonSchemaType.STRING),
                    "message": apigw.JsonSchema(type=apigw.JsonSchemaType.STRING),
                    "details": apigw.JsonSchema(
                        type=apigw.JsonSchemaType.ARRAY,
                        items=apigw.JsonSchema(
                            type=apigw.JsonSchemaType.OBJECT,
                            properties={
                                "field": apigw.JsonSchema(type=apigw.JsonSchemaType.STRING),
                                "code": apigw.JsonSchema(type=apigw.JsonSchemaType.STRING),
                                "message": apigw.JsonSchema(type=apigw.JsonSchemaType.STRING),
                            },
                        ),
                    ),
                    "timestamp": apigw.JsonSchema(type=apigw.JsonSchemaType.STRING),
                    "path": apigw.JsonSchema(type=apigw.JsonSchemaType.STRING),
                },
            ),
        )

    def _create_api_resources(self) -> None:
        """Create API resources and request validator."""
        # Create request validator
        self.request_validator = apigw.RequestValidator(
            self,
            "ComprehensiveValidator",
            rest_api=self.api,
            request_validator_name="comprehensive-validator",
            validate_request_body=True,
            validate_request_parameters=True,
        )

        # Create /users resource
        self.users_resource = self.api.root.add_resource("users")

    def _configure_transformations(self) -> None:
        """Configure request/response transformations with VTL templates."""
        # Request transformation template for POST
        post_request_template = '''
#set($inputRoot = $input.path('$'))
#set($context = $context)
#set($util = $util)

## Transform incoming request to backend format
{
    "user_data": {
        "id": "$util.escapeJavaScript($context.requestId)",
        "first_name": "$util.escapeJavaScript($inputRoot.firstName)",
        "last_name": "$util.escapeJavaScript($inputRoot.lastName)",
        "email": "$util.escapeJavaScript($inputRoot.email.toLowerCase())",
        #if($inputRoot.phoneNumber && $inputRoot.phoneNumber != "")
        "phone": "$util.escapeJavaScript($inputRoot.phoneNumber)",
        #end
        #if($inputRoot.preferences)
        "preferences": {
            #if($inputRoot.preferences.notifications)
            "email_notifications": $inputRoot.preferences.notifications,
            #end
            #if($inputRoot.preferences.theme)
            "ui_theme": "$util.escapeJavaScript($inputRoot.preferences.theme)",
            #end
            #if($inputRoot.preferences.language)
            "locale": "$util.escapeJavaScript($inputRoot.preferences.language)",
            #end
            "auto_save": true
        },
        #end
        "source": "api_gateway",
        "created_via": "rest_api"
    },
    "request_context": {
        "request_id": "$context.requestId",
        "api_id": "$context.apiId",
        "stage": "$context.stage",
        "resource_path": "$context.resourcePath",
        "http_method": "$context.httpMethod",
        "source_ip": "$context.identity.sourceIp",
        "user_agent": "$util.escapeJavaScript($context.identity.userAgent)",
        "request_time": "$context.requestTime",
        "request_time_epoch": $context.requestTimeEpoch
    },
    #if($inputRoot.metadata)
    "additional_metadata": $input.json('$.metadata'),
    #end
    "processing_flags": {
        "validate_email": true,
        "send_welcome": true,
        "create_profile": true
    }
}
'''

        # Response transformation template for POST
        post_response_template = '''
#set($inputRoot = $input.path('$'))
#set($context = $context)

## Transform backend response to standardized API format
{
    "success": true,
    "data": {
        "userId": "$util.escapeJavaScript($inputRoot.id)",
        "displayName": "$util.escapeJavaScript($inputRoot.full_name)",
        "contactInfo": {
            #if($inputRoot.profile.email)
            "email": "$util.escapeJavaScript($inputRoot.profile.email)",
            #end
            #if($inputRoot.profile.phone)
            "phone": "$util.escapeJavaScript($inputRoot.profile.phone)"
            #end
        },
        "createdAt": "$util.escapeJavaScript($inputRoot.processed_at)",
        "profileComplete": #if($inputRoot.profile.email && $inputRoot.full_name != "")true#{else}false#end,
        "preferences": #if($inputRoot.profile.preferences)$input.json('$.profile.preferences')#{else}{}#end
    },
    "metadata": {
        "processingId": "$util.escapeJavaScript($inputRoot.id)",
        "version": #if($inputRoot.metadata.version)"$util.escapeJavaScript($inputRoot.metadata.version)"#{else}"1.0"#end,
        "processedAt": "$util.escapeJavaScript($inputRoot.processed_at)"
    },
    "links": {
        "self": "https://$context.domainName/$context.stage/users/$util.escapeJavaScript($inputRoot.id)",
        "profile": "https://$context.domainName/$context.stage/users/$util.escapeJavaScript($inputRoot.id)/profile"
    }
}
'''

        # Lambda integration for POST
        post_integration = apigw.LambdaIntegration(
            self.processor_function,
            passthrough_behavior=apigw.PassthroughBehavior.NEVER,
            request_templates={
                "application/json": post_request_template
            },
            integration_responses=[
                apigw.IntegrationResponse(
                    status_code="200",
                    response_templates={
                        "application/json": post_response_template
                    },
                ),
                apigw.IntegrationResponse(
                    status_code="500",
                    selection_pattern=r'.*"statusCode": 500.*',
                    response_templates={
                        "application/json": self._get_error_response_template()
                    },
                ),
            ],
        )

        # Create POST method
        self.users_resource.add_method(
            "POST",
            post_integration,
            request_validator=self.request_validator,
            request_models={"application/json": self.user_request_model},
            method_responses=[
                apigw.MethodResponse(
                    status_code="200",
                    response_models={"application/json": self.user_response_model},
                ),
                apigw.MethodResponse(
                    status_code="400",
                    response_models={"application/json": self.error_response_model},
                ),
                apigw.MethodResponse(
                    status_code="500",
                    response_models={"application/json": self.error_response_model},
                ),
            ],
        )

        # GET method with query parameter transformation
        get_request_template = '''
{
    "operation": "list_users",
    "pagination": {
        "limit": #if($input.params('limit'))$input.params('limit')#{else}10#end,
        "offset": #if($input.params('offset'))$input.params('offset')#{else}0#end
    },
    #if($input.params('filter'))
    "filters": {
        #set($filterParam = $input.params('filter'))
        #if($filterParam.contains(':'))
            #set($filterParts = $filterParam.split(':'))
            "$util.escapeJavaScript($filterParts[0])": "$util.escapeJavaScript($filterParts[1])"
        #else
            "search": "$util.escapeJavaScript($filterParam)"
        #end
    },
    #end
    #if($input.params('sort'))
    "sorting": {
        #set($sortParam = $input.params('sort'))
        #if($sortParam.startsWith('-'))
            "field": "$util.escapeJavaScript($sortParam.substring(1))",
            "direction": "desc"
        #else
            "field": "$util.escapeJavaScript($sortParam)",
            "direction": "asc"
        #end
    },
    #end
    "request_context": {
        "request_id": "$context.requestId",
        "source_ip": "$context.identity.sourceIp",
        "user_agent": "$util.escapeJavaScript($context.identity.userAgent)"
    }
}
'''

        # Lambda integration for GET
        get_integration = apigw.LambdaIntegration(
            self.processor_function,
            request_templates={
                "application/json": get_request_template
            },
        )

        # Create GET method
        self.users_resource.add_method(
            "GET",
            get_integration,
            request_parameters={
                "method.request.querystring.limit": False,
                "method.request.querystring.offset": False,
                "method.request.querystring.filter": False,
                "method.request.querystring.sort": False,
            },
        )

    def _get_error_response_template(self) -> str:
        """Get error response transformation template."""
        return '''
#set($inputRoot = $input.path('$.errorMessage'))
#set($context = $context)

{
    "error": "PROCESSING_ERROR",
    "message": #if($inputRoot)"$util.escapeJavaScript($inputRoot)"#{else}"An error occurred while processing your request"#end,
    "details": [
        {
            "field": "request",
            "code": "LAMBDA_EXECUTION_ERROR",
            "message": "Backend service encountered an error"
        }
    ],
    "timestamp": "$context.requestTime",
    "path": "$context.resourcePath",
    "requestId": "$context.requestId"
}
'''

    def _create_custom_error_responses(self) -> None:
        """Create custom gateway responses for error handling."""
        # Validation error response
        validation_error_template = '''
{
    "error": "VALIDATION_ERROR",
    "message": "Request validation failed",
    "details": [
        #foreach($error in $context.error.validationErrorString.split(','))
        {
            "field": #if($error.contains('Invalid request body'))"body"#{elseif($error.contains('required'))$error.split("'")[1]#{else}"unknown"#end,
            "code": "VALIDATION_FAILED",
            "message": "$util.escapeJavaScript($error.trim())"
        }#if($foreach.hasNext),#end
        #end
    ],
    "timestamp": "$context.requestTime",
    "path": "$context.resourcePath",
    "requestId": "$context.requestId"
}
'''

        # Bad request body gateway response
        self.api.add_gateway_response(
            "BadRequestBodyResponse",
            type=apigw.ResponseType.BAD_REQUEST_BODY,
            status_code=400,
            response_headers={
                "Content-Type": "application/json",
            },
            templates={
                "application/json": validation_error_template
            },
        )

        # Unauthorized gateway response
        self.api.add_gateway_response(
            "UnauthorizedResponse",
            type=apigw.ResponseType.UNAUTHORIZED,
            status_code=401,
            response_headers={
                "Content-Type": "application/json",
            },
            templates={
                "application/json": '''
{
    "error": "UNAUTHORIZED",
    "message": "Authentication required",
    "timestamp": "$context.requestTime",
    "path": "$context.resourcePath"
}
'''
            },
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for the stack."""
        CfnOutput(
            self,
            "APIEndpoint",
            value=self.api.url,
            description="API Gateway endpoint URL",
        )

        CfnOutput(
            self,
            "APIId",
            value=self.api.rest_api_id,
            description="API Gateway REST API ID",
        )

        CfnOutput(
            self,
            "LambdaFunctionArn",
            value=self.processor_function.function_arn,
            description="Lambda function ARN",
        )

        CfnOutput(
            self,
            "S3BucketName",
            value=self.data_bucket.bucket_name,
            description="S3 bucket name for data storage",
        )

        CfnOutput(
            self,
            "UsersEndpoint",
            value=f"{self.api.url}users",
            description="Users resource endpoint",
        )


class RequestResponseTransformationApp(cdk.App):
    """CDK Application for request/response transformation."""

    def __init__(self, **kwargs):
        super().__init__(**kwargs)

        # Get context values
        unique_suffix = self.node.try_get_context("unique_suffix")
        if not unique_suffix:
            import secrets
            unique_suffix = secrets.token_hex(3)
            self.node.set_context("unique_suffix", unique_suffix)

        # Create the main stack
        RequestResponseTransformationStack(
            self,
            "RequestResponseTransformationStack",
            description="CDK stack for Transforming API Requests with VTL Templates",
            env=cdk.Environment(
                account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
                region=os.environ.get("CDK_DEFAULT_REGION"),
            ),
        )


# Create and run the CDK application
app = RequestResponseTransformationApp()
app.synth()