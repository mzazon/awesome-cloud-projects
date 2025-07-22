#!/usr/bin/env python3
"""
CDK application for Conversational AI with Amazon Bedrock and Claude.

This application deploys a complete conversational AI solution that includes:
- DynamoDB table for conversation history storage
- Lambda function for conversational AI processing
- API Gateway for REST API access
- IAM roles and policies with least privilege
- CloudWatch monitoring and X-Ray tracing

The solution enables building scalable conversational AI applications using
Amazon Bedrock's Claude models without managing infrastructure complexity.
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    aws_lambda as _lambda,
    aws_apigateway as apigateway,
    aws_dynamodb as dynamodb,
    aws_iam as iam,
    aws_logs as logs,
    CfnOutput,
)
from constructs import Construct


class ConversationalAIStack(Stack):
    """
    CDK Stack for Conversational AI application using Amazon Bedrock and Claude.
    
    This stack creates all necessary AWS resources for a production-ready
    conversational AI application with proper security, monitoring, and scaling.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Parameters for customization
        self.claude_model_id = cdk.CfnParameter(
            self,
            "ClaudeModelId",
            type="String",
            default="anthropic.claude-3-haiku-20240307-v1:0",
            description="The Claude model ID to use for conversations",
            allowed_values=[
                "anthropic.claude-3-haiku-20240307-v1:0",
                "anthropic.claude-3-sonnet-20240229-v1:0",
                "anthropic.claude-3-opus-20240229-v1:0",
                "anthropic.claude-v2:1",
                "anthropic.claude-v2",
                "anthropic.claude-instant-v1"
            ]
        )

        self.max_tokens = cdk.CfnParameter(
            self,
            "MaxTokens",
            type="Number",
            default=1000,
            min_value=1,
            max_value=4000,
            description="Maximum number of tokens for Claude responses"
        )

        self.temperature = cdk.CfnParameter(
            self,
            "Temperature",
            type="Number",
            default=0.7,
            min_value=0.0,
            max_value=1.0,
            description="Temperature setting for Claude model (0.0-1.0)"
        )

        # Create DynamoDB table for conversation storage
        self.create_conversation_table()
        
        # Create IAM role for Lambda function
        self.create_lambda_role()
        
        # Create Lambda function for conversational AI
        self.create_lambda_function()
        
        # Create API Gateway for REST API access
        self.create_api_gateway()
        
        # Create CloudWatch Log Group for API Gateway
        self.create_api_logs()
        
        # Create outputs for easy access to resources
        self.create_outputs()

    def create_conversation_table(self) -> None:
        """
        Create DynamoDB table for storing conversation history.
        
        The table uses a composite key with session_id as partition key
        and timestamp as sort key for efficient querying and ordering.
        """
        self.conversation_table = dynamodb.Table(
            self,
            "ConversationTable",
            table_name=f"conversational-ai-{self.account}-{self.region}",
            partition_key=dynamodb.Attribute(
                name="session_id",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="timestamp",
                type=dynamodb.AttributeType.NUMBER
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            encryption=dynamodb.TableEncryption.AWS_MANAGED,
            point_in_time_recovery=True,
            removal_policy=RemovalPolicy.DESTROY,  # Use RETAIN for production
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES
        )

        # Add Global Secondary Index for user-based queries
        self.conversation_table.add_global_secondary_index(
            index_name="UserIndex",
            partition_key=dynamodb.Attribute(
                name="user_id",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="timestamp",
                type=dynamodb.AttributeType.NUMBER
            )
        )

        # Add tags for resource management
        cdk.Tags.of(self.conversation_table).add("Component", "ConversationStorage")
        cdk.Tags.of(self.conversation_table).add("Environment", "Development")

    def create_lambda_role(self) -> None:
        """
        Create IAM role for Lambda function with least privilege permissions.
        
        The role includes permissions for:
        - Bedrock model invocation
        - DynamoDB read/write operations
        - CloudWatch logging
        - X-Ray tracing
        """
        self.lambda_role = iam.Role(
            self,
            "ConversationalAILambdaRole",
            role_name=f"ConversationalAI-Lambda-Role-{self.region}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="IAM role for Conversational AI Lambda function",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                ),
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "AWSXRayDaemonWriteAccess"
                )
            ]
        )

        # Add Bedrock permissions
        self.lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "bedrock:InvokeModel",
                    "bedrock:InvokeModelWithResponseStream"
                ],
                resources=[
                    f"arn:aws:bedrock:{self.region}::foundation-model/*"
                ]
            )
        )

        # Add DynamoDB permissions
        self.lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "dynamodb:GetItem",
                    "dynamodb:PutItem",
                    "dynamodb:Query",
                    "dynamodb:UpdateItem",
                    "dynamodb:DeleteItem"
                ],
                resources=[
                    self.conversation_table.table_arn,
                    f"{self.conversation_table.table_arn}/index/*"
                ]
            )
        )

    def create_lambda_function(self) -> None:
        """
        Create Lambda function for conversational AI processing.
        
        The function handles:
        - Request parsing and validation
        - Conversation history retrieval
        - Bedrock model invocation
        - Response processing and storage
        """
        # Create CloudWatch Log Group for Lambda
        lambda_log_group = logs.LogGroup(
            self,
            "ConversationalAILambdaLogGroup",
            log_group_name=f"/aws/lambda/conversational-ai-handler-{self.account}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY
        )

        self.lambda_function = _lambda.Function(
            self,
            "ConversationalAIFunction",
            function_name=f"conversational-ai-handler-{self.account}",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="conversational_ai_handler.lambda_handler",
            code=_lambda.Code.from_inline(self._get_lambda_code()),
            timeout=Duration.seconds(30),
            memory_size=512,
            role=self.lambda_role,
            environment={
                "TABLE_NAME": self.conversation_table.table_name,
                "CLAUDE_MODEL_ID": self.claude_model_id.value_as_string,
                "MAX_TOKENS": self.max_tokens.value_as_string,
                "TEMPERATURE": self.temperature.value_as_string,
                "AWS_REGION": self.region
            },
            tracing=_lambda.Tracing.ACTIVE,
            log_group=lambda_log_group,
            description="Conversational AI handler using Amazon Bedrock and Claude"
        )

        # Add tags for resource management
        cdk.Tags.of(self.lambda_function).add("Component", "ConversationalAI")
        cdk.Tags.of(self.lambda_function).add("Environment", "Development")

    def create_api_gateway(self) -> None:
        """
        Create API Gateway for REST API access to conversational AI.
        
        The API provides:
        - RESTful endpoints for chat functionality
        - CORS support for web applications
        - Request/response validation
        - Throttling and rate limiting
        """
        self.api = apigateway.RestApi(
            self,
            "ConversationalAIAPI",
            rest_api_name="Conversational AI API",
            description="RESTful API for conversational AI using Amazon Bedrock and Claude",
            default_cors_preflight_options=apigateway.CorsOptions(
                allow_origins=apigateway.Cors.ALL_ORIGINS,
                allow_methods=apigateway.Cors.ALL_METHODS,
                allow_headers=["Content-Type", "X-Amz-Date", "Authorization", "X-Api-Key"]
            ),
            endpoint_configuration=apigateway.EndpointConfiguration(
                types=[apigateway.EndpointType.REGIONAL]
            ),
            cloud_watch_role=True,
            deploy_options=apigateway.StageOptions(
                stage_name="prod",
                description="Production stage for Conversational AI API",
                logging_level=apigateway.MethodLoggingLevel.INFO,
                data_trace_enabled=True,
                metrics_enabled=True,
                throttling_rate_limit=1000,
                throttling_burst_limit=2000
            )
        )

        # Create Lambda integration
        lambda_integration = apigateway.LambdaIntegration(
            self.lambda_function,
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

        # Create /chat resource
        chat_resource = self.api.root.add_resource("chat")
        
        # Add POST method for chat functionality
        chat_resource.add_method(
            "POST",
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

        # Create /health resource for health checks
        health_resource = self.api.root.add_resource("health")
        health_resource.add_method(
            "GET",
            apigateway.MockIntegration(
                integration_responses=[
                    apigateway.IntegrationResponse(
                        status_code="200",
                        response_templates={
                            "application/json": '{"status": "healthy", "timestamp": "$context.requestTime"}'
                        }
                    )
                ],
                request_templates={
                    "application/json": '{"statusCode": 200}'
                }
            ),
            method_responses=[
                apigateway.MethodResponse(status_code="200")
            ]
        )

    def create_api_logs(self) -> None:
        """Create CloudWatch Log Group for API Gateway access logs."""
        self.api_log_group = logs.LogGroup(
            self,
            "ConversationalAIAPILogGroup",
            log_group_name=f"/aws/apigateway/conversational-ai-{self.account}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY
        )

    def create_outputs(self) -> None:
        """Create CloudFormation outputs for easy access to resources."""
        CfnOutput(
            self,
            "APIEndpoint",
            value=self.api.url,
            description="API Gateway endpoint URL for conversational AI",
            export_name=f"ConversationalAI-API-Endpoint-{self.account}"
        )

        CfnOutput(
            self,
            "ChatEndpoint",
            value=f"{self.api.url}chat",
            description="Chat endpoint for conversational AI requests",
            export_name=f"ConversationalAI-Chat-Endpoint-{self.account}"
        )

        CfnOutput(
            self,
            "DynamoDBTableName",
            value=self.conversation_table.table_name,
            description="DynamoDB table name for conversation storage",
            export_name=f"ConversationalAI-Table-Name-{self.account}"
        )

        CfnOutput(
            self,
            "LambdaFunctionName",
            value=self.lambda_function.function_name,
            description="Lambda function name for conversational AI",
            export_name=f"ConversationalAI-Lambda-Name-{self.account}"
        )

        CfnOutput(
            self,
            "LambdaFunctionArn",
            value=self.lambda_function.function_arn,
            description="Lambda function ARN for conversational AI",
            export_name=f"ConversationalAI-Lambda-ARN-{self.account}"
        )

    def _get_lambda_code(self) -> str:
        """
        Return the Lambda function code as a string.
        
        In production, this would typically be loaded from a separate file
        or built as a deployment package.
        """
        return '''
import json
import boto3
import uuid
import time
import os
from datetime import datetime
import logging
from typing import Dict, List, Any, Optional

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
bedrock_runtime = boto3.client('bedrock-runtime')
dynamodb = boto3.resource('dynamodb')

# Environment variables
TABLE_NAME = os.environ['TABLE_NAME']
CLAUDE_MODEL_ID = os.environ['CLAUDE_MODEL_ID']
MAX_TOKENS = int(os.environ.get('MAX_TOKENS', '1000'))
TEMPERATURE = float(os.environ.get('TEMPERATURE', '0.7'))

table = dynamodb.Table(TABLE_NAME)


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """Main handler for conversational AI requests."""
    
    try:
        # Handle CORS preflight requests
        if event.get('httpMethod') == 'OPTIONS':
            return {
                'statusCode': 200,
                'headers': {
                    'Access-Control-Allow-Origin': '*',
                    'Access-Control-Allow-Methods': 'POST, OPTIONS',
                    'Access-Control-Allow-Headers': 'Content-Type'
                },
                'body': ''
            }
        
        # Parse request body from API Gateway
        body = json.loads(event.get('body', '{}'))
        user_message = body.get('message', '').strip()
        session_id = body.get('session_id', str(uuid.uuid4()))
        user_id = body.get('user_id', 'anonymous')
        
        # Validate required fields
        if not user_message:
            return create_error_response(400, 'Message is required')
        
        # Get conversation history for context
        conversation_history = get_conversation_history(session_id)
        
        # Build prompt with conversation context
        messages = build_prompt_with_context(user_message, conversation_history)
        
        # Call Bedrock Claude model for AI response
        response = invoke_claude_model(messages)
        
        if not response:
            return create_error_response(500, 'Failed to generate AI response')
        
        # Save this conversation turn to DynamoDB
        save_conversation_turn(session_id, user_id, user_message, response)
        
        # Return successful response
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'POST, OPTIONS',
                'Access-Control-Allow-Headers': 'Content-Type'
            },
            'body': json.dumps({
                'response': response,
                'session_id': session_id,
                'timestamp': datetime.utcnow().isoformat(),
                'model_id': CLAUDE_MODEL_ID
            })
        }
        
    except json.JSONDecodeError:
        logger.error("Invalid JSON in request body")
        return create_error_response(400, 'Invalid JSON format')
    except Exception as e:
        logger.error(f"Error processing request: {str(e)}")
        return create_error_response(500, 'Internal server error')


def create_error_response(status_code: int, message: str) -> Dict[str, Any]:
    """Create standardized error response."""
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps({
            'error': message,
            'timestamp': datetime.utcnow().isoformat()
        })
    }


def get_conversation_history(session_id: str, limit: int = 10) -> List[Dict[str, str]]:
    """Retrieve recent conversation history for context."""
    
    try:
        response = table.query(
            KeyConditionExpression='session_id = :session_id',
            ExpressionAttributeValues={':session_id': session_id},
            ScanIndexForward=False,  # Most recent first
            Limit=limit * 2  # Get both user and assistant messages
        )
        
        # Format conversation history
        history = []
        for item in reversed(response['Items']):
            history.append({
                'role': item['role'],
                'content': item['content']
            })
        
        return history[-limit:] if len(history) > limit else history
        
    except Exception as e:
        logger.error(f"Error retrieving conversation history: {str(e)}")
        return []


def build_prompt_with_context(user_message: str, conversation_history: List[Dict[str, str]]) -> List[Dict[str, str]]:
    """Build Claude prompt with conversation context."""
    
    # System prompt defines the AI's behavior and personality
    system_prompt = """You are a helpful AI assistant powered by Claude. You provide accurate, helpful, and engaging responses to user questions. You maintain context from previous messages in the conversation and provide personalized assistance. Be concise but thorough in your responses."""
    
    # Build conversation context
    messages = [{"role": "system", "content": system_prompt}]
    
    # Add conversation history for context
    for turn in conversation_history:
        messages.append({
            "role": turn['role'],
            "content": turn['content']
        })
    
    # Add current user message
    messages.append({
        "role": "user",
        "content": user_message
    })
    
    return messages


def invoke_claude_model(messages: List[Dict[str, str]]) -> Optional[str]:
    """Invoke Claude model through Bedrock."""
    
    try:
        # Prepare request body for Claude API format
        request_body = {
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": MAX_TOKENS,
            "temperature": TEMPERATURE,
            "messages": messages[1:]  # Exclude system message for messages array
        }
        
        # Add system message if present
        if messages[0]["role"] == "system":
            request_body["system"] = messages[0]["content"]
        
        # Invoke model through Bedrock Runtime
        response = bedrock_runtime.invoke_model(
            modelId=CLAUDE_MODEL_ID,
            body=json.dumps(request_body),
            contentType='application/json'
        )
        
        # Parse response
        response_body = json.loads(response['body'].read())
        
        # Extract text from Claude response
        if 'content' in response_body and len(response_body['content']) > 0:
            return response_body['content'][0]['text']
        else:
            logger.error("Unexpected response format from Claude")
            return None
            
    except Exception as e:
        logger.error(f"Error invoking Claude model: {str(e)}")
        return None


def save_conversation_turn(session_id: str, user_id: str, user_message: str, assistant_response: str) -> None:
    """Save conversation turn to DynamoDB."""
    
    try:
        timestamp = int(time.time() * 1000)  # Milliseconds for better sorting
        
        # Save user message
        table.put_item(
            Item={
                'session_id': session_id,
                'timestamp': timestamp,
                'role': 'user',
                'content': user_message,
                'user_id': user_id,
                'created_at': datetime.utcnow().isoformat(),
                'ttl': int(time.time()) + (30 * 24 * 60 * 60)  # 30-day TTL
            }
        )
        
        # Save assistant response
        table.put_item(
            Item={
                'session_id': session_id,
                'timestamp': timestamp + 1,  # Ensure assistant response comes after user message
                'role': 'assistant',
                'content': assistant_response,
                'user_id': user_id,
                'created_at': datetime.utcnow().isoformat(),
                'ttl': int(time.time()) + (30 * 24 * 60 * 60)  # 30-day TTL
            }
        )
        
        logger.info(f"Saved conversation turn for session {session_id}")
        
    except Exception as e:
        logger.error(f"Error saving conversation: {str(e)}")
'''


app = cdk.App()

# Create the conversational AI stack
ConversationalAIStack(
    app,
    "ConversationalAIStack",
    description="Conversational AI application using Amazon Bedrock and Claude",
    env=cdk.Environment(
        account=app.node.try_get_context("account"),
        region=app.node.try_get_context("region")
    )
)

# Add global tags
cdk.Tags.of(app).add("Project", "ConversationalAI")
cdk.Tags.of(app).add("ManagedBy", "CDK")
cdk.Tags.of(app).add("Environment", "Development")

app.synth()