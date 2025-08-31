#!/usr/bin/env python3
"""
Enterprise API Integration with AgentCore Gateway and Step Functions

This CDK application creates a comprehensive API integration system using:
- Amazon API Gateway for external API endpoints
- AWS Lambda functions for data transformation and validation
- AWS Step Functions for workflow orchestration
- IAM roles with least privilege permissions
- CloudWatch monitoring and logging

The architecture follows AWS best practices for serverless applications
and provides a scalable foundation for enterprise API integration.
"""

import os
from typing import Optional

import aws_cdk as cdk
from aws_cdk import (
    aws_apigateway as apigateway,
    aws_iam as iam,
    aws_lambda as _lambda,
    aws_stepfunctions as sfn,
    aws_stepfunctions_tasks as sfn_tasks,
    aws_logs as logs,
    CfnOutput,
    Duration,
    RemovalPolicy,
    Stack,
    StackProps,
)
from constructs import Construct


class ApiIntegrationStack(Stack):
    """
    Main stack for the API Integration with AgentCore Gateway solution.
    
    This stack creates all the necessary AWS resources for enterprise API integration
    including Lambda functions, Step Functions state machine, API Gateway, and
    associated IAM roles and policies.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Environment variables for customization
        self.project_name = os.environ.get("PROJECT_NAME", "api-integration")
        self.environment = os.environ.get("ENVIRONMENT", "dev")
        
        # Create Lambda execution role with basic permissions
        self.lambda_execution_role = self._create_lambda_execution_role()
        
        # Create Step Functions execution role
        self.stepfunctions_execution_role = self._create_stepfunctions_execution_role()
        
        # Create API Gateway execution role
        self.apigateway_execution_role = self._create_apigateway_execution_role()
        
        # Create Lambda functions for data processing
        self.api_transformer_function = self._create_api_transformer_function()
        self.data_validator_function = self._create_data_validator_function()
        
        # Create Step Functions state machine for orchestration
        self.state_machine = self._create_orchestration_state_machine()
        
        # Create API Gateway for external access
        self.api_gateway = self._create_api_gateway()
        
        # Create CloudWatch Log Groups for monitoring
        self._create_log_groups()
        
        # Output important resource identifiers
        self._create_outputs()

    def _create_lambda_execution_role(self) -> iam.Role:
        """
        Create IAM role for Lambda function execution with least privilege permissions.
        
        Returns:
            iam.Role: The Lambda execution role with appropriate policies attached
        """
        role = iam.Role(
            self,
            "LambdaExecutionRole",
            role_name=f"{self.project_name}-lambda-execution-role-{self.environment}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Execution role for Lambda functions in API integration solution",
        )

        # Attach basic Lambda execution policy
        role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name(
                "service-role/AWSLambdaBasicExecutionRole"
            )
        )

        # Add CloudWatch Logs permissions for enhanced monitoring
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents",
                    "logs:DescribeLogGroups",
                    "logs:DescribeLogStreams",
                ],
                resources=[
                    f"arn:aws:logs:{self.region}:{self.account}:*"
                ],
            )
        )

        return role

    def _create_stepfunctions_execution_role(self) -> iam.Role:
        """
        Create IAM role for Step Functions execution with permissions to invoke Lambda.
        
        Returns:
            iam.Role: The Step Functions execution role
        """
        role = iam.Role(
            self,
            "StepFunctionsExecutionRole",
            role_name=f"{self.project_name}-stepfunctions-execution-role-{self.environment}",
            assumed_by=iam.ServicePrincipal("states.amazonaws.com"),
            description="Execution role for Step Functions state machine in API integration solution",
        )

        # Add permissions to invoke Lambda functions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "lambda:InvokeFunction",
                ],
                resources=[
                    f"arn:aws:lambda:{self.region}:{self.account}:function:{self.project_name}-*"
                ],
            )
        )

        # Add CloudWatch Logs permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "logs:CreateLogDelivery",
                    "logs:GetLogDelivery",
                    "logs:UpdateLogDelivery",
                    "logs:DeleteLogDelivery",
                    "logs:ListLogDeliveries",
                    "logs:PutResourcePolicy",
                    "logs:DescribeResourcePolicies",
                    "logs:DescribeLogGroups",
                ],
                resources=["*"],
            )
        )

        return role

    def _create_apigateway_execution_role(self) -> iam.Role:
        """
        Create IAM role for API Gateway to invoke Step Functions.
        
        Returns:
            iam.Role: The API Gateway execution role
        """
        role = iam.Role(
            self,
            "ApiGatewayExecutionRole",
            role_name=f"{self.project_name}-apigateway-stepfunctions-role-{self.environment}",
            assumed_by=iam.ServicePrincipal("apigateway.amazonaws.com"),
            description="Execution role for API Gateway to invoke Step Functions",
        )

        # Add permissions to start Step Functions executions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "states:StartExecution",
                ],
                resources=[
                    f"arn:aws:states:{self.region}:{self.account}:stateMachine:{self.project_name}-*"
                ],
            )
        )

        return role

    def _create_api_transformer_function(self) -> _lambda.Function:
        """
        Create Lambda function for API request transformation.
        
        Returns:
            _lambda.Function: The API transformer Lambda function
        """
        # Lambda function code for API transformation
        transformer_code = '''
import json
import urllib3
from typing import Dict, Any

# Initialize urllib3 PoolManager for HTTP requests
http = urllib3.PoolManager()

def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    Transform API requests for enterprise system integration
    """
    try:
        # Extract request parameters
        api_type = event.get('api_type', 'generic')
        payload = event.get('payload', {})
        target_url = event.get('target_url')
        
        # Transform based on API type
        if api_type == 'erp':
            transformed_data = transform_erp_request(payload)
        elif api_type == 'crm':
            transformed_data = transform_crm_request(payload)
        else:
            transformed_data = payload
        
        # Simulate API call to target system (using mock response)
        # In production, this would make actual HTTP requests to enterprise APIs
        mock_response = {
            'success': True,
            'transaction_id': f"{api_type}-{payload.get('id', 'unknown')}",
            'processed_data': transformed_data,
            'status': 'completed'
        }
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'success': True,
                'data': mock_response,
                'status_code': 200
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({
                'success': False,
                'error': str(e)
            })
        }

