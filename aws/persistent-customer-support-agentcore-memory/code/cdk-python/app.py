#!/usr/bin/env python3
"""
CDK Python application for Persistent Customer Support Agent with Bedrock AgentCore Memory

This application creates a complete customer support system with persistent memory
capabilities using Amazon Bedrock AgentCore, Lambda, DynamoDB, and API Gateway.
"""

import os
from typing import Dict, Any, Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_lambda as _lambda,
    aws_apigateway as apigateway,
    aws_dynamodb as dynamodb,
    aws_iam as iam,
    aws_logs as logs,
)
from constructs import Construct


class PersistentCustomerSupportStack(Stack):
    """
    CDK Stack for Persistent Customer Support Agent with Bedrock AgentCore Memory
    
    This stack creates:
    - DynamoDB table for customer metadata
    - Lambda function for support agent logic
    - API Gateway for client access
    - IAM roles and policies with least privilege
    - CloudWatch Log Groups for monitoring
    """

    def __init__(
        self, 
        scope: Construct, 
        construct_id: str, 
        memory_name: Optional[str] = None,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique resource names
        random_suffix = self._generate_random_suffix()
        
        # Resource naming
        self.memory_name = memory_name or f"customer-support-memory-{random_suffix}"
        self.lambda_function_name = f"support-agent-{random_suffix}"
        self.ddb_table_name = f"customer-data-{random_suffix}"
        self.api_name = f"support-api-{random_suffix}"

        # Create DynamoDB table for customer metadata
        self.customer_table = self._create_customer_table()
        
        # Create Lambda execution role
        self.lambda_role = self._create_lambda_role()
        
        # Create Lambda function
        self.lambda_function = self._create_lambda_function()
        
        # Create API Gateway
        self.api_gateway = self._create_api_gateway()
        
        # Create CloudWatch Log Group
        self.log_group = self._create_log_group()
        
        # Create outputs
        self._create_outputs()

    def _generate_random_suffix(self) -> str:
        """Generate a random suffix for resource naming"""
        import random
        import string
        return ''.join(random.choices(string.ascii_lowercase + string.digits, k=6))

    def _create_customer_table(self) -> dynamodb.Table:
        """
        Create DynamoDB table for storing customer metadata and preferences
        
        Returns:
            dynamodb.Table: The created DynamoDB table
        """
        table = dynamodb.Table(
            self, "CustomerDataTable",
            table_name=self.ddb_table_name,
            partition_key=dynamodb.Attribute(
                name="customerId",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PROVISIONED,
            read_capacity=5,
            write_capacity=5,
            removal_policy=RemovalPolicy.DESTROY,  # For demo purposes
            point_in_time_recovery=True,
            encryption=dynamodb.TableEncryption.AWS_MANAGED,
        )
        
        # Add tags
        cdk.Tags.of(table).add("Purpose", "CustomerSupport")
        cdk.Tags.of(table).add("Application", "BedrockAgentCore")
        
        return table

    def _create_lambda_role(self) -> iam.Role:
        """
        Create IAM role for Lambda function with necessary permissions
        
        Returns:
            iam.Role: The created IAM role
        """
        role = iam.Role(
            self, "SupportAgentLambdaRole",
            role_name=f"{self.lambda_function_name}-role",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Execution role for customer support agent Lambda function",
        )
        
        # Add basic Lambda execution policy
        role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name(
                "service-role/AWSLambdaBasicExecutionRole"
            )
        )
        
        # Add Bedrock AgentCore permissions
        bedrock_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "bedrock-agentcore:CreateEvent",
                "bedrock-agentcore:ListSessions",
                "bedrock-agentcore:ListEvents",
                "bedrock-agentcore:GetEvent",
                "bedrock-agentcore:RetrieveMemoryRecords",
            ],
            resources=["*"],  # AgentCore resources are region-specific
        )
        
        # Add Bedrock model invocation permissions
        bedrock_invoke_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=["bedrock:InvokeModel"],
            resources=[
                f"arn:aws:bedrock:{self.region}::foundation-model/*"
            ],
        )
        
        # Add DynamoDB permissions
        dynamodb_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "dynamodb:GetItem",
                "dynamodb:PutItem",
                "dynamodb:UpdateItem",
                "dynamodb:Query",
            ],
            resources=[self.customer_table.table_arn],
        )
        
        # Add policies to role
        role.add_to_policy(bedrock_policy)
        role.add_to_policy(bedrock_invoke_policy)
        role.add_to_policy(dynamodb_policy)
        
        return role

    def _create_lambda_function(self) -> _lambda.Function:
        """
        Create Lambda function for customer support agent logic
        
        Returns:
            _lambda.Function: The created Lambda function
        """
        
        # Lambda function code
        lambda_code = '''
import json
import boto3
import os
from datetime import datetime
from typing import Dict, List, Any, Optional

bedrock_agentcore = boto3.client('bedrock-agentcore')
bedrock_runtime = boto3.client('bedrock-runtime')
dynamodb = boto3.resource('dynamodb')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for customer support interactions
    
    Args:
        event: API Gateway event containing customer request
        context: Lambda context object
        
    Returns:
        Dict containing API Gateway response
    """
    try:
        # Parse incoming request
        body = json.loads(event.get('body', '{}')) if event.get('body') else event
        customer_id = body.get('customerId')
        message = body.get('message')
        session_id = body.get('sessionId', f"session-{customer_id}-{int(datetime.now().timestamp())}")
        
        if not customer_id or not message:
            return create_error_response(400, "Missing required fields: customerId and message")
        
        # Retrieve customer context from DynamoDB
        table = dynamodb.Table(os.environ['DDB_TABLE_NAME'])
        customer_data = get_customer_data(table, customer_id)
        
        # Retrieve relevant memories from AgentCore
        memory_context = retrieve_memory_context(customer_id, message)
        
        # Generate AI response using Bedrock
        ai_response = generate_support_response(message, memory_context, customer_data)
        
        # Store interaction in AgentCore Memory
        store_interaction(customer_id, session_id, message, ai_response)
        
        # Update customer data if needed
        update_customer_data(table, customer_id, body.get('metadata', {}))
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type',
                'Access-Control-Allow-Methods': 'POST,OPTIONS'
            },
            'body': json.dumps({
                'response': ai_response,
                'sessionId': session_id,
                'customerId': customer_id,
                'timestamp': datetime.now().isoformat()
            })
        }
        
    except Exception as e:
        print(f"Error in lambda_handler: {str(e)}")
        return create_error_response(500, "Internal server error")

def create_error_response(status_code: int, message: str) -> Dict[str, Any]:
    """Create standardized error response"""
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps({
            'error': message,
            'timestamp': datetime.now().isoformat()
        })
    }

def get_customer_data(table: Any, customer_id: str) -> Dict[str, Any]:
    """
    Retrieve customer data from DynamoDB
    
    Args:
        table: DynamoDB table resource
        customer_id: Customer identifier
        
    Returns:
        Dict containing customer data
    """
    try:
        response = table.get_item(Key={'customerId': customer_id})
        return response.get('Item', {})
    except Exception as e:
        print(f"Error retrieving customer data: {e}")
        return {}

def retrieve_memory_context(customer_id: str, query: str) -> List[str]:
    """
    Retrieve relevant memory context from AgentCore
    
    Args:
        customer_id: Customer identifier
        query: Current query for semantic search
        
    Returns:
        List of relevant memory records
    """
    try:
        if not os.environ.get('MEMORY_ID'):
            print("No MEMORY_ID configured, skipping memory retrieval")
            return []
            
        response = bedrock_agentcore.retrieve_memory_records(
            memoryId=os.environ['MEMORY_ID'],
            query=query,
            filter={'customerId': customer_id},
            maxResults=5
        )
        return [record.get('content', '') for record in response.get('memoryRecords', [])]
    except Exception as e:
        print(f"Error retrieving memory context: {e}")
        return []

def generate_support_response(
    message: str, 
    memory_context: List[str], 
    customer_data: Dict[str, Any]
) -> str:
    """
    Generate AI response using Bedrock foundation model
    
    Args:
        message: Customer message
        memory_context: Previous interaction context
        customer_data: Customer profile data
        
    Returns:
        Generated support response
    """
    try:
        # Prepare context for AI model
        context_parts = []
        
        if memory_context:
            context_parts.append(f"Previous interactions: {'; '.join(memory_context)}")
        
        if customer_data:
            customer_profile = {
                'name': customer_data.get('name', 'Unknown'),
                'supportTier': customer_data.get('supportTier', 'standard'),
                'preferredChannel': customer_data.get('preferredChannel', 'chat'),
                'productInterests': customer_data.get('productInterests', [])
            }
            context_parts.append(f"Customer profile: {json.dumps(customer_profile)}")
        
        context_parts.append(f"Current query: {message}")
        
        context = f"""
Customer Support Context:
{chr(10).join(context_parts)}

Provide a helpful, personalized response based on the customer's history and current request.
Be empathetic, professional, and reference relevant past interactions when appropriate.
Keep the response concise but comprehensive, under 300 words.
"""
        
        # Invoke Bedrock model
        response = bedrock_runtime.invoke_model(
            modelId='anthropic.claude-3-haiku-20240307-v1:0',
            body=json.dumps({
                'anthropic_version': 'bedrock-2023-05-31',
                'max_tokens': 500,
                'messages': [
                    {
                        'role': 'user',
                        'content': context
                    }
                ]
            })
        )
        
        result = json.loads(response['body'].read())
        return result['content'][0]['text']
        
    except Exception as e:
        print(f"Error generating response: {e}")
        return "I apologize, but I'm experiencing technical difficulties. Please try again or contact our support team directly."

def store_interaction(
    customer_id: str, 
    session_id: str, 
    user_message: str, 
    agent_response: str
) -> None:
    """
    Store conversation in AgentCore Memory
    
    Args:
        customer_id: Customer identifier
        session_id: Session identifier
        user_message: Customer message
        agent_response: Agent response
    """
    try:
        if not os.environ.get('MEMORY_ID'):
            print("No MEMORY_ID configured, skipping memory storage")
            return
            
        # Store user message
        bedrock_agentcore.create_event(
            memoryId=os.environ['MEMORY_ID'],
            sessionId=session_id,
            eventData={
                'type': 'user_message',
                'customerId': customer_id,
                'content': user_message,
                'timestamp': datetime.now().isoformat()
            }
        )
        
        # Store agent response
        bedrock_agentcore.create_event(
            memoryId=os.environ['MEMORY_ID'],
            sessionId=session_id,
            eventData={
                'type': 'agent_response',
                'customerId': customer_id,
                'content': agent_response,
                'timestamp': datetime.now().isoformat()
            }
        )
    except Exception as e:
        print(f"Error storing interaction in memory: {e}")

def update_customer_data(
    table: Any, 
    customer_id: str, 
    metadata: Dict[str, Any]
) -> None:
    """
    Update customer data in DynamoDB
    
    Args:
        table: DynamoDB table resource
        customer_id: Customer identifier
        metadata: Additional customer metadata
    """
    try:
        if metadata:
            item = {
                'customerId': customer_id,
                'lastInteraction': datetime.now().isoformat(),
                **metadata
            }
            table.put_item(Item=item)
    except Exception as e:
        print(f"Error updating customer data: {e}")
'''
        
        function = _lambda.Function(
            self, "SupportAgentFunction",
            function_name=self.lambda_function_name,
            runtime=_lambda.Runtime.PYTHON_3_11,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline(lambda_code),
            role=self.lambda_role,
            timeout=Duration.seconds(30),
            memory_size=512,
            environment={
                "DDB_TABLE_NAME": self.customer_table.table_name,
                # MEMORY_ID will be set manually after AgentCore Memory creation
                "MEMORY_ID": "",  # Placeholder - must be updated after memory creation
            },
            description="Customer support agent with persistent memory capabilities",
        )
        
        return function

    def _create_api_gateway(self) -> apigateway.RestApi:
        """
        Create API Gateway for customer support interactions
        
        Returns:
            apigateway.RestApi: The created API Gateway
        """
        api = apigateway.RestApi(
            self, "SupportApi",
            rest_api_name=self.api_name,
            description="Customer Support Agent API with AgentCore Memory",
            default_cors_preflight_options=apigateway.CorsOptions(
                allow_origins=apigateway.Cors.ALL_ORIGINS,
                allow_methods=["POST", "OPTIONS"],
                allow_headers=["Content-Type", "Authorization"],
            ),
            deploy_options=apigateway.StageOptions(
                stage_name="prod",
                throttling_rate_limit=100,
                throttling_burst_limit=200,
                logging_level=apigateway.MethodLoggingLevel.INFO,
                data_trace_enabled=True,
                metrics_enabled=True,
            ),
        )
        
        # Create support resource
        support_resource = api.root.add_resource("support")
        
        # Create Lambda integration
        lambda_integration = apigateway.LambdaIntegration(
            self.lambda_function,
            proxy=True,
            integration_responses=[
                apigateway.IntegrationResponse(
                    status_code="200",
                    response_headers={
                        "Access-Control-Allow-Origin": "'*'",
                        "Access-Control-Allow-Headers": "'Content-Type,Authorization'",
                    },
                )
            ],
        )
        
        # Add POST method
        support_resource.add_method(
            "POST",
            lambda_integration,
            method_responses=[
                apigateway.MethodResponse(
                    status_code="200",
                    response_headers={
                        "Access-Control-Allow-Origin": True,
                        "Access-Control-Allow-Headers": True,
                    },
                )
            ],
        )
        
        return api

    def _create_log_group(self) -> logs.LogGroup:
        """
        Create CloudWatch Log Group for Lambda function
        
        Returns:
            logs.LogGroup: The created log group
        """
        log_group = logs.LogGroup(
            self, "SupportAgentLogGroup",
            log_group_name=f"/aws/lambda/{self.lambda_function_name}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        return log_group

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources"""
        
        CfnOutput(
            self, "ApiEndpoint",
            description="API Gateway endpoint for customer support",
            value=f"{self.api_gateway.url}support",
            export_name=f"{self.stack_name}-ApiEndpoint",
        )
        
        CfnOutput(
            self, "LambdaFunctionName",
            description="Lambda function name for customer support agent",
            value=self.lambda_function.function_name,
            export_name=f"{self.stack_name}-LambdaFunctionName",
        )
        
        CfnOutput(
            self, "DynamoDBTableName",
            description="DynamoDB table name for customer data",
            value=self.customer_table.table_name,
            export_name=f"{self.stack_name}-DynamoDBTableName",
        )
        
        CfnOutput(
            self, "AgentCoreMemoryName",
            description="AgentCore Memory name (must be created manually)",
            value=self.memory_name,
            export_name=f"{self.stack_name}-MemoryName",
        )
        
        CfnOutput(
            self, "LambdaRoleArn",
            description="Lambda execution role ARN",
            value=self.lambda_role.role_arn,
            export_name=f"{self.stack_name}-LambdaRoleArn",
        )


class PersistentCustomerSupportApp(cdk.App):
    """
    CDK Application for Persistent Customer Support Agent
    """
    
    def __init__(self):
        super().__init__()
        
        # Environment configuration
        env = cdk.Environment(
            account=os.getenv('CDK_DEFAULT_ACCOUNT'),
            region=os.getenv('CDK_DEFAULT_REGION', 'us-east-1')
        )
        
        # Create the main stack
        PersistentCustomerSupportStack(
            self, 
            "PersistentCustomerSupportStack",
            env=env,
            description="Persistent Customer Support Agent with Bedrock AgentCore Memory",
            tags={
                "Application": "CustomerSupport",
                "Component": "BedrockAgentCore",
                "Environment": "Demo",
                "Owner": "CDK"
            }
        )


# Create the CDK application
app = PersistentCustomerSupportApp()
app.synth()