"""
Multi-Agent AI Workflow Stack

This module defines the CDK stack for deploying a comprehensive multi-agent AI system
using Amazon Bedrock agents, AWS Lambda for orchestration, Amazon EventBridge for
event-driven coordination, and DynamoDB for shared memory management.
"""

from typing import Any, Dict, List

import aws_cdk as cdk
import aws_cdk.aws_bedrock as bedrock
import aws_cdk.aws_dynamodb as dynamodb
import aws_cdk.aws_events as events
import aws_cdk.aws_events_targets as events_targets
import aws_cdk.aws_iam as iam
import aws_cdk.aws_lambda as lambda_
import aws_cdk.aws_logs as logs
import aws_cdk.aws_sqs as sqs
from constructs import Construct


class MultiAgentWorkflowStack(cdk.Stack):
    """
    AWS CDK Stack for Multi-Agent AI Workflows using Amazon Bedrock AgentCore.
    
    This stack creates:
    - Amazon Bedrock agents (supervisor and specialized agents)
    - AWS Lambda function for workflow coordination
    - Amazon EventBridge custom bus for agent communication
    - DynamoDB table for agent memory management
    - IAM roles and policies with least-privilege access
    - CloudWatch monitoring and logging
    - SQS dead letter queue for failed events
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs: Any) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Create foundational resources
        self.agent_memory_table = self._create_memory_table()
        self.event_bus = self._create_event_bus()
        self.coordinator_function = self._create_coordinator_function()
        self.dead_letter_queue = self._create_dead_letter_queue()
        
        # Create Bedrock agents
        self.bedrock_agent_role = self._create_bedrock_agent_role()
        self.agents = self._create_bedrock_agents()
        
        # Configure EventBridge integration
        self._configure_event_routing()
        
        # Create monitoring resources
        self._create_monitoring_resources()
        
        # Output important resource identifiers
        self._create_outputs()

    def _create_memory_table(self) -> dynamodb.Table:
        """Create DynamoDB table for agent memory management."""
        table = dynamodb.Table(
            self,
            "AgentMemoryTable",
            table_name=f"agent-memory-{self.stack_name.lower()}",
            partition_key=dynamodb.Attribute(
                name="SessionId",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="Timestamp",
                type=dynamodb.AttributeType.NUMBER
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
            time_to_live_attribute="TTL",
            point_in_time_recovery=True,
            removal_policy=cdk.RemovalPolicy.DESTROY,  # For demo purposes
        )

        # Add GSI for querying by task type
        table.add_global_secondary_index(
            index_name="TaskTypeIndex",
            partition_key=dynamodb.Attribute(
                name="TaskType",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="Timestamp",
                type=dynamodb.AttributeType.NUMBER
            ),
        )

        return table

    def _create_event_bus(self) -> events.EventBus:
        """Create custom EventBridge bus for agent communication."""
        event_bus = events.EventBus(
            self,
            "MultiAgentEventBus",
            event_bus_name=f"multi-agent-bus-{self.stack_name.lower()}"
        )

        return event_bus

    def _create_coordinator_function(self) -> lambda_.Function:
        """Create AWS Lambda function for workflow coordination."""
        # Create IAM role for Lambda coordinator
        lambda_role = iam.Role(
            self,
            "LambdaCoordinatorRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole"),
            ],
        )

        # Add permissions for DynamoDB, EventBridge, and Bedrock
        lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "dynamodb:GetItem",
                    "dynamodb:PutItem",
                    "dynamodb:UpdateItem",
                    "dynamodb:Query",
                    "dynamodb:Scan",
                ],
                resources=[self.agent_memory_table.table_arn, f"{self.agent_memory_table.table_arn}/*"]
            )
        )

        lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "events:PutEvents",
                ],
                resources=[self.event_bus.event_bus_arn]
            )
        )

        lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "bedrock:InvokeAgent",
                    "bedrock:InvokeModel",
                ],
                resources=["*"]  # Bedrock resources don't support specific ARNs
            )
        )

        # Create Lambda function
        coordinator_function = lambda_.Function(
            self,
            "AgentCoordinator",
            function_name=f"agent-coordinator-{self.stack_name.lower()}",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="coordinator.lambda_handler",
            code=lambda_.Code.from_inline(self._get_coordinator_code()),
            timeout=cdk.Duration.minutes(5),
            memory_size=256,
            role=lambda_role,
            environment={
                "MEMORY_TABLE_NAME": self.agent_memory_table.table_name,
                "EVENT_BUS_NAME": self.event_bus.event_bus_name,
            },
            tracing=lambda_.Tracing.ACTIVE,  # Enable X-Ray tracing
        )

        return coordinator_function

    def _create_dead_letter_queue(self) -> sqs.Queue:
        """Create SQS dead letter queue for failed events."""
        dlq = sqs.Queue(
            self,
            "MultiAgentDLQ",
            queue_name=f"multi-agent-dlq-{self.stack_name.lower()}",
            message_retention_period=cdk.Duration.days(14),
            visibility_timeout=cdk.Duration.minutes(5),
        )

        return dlq

    def _create_bedrock_agent_role(self) -> iam.Role:
        """Create IAM role for Amazon Bedrock agents."""
        role = iam.Role(
            self,
            "BedrockAgentRole",
            assumed_by=iam.ServicePrincipal("bedrock.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonBedrockFullAccess"),
            ],
        )

        # Add permissions for DynamoDB access
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "dynamodb:GetItem",
                    "dynamodb:PutItem",
                    "dynamodb:UpdateItem",
                    "dynamodb:Query",
                ],
                resources=[self.agent_memory_table.table_arn]
            )
        )

        return role

    def _create_bedrock_agents(self) -> Dict[str, Any]:
        """Create Amazon Bedrock agents for the multi-agent system."""
        agents = {}

        # Agent configurations
        agent_configs = [
            {
                "name": "supervisor",
                "description": "Supervisor agent for multi-agent workflow coordination",
                "instruction": """You are a supervisor agent responsible for coordinating complex business tasks across specialized agent teams. Your responsibilities include:
1. Analyzing incoming requests and breaking them into sub-tasks
2. Routing tasks to appropriate specialist agents: Financial Agent for financial analysis, Support Agent for customer service, Analytics Agent for data analysis
3. Coordinating parallel work streams and managing dependencies
4. Synthesizing results from multiple agents into cohesive responses
5. Ensuring quality control and consistency across agent outputs
Always provide clear task delegation and maintain oversight of the overall workflow progress.""",
                "session_ttl": 3600
            },
            {
                "name": "finance",
                "description": "Specialized agent for financial analysis and reporting",
                "instruction": """You are a financial analysis specialist. Your role is to analyze financial data, create reports, calculate metrics, and provide insights on financial performance. Always provide detailed explanations of your analysis methodology and cite relevant financial principles. Focus on accuracy and compliance with financial reporting standards.""",
                "session_ttl": 1800
            },
            {
                "name": "support",
                "description": "Specialized agent for customer support and service",
                "instruction": """You are a customer support specialist. Your role is to help customers resolve issues, answer questions, and provide excellent service experiences. Always maintain a helpful, empathetic tone and focus on resolving customer concerns efficiently. Escalate complex technical issues when appropriate and always follow company policies.""",
                "session_ttl": 1800
            },
            {
                "name": "analytics",
                "description": "Specialized agent for data analysis and insights",
                "instruction": """You are a data analytics specialist. Your role is to analyze datasets, identify patterns, create visualizations, and provide actionable insights. Focus on statistical accuracy, clear data interpretation, and practical business recommendations. Always explain your analytical methodology and validate your findings.""",
                "session_ttl": 1800
            }
        ]

        # Create agents using CloudFormation custom resource
        # Note: As of CDK v2, there's no high-level construct for Bedrock agents
        # We'll use CfnAgent from the low-level constructs
        for config in agent_configs:
            agent = bedrock.CfnAgent(
                self,
                f"{config['name'].title()}Agent",
                agent_name=f"{config['name']}-agent-{self.stack_name.lower()}",
                agent_resource_role_arn=self.bedrock_agent_role.role_arn,
                description=config["description"],
                foundation_model="anthropic.claude-3-sonnet-20240229-v1:0",
                instruction=config["instruction"],
                idle_session_ttl_in_seconds=config["session_ttl"],
                auto_prepare=True,
            )
            
            agents[config["name"]] = agent

            # Create agent alias for production use
            bedrock.CfnAgentAlias(
                self,
                f"{config['name'].title()}AgentAlias",
                agent_id=agent.attr_agent_id,
                agent_alias_name="production",
                description=f"Production alias for {config['name']} agent"
            )

        return agents

    def _configure_event_routing(self) -> None:
        """Configure EventBridge rules and targets for agent communication."""
        # Create rule for agent task routing
        task_routing_rule = events.Rule(
            self,
            "AgentTaskRoutingRule",
            event_bus=self.event_bus,
            rule_name="agent-task-router",
            description="Routes tasks to specialized agents",
            event_pattern=events.EventPattern(
                source=["multi-agent.system"],
                detail_type=["Agent Task Request"]
            )
        )

        # Add Lambda function as target
        task_routing_rule.add_target(
            events_targets.LambdaFunction(
                self.coordinator_function,
                dead_letter_queue=self.dead_letter_queue,
                retry_attempts=3
            )
        )

    def _create_monitoring_resources(self) -> None:
        """Create CloudWatch monitoring and logging resources."""
        # Create log groups
        logs.LogGroup(
            self,
            "BedrockAgentsLogGroup",
            log_group_name="/aws/bedrock/agents/multi-agent-workflow",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=cdk.RemovalPolicy.DESTROY
        )

        logs.LogGroup(
            self,
            "CoordinatorLogGroup", 
            log_group_name=f"/aws/lambda/{self.coordinator_function.function_name}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=cdk.RemovalPolicy.DESTROY
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource identifiers."""
        cdk.CfnOutput(
            self,
            "AgentMemoryTableName",
            value=self.agent_memory_table.table_name,
            description="DynamoDB table name for agent memory management"
        )

        cdk.CfnOutput(
            self,
            "EventBusName",
            value=self.event_bus.event_bus_name,
            description="EventBridge custom bus name for agent communication"
        )

        cdk.CfnOutput(
            self,
            "CoordinatorFunctionName",
            value=self.coordinator_function.function_name,
            description="Lambda function name for workflow coordination"
        )

        cdk.CfnOutput(
            self,
            "SupervisorAgentId",
            value=self.agents["supervisor"].attr_agent_id,
            description="Amazon Bedrock supervisor agent ID"
        )

        cdk.CfnOutput(
            self,
            "DeadLetterQueueUrl",
            value=self.dead_letter_queue.queue_url,
            description="SQS dead letter queue URL for failed events"
        )

    def _get_coordinator_code(self) -> str:
        """Return the Lambda function code for the agent coordinator."""
        return '''
import json
import boto3
import logging
import os
from datetime import datetime, timedelta
from typing import Dict, Any, Optional

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
eventbridge = boto3.client('events')
bedrock_agent = boto3.client('bedrock-agent-runtime')
dynamodb = boto3.resource('dynamodb')

# Get environment variables
MEMORY_TABLE_NAME = os.environ['MEMORY_TABLE_NAME']
EVENT_BUS_NAME = os.environ['EVENT_BUS_NAME']

def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    Coordinate multi-agent workflows based on EventBridge events.
    
    Args:
        event: EventBridge event containing task details
        context: Lambda context object
        
    Returns:
        Response dictionary with status and correlation ID
    """
    try:
        # Parse EventBridge event
        detail = event.get('detail', {})
        task_type = detail.get('taskType')
        request_data = detail.get('requestData')
        correlation_id = detail.get('correlationId')
        session_id = detail.get('sessionId', correlation_id)
        
        logger.info(f"Processing task: {task_type} with correlation: {correlation_id}")
        
        # Store task in memory table
        memory_table = dynamodb.Table(MEMORY_TABLE_NAME)
        
        # Set TTL for 24 hours from now
        ttl = int((datetime.utcnow() + timedelta(days=1)).timestamp())
        
        memory_table.put_item(
            Item={
                'SessionId': session_id,
                'Timestamp': int(datetime.utcnow().timestamp()),
                'TaskType': task_type,
                'RequestData': request_data,
                'Status': 'processing',
                'TTL': ttl
            }
        )
        
        # Route to appropriate agent based on task type
        agent_response = route_to_agent(task_type, request_data, session_id)
        
        # Update memory with result
        memory_table.put_item(
            Item={
                'SessionId': session_id,
                'Timestamp': int(datetime.utcnow().timestamp()),
                'TaskType': task_type,
                'Response': agent_response,
                'Status': 'completed',
                'TTL': ttl
            }
        )
        
        # Publish completion event
        eventbridge.put_events(
            Entries=[{
                'Source': 'multi-agent.coordinator',
                'DetailType': 'Agent Task Completed',
                'Detail': json.dumps({
                    'correlationId': correlation_id,
                    'taskType': task_type,
                    'result': agent_response,
                    'status': 'completed'
                }),
                'EventBusName': EVENT_BUS_NAME
            }]
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Task coordinated successfully',
                'correlationId': correlation_id
            })
        }
        
    except Exception as e:
        logger.error(f"Coordination error: {str(e)}")
        
        # Publish error event
        eventbridge.put_events(
            Entries=[{
                'Source': 'multi-agent.coordinator',
                'DetailType': 'Agent Task Failed',
                'Detail': json.dumps({
                    'correlationId': correlation_id if 'correlation_id' in locals() else 'unknown',
                    'error': str(e),
                    'status': 'failed'
                }),
                'EventBusName': EVENT_BUS_NAME
            }]
        )
        
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def route_to_agent(task_type: str, request_data: str, session_id: str) -> str:
    """
    Route task to appropriate specialized agent.
    
    Args:
        task_type: Type of task to process
        request_data: The actual request data
        session_id: Session identifier for context
        
    Returns:
        Agent response string
    """
    # This is a simplified routing function for demonstration
    # In production, this would invoke actual Bedrock agents
    agent_responses = {
        'financial_analysis': f"Financial analysis completed for: {request_data}",
        'customer_support': f"Customer support response for: {request_data}",
        'data_analytics': f"Analytics insights for: {request_data}",
        'general': f"General processing completed for: {request_data}"
    }
    
    return agent_responses.get(task_type, agent_responses['general'])

def invoke_bedrock_agent(agent_id: str, agent_alias_id: str, session_id: str, input_text: str) -> Optional[str]:
    """
    Invoke a Bedrock agent and return the response.
    
    Args:
        agent_id: The Bedrock agent ID
        agent_alias_id: The agent alias ID
        session_id: Session identifier
        input_text: Input text for the agent
        
    Returns:
        Agent response text or None if error
    """
    try:
        response = bedrock_agent.invoke_agent(
            agentId=agent_id,
            agentAliasId=agent_alias_id,
            sessionId=session_id,
            inputText=input_text
        )
        
        # Extract the response text
        return response.get('completion', '')
        
    except Exception as e:
        logger.error(f"Error invoking Bedrock agent {agent_id}: {str(e)}")
        return None
'''