def transform_erp_request(payload: Dict[str, Any]) -> Dict[str, Any]:
    """Transform requests for ERP system format"""
    return {
        'transaction_type': payload.get('type', 'query'),
        'data': payload.get('data', {}),
        'metadata': {
            'source': 'agentcore_gateway',
            'timestamp': payload.get('timestamp')
        }
    }

def transform_crm_request(payload: Dict[str, Any]) -> Dict[str, Any]:
    """Transform requests for CRM system format"""
    return {
        'operation': payload.get('action', 'read'),
        'entity': payload.get('entity', 'contact'),
        'attributes': payload.get('data', {}),
        'source_system': 'ai_agent'
    }
'''

        function = _lambda.Function(
            self,
            "ApiTransformerFunction",
            function_name=f"{self.project_name}-api-transformer-{self.environment}",
            runtime=_lambda.Runtime.PYTHON_3_12,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline(transformer_code),
            role=self.lambda_execution_role,
            timeout=Duration.seconds(60),
            memory_size=512,
            description="Transform API requests for enterprise system integration",
            environment={
                "ENVIRONMENT": self.environment,
                "LOG_LEVEL": "INFO",
                "PROJECT_NAME": self.project_name,
            },
        )

        return function

    def _create_data_validator_function(self) -> _lambda.Function:
        """
        Create Lambda function for data validation.
        
        Returns:
            _lambda.Function: The data validator Lambda function
        """
        # Lambda function code for data validation
        validator_code = '''
import json
import re
from typing import Dict, Any, List

def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    Validate API request data according to enterprise rules
    """
    try:
        data = event.get('data', {})
        validation_type = event.get('validation_type', 'standard')
        
        # Perform validation based on type
        validation_result = validate_data(data, validation_type)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'valid': validation_result['is_valid'],
                'errors': validation_result['errors'],
                'sanitized_data': validation_result['sanitized_data']
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({
                'valid': False,
                'errors': [f"Validation error: {str(e)}"]
            })
        }

def validate_data(data: Dict[str, Any], validation_type: str) -> Dict[str, Any]:
    """Perform comprehensive data validation"""
    errors = []
    sanitized_data = {}
    
    # Standard validation rules
    if validation_type == 'standard':
        errors.extend(validate_required_fields(data))
        errors.extend(validate_data_types(data))
        sanitized_data = sanitize_data(data)
    
    # Financial data validation
    elif validation_type == 'financial':
        errors.extend(validate_required_fields(data))
        errors.extend(validate_financial_data(data))
        sanitized_data = sanitize_financial_data(data)
    
    # Customer data validation
    elif validation_type == 'customer':
        errors.extend(validate_required_fields(data))
        errors.extend(validate_customer_data(data))
        sanitized_data = sanitize_customer_data(data)
    
    return {
        'is_valid': len(errors) == 0,
        'errors': errors,
        'sanitized_data': sanitized_data
    }

def validate_required_fields(data: Dict[str, Any]) -> List[str]:
    """Validate required field presence"""
    errors = []
    required_fields = ['id', 'type', 'data']
    
    for field in required_fields:
        if field not in data or data[field] is None:
            errors.append(f"Required field '{field}' is missing")
    
    return errors

def validate_data_types(data: Dict[str, Any]) -> List[str]:
    """Validate data type constraints"""
    errors = []
    
    if 'id' in data and not isinstance(data['id'], (str, int)):
        errors.append("Field 'id' must be string or integer")
    
    if 'type' in data and not isinstance(data['type'], str):
        errors.append("Field 'type' must be string")
    
    return errors

def validate_financial_data(data: Dict[str, Any]) -> List[str]:
    """Validate financial-specific data"""
    errors = []
    
    if 'amount' in data:
        try:
            amount = float(data['amount'])
            if amount < 0:
                errors.append("Amount cannot be negative")
            if amount > 1000000:
                errors.append("Amount exceeds maximum limit")
        except (ValueError, TypeError):
            errors.append("Amount must be a valid number")
    
    return errors

def validate_customer_data(data: Dict[str, Any]) -> List[str]:
    """Validate customer-specific data"""
    errors = []
    
    if 'email' in data:
        email_pattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$'
        if not re.match(email_pattern, data['email']):
            errors.append("Invalid email format")
    
    if 'phone' in data:
        phone_pattern = r'^\\+?[\\d\\s\\-\\(\\)]{10,}$'
        if not re.match(phone_pattern, str(data['phone'])):
            errors.append("Invalid phone number format")
    
    return errors

def sanitize_data(data: Dict[str, Any]) -> Dict[str, Any]:
    """Sanitize and clean data"""
    sanitized = {}
    for key, value in data.items():
        if isinstance(value, str):
            sanitized[key] = value.strip()
        else:
            sanitized[key] = value
    return sanitized

def sanitize_financial_data(data: Dict[str, Any]) -> Dict[str, Any]:
    """Sanitize financial-specific data"""
    sanitized = sanitize_data(data)
    if 'amount' in sanitized:
        try:
            sanitized['amount'] = round(float(sanitized['amount']), 2)
        except (ValueError, TypeError):
            pass
    return sanitized

def sanitize_customer_data(data: Dict[str, Any]) -> Dict[str, Any]:
    """Sanitize customer-specific data"""
    sanitized = sanitize_data(data)
    if 'email' in sanitized:
        sanitized['email'] = sanitized['email'].lower()
    return sanitized
'''

        function = _lambda.Function(
            self,
            "DataValidatorFunction",
            function_name=f"{self.project_name}-data-validator-{self.environment}",
            runtime=_lambda.Runtime.PYTHON_3_12,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline(validator_code),
            role=self.lambda_execution_role,
            timeout=Duration.seconds(30),
            memory_size=256,
            description="Validate API request data according to enterprise rules",
            environment={
                "ENVIRONMENT": self.environment,
                "LOG_LEVEL": "INFO",
                "PROJECT_NAME": self.project_name,
            },
        )

        return function

    def _create_orchestration_state_machine(self) -> sfn.StateMachine:
        """
        Create Step Functions state machine for API orchestration.
        
        Returns:
            sfn.StateMachine: The orchestration state machine
        """
        # Define validation task
        validate_input_task = sfn_tasks.LambdaInvoke(
            self,
            "ValidateInput",
            lambda_function=self.data_validator_function,
            output_path="$.Payload",
            retry_on_service_exceptions=True,
        )

        # Define choice condition for validation results
        validation_choice = sfn.Choice(self, "CheckValidation")
        
        # Define transformation tasks for different API types
        transform_erp_task = sfn_tasks.LambdaInvoke(
            self,
            "TransformForERP",
            lambda_function=self.api_transformer_function,
            payload=sfn.TaskInput.from_object({
                "api_type": "erp",
                "payload": sfn.JsonPath.entire_payload,
                "target_url": "https://example-erp.com/api/v1/process",
            }),
            retry_on_service_exceptions=True,
        )

        transform_crm_task = sfn_tasks.LambdaInvoke(
            self,
            "TransformForCRM",
            lambda_function=self.api_transformer_function,
            payload=sfn.TaskInput.from_object({
                "api_type": "crm",
                "payload": sfn.JsonPath.entire_payload,
                "target_url": "https://example-crm.com/api/v2/entities",
            }),
            retry_on_service_exceptions=True,
        )

        # Define parallel processing for multiple API calls
        parallel_processing = sfn.Parallel(
            self,
            "RouteRequest",
            comment="Process API requests in parallel across multiple enterprise systems",
        )
        parallel_processing.branch(transform_erp_task)
        parallel_processing.branch(transform_crm_task)

        # Define success and failure states
        aggregate_results = sfn.Pass(
            self,
            "AggregateResults",
            parameters={
                "status": "success",
                "results": sfn.JsonPath.entire_payload,
                "timestamp": sfn.JsonPath.string_at("$$.State.EnteredTime"),
                "execution_arn": sfn.JsonPath.string_at("$$.Execution.Name"),
            },
        )

        validation_failed = sfn.Pass(
            self,
            "ValidationFailed",
            parameters={
                "status": "validation_failed",
                "errors": sfn.JsonPath.string_at("$.errors"),
                "timestamp": sfn.JsonPath.string_at("$$.State.EnteredTime"),
            },
        )

        processing_failed = sfn.Pass(
            self,
            "ProcessingFailed",
            parameters={
                "status": "processing_failed",
                "error": sfn.JsonPath.string_at("$.Error"),
                "timestamp": sfn.JsonPath.string_at("$$.State.EnteredTime"),
            },
        )

        # Define the workflow chain
        definition = (
            validate_input_task
            .next(
                validation_choice
                .when(
                    sfn.Condition.string_matches("$.body", "*\"valid\":true*"),
                    parallel_processing.next(aggregate_results)
                )
                .otherwise(validation_failed)
            )
        )

        # Add error handling for processing failures
        parallel_processing.add_catch(
            processing_failed,
            errors=["States.ALL"],
            result_path="$.error"
        )

        # Create the state machine
        state_machine = sfn.StateMachine(
            self,
            "OrchestrationStateMachine",
            state_machine_name=f"{self.project_name}-api-orchestrator-{self.environment}",
            definition=definition,
            role=self.stepfunctions_execution_role,
            timeout=Duration.minutes(5),
            comment="Enterprise API Integration Orchestration Workflow",
        )

        return state_machine

    def _create_api_gateway(self) -> apigateway.RestApi:
        """
        Create API Gateway for external access to the integration workflow.
        
        Returns:
            apigateway.RestApi: The API Gateway REST API
        """
        # Create the REST API
        api = apigateway.RestApi(
            self,
            "EnterpriseApiIntegration",
            rest_api_name=f"{self.project_name}-enterprise-api-integration-{self.environment}",
            description="Enterprise API Integration with AgentCore Gateway",
            endpoint_configuration=apigateway.EndpointConfiguration(
                types=[apigateway.EndpointType.REGIONAL]
            ),
            deploy_options=apigateway.StageOptions(
                stage_name="prod",
                throttling_rate_limit=1000,
                throttling_burst_limit=2000,
                logging_level=apigateway.MethodLoggingLevel.INFO,
                data_trace_enabled=True,
                metrics_enabled=True,
            ),
        )

        # Create integration resource
        integration_resource = api.root.add_resource("integrate")

        # Create Step Functions integration
        stepfunctions_integration = apigateway.AwsIntegration(
            service="states",
            action="StartExecution",
            integration_http_method="POST",
            options=apigateway.IntegrationOptions(
                credentials_role=self.apigateway_execution_role,
                request_templates={
                    "application/json": f'''{{
                        "input": "$util.escapeJavaScript($input.body)",
                        "stateMachineArn": "{self.state_machine.state_machine_arn}"
                    }}'''
                },
                integration_responses=[
                    apigateway.IntegrationResponse(
                        status_code="200",
                        response_templates={
                            "application/json": '''{{
                                "executionArn": "$input.path('$.executionArn')",
                                "startDate": "$input.path('$.startDate')",
                                "status": "STARTED"
                            }}'''
                        },
                    )
                ],
            ),
        )

        # Add POST method to the integration resource
        integration_resource.add_method(
            "POST",
            stepfunctions_integration,
            method_responses=[
                apigateway.MethodResponse(
                    status_code="200",
                    response_models={
                        "application/json": apigateway.Model.EMPTY_MODEL
                    },
                )
            ],
        )

        return api

    def _create_log_groups(self) -> None:
        """
        Create CloudWatch Log Groups for monitoring and observability.
        """
        # Log group for API Gateway
        logs.LogGroup(
            self,
            "ApiGatewayLogGroup",
            log_group_name=f"/aws/apigateway/{self.project_name}-{self.environment}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )

        # Log group for Step Functions
        logs.LogGroup(
            self,
            "StepFunctionsLogGroup",
            log_group_name=f"/aws/stepfunctions/{self.project_name}-{self.environment}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )

    def _create_outputs(self) -> None:
        """
        Create CloudFormation outputs for important resource identifiers.
        """
        CfnOutput(
            self,
            "ApiEndpoint",
            description="API Gateway endpoint URL for integration",
            value=f"{self.api_gateway.url}integrate",
        )

        CfnOutput(
            self,
            "StateMachineArn",
            description="Step Functions state machine ARN",
            value=self.state_machine.state_machine_arn,
        )

        CfnOutput(
            self,
            "ApiTransformerFunctionName",
            description="API transformer Lambda function name",
            value=self.api_transformer_function.function_name,
        )

        CfnOutput(
            self,
            "DataValidatorFunctionName",
            description="Data validator Lambda function name",
            value=self.data_validator_function.function_name,
        )

        CfnOutput(
            self,
            "ApiGatewayId",
            description="API Gateway REST API ID",
            value=self.api_gateway.rest_api_id,
        )


# CDK App initialization
app = cdk.App()

# Get environment configuration
project_name = app.node.try_get_context("project_name") or "api-integration"
environment = app.node.try_get_context("environment") or "dev"

# Set environment variables for the stack
os.environ["PROJECT_NAME"] = project_name
os.environ["ENVIRONMENT"] = environment

# Create the main stack
ApiIntegrationStack(
    app,
    f"ApiIntegrationStack-{environment}",
    description="Enterprise API Integration with AgentCore Gateway and Step Functions",
    env=cdk.Environment(
        account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
        region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
    ),
)

# Synthesize the CDK app
app.synth()