#!/usr/bin/env python3
"""
AWS CDK Python Application for Business Process Automation
with Bedrock AgentCore and EventBridge

This application creates an intelligent business process automation system that:
- Uses Amazon Bedrock Agents to analyze documents and make decisions
- Orchestrates workflows through EventBridge event routing
- Implements serverless business process handlers with Lambda
- Provides secure document storage and processing with S3
"""

import aws_cdk as cdk
from aws_cdk import (
    aws_bedrock as bedrock,
    aws_events as events,
    aws_events_targets as targets,
    aws_lambda as lambda_,
    aws_s3 as s3,
    aws_iam as iam,
    aws_logs as logs,
    Stack,
    Duration,
    RemovalPolicy,
    CfnOutput
)
from constructs import Construct
import json
from typing import Dict, Any


class BusinessProcessAutomationStack(Stack):
    """
    CDK Stack for Business Process Automation with Bedrock Agents and EventBridge.
    
    Creates a complete serverless architecture for intelligent document processing
    and workflow automation using AI-powered decision making.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Stack parameters and configuration
        self.project_name = "biz-automation"
        self.region = self.region
        self.account = self.account

        # Create core infrastructure components
        self.document_bucket = self._create_document_storage()
        self.event_bus = self._create_event_bus()
        self.lambda_functions = self._create_lambda_functions()
        self.event_rules = self._create_event_rules()
        self.bedrock_agent = self._create_bedrock_agent()

        # Create outputs for external integration
        self._create_outputs()

    def _create_document_storage(self) -> s3.Bucket:
        """
        Create secure S3 bucket for document storage with encryption and versioning.
        
        Returns:
            s3.Bucket: Configured S3 bucket for document processing
        """
        bucket = s3.Bucket(
            self, "DocumentBucket",
            bucket_name=f"{self.project_name}-documents-{self.account}-{self.region}",
            encryption=s3.BucketEncryption.S3_MANAGED,
            versioned=True,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DocumentLifecycle",
                    enabled=True,
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30)
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(90)
                        )
                    ]
                )
            ]
        )

        # Add bucket notification configuration for future integration
        bucket.add_cors_rule(
            allowed_methods=[s3.HttpMethods.GET, s3.HttpMethods.PUT, s3.HttpMethods.POST],
            allowed_origins=["*"],
            allowed_headers=["*"],
            max_age=3000
        )

        return bucket

    def _create_event_bus(self) -> events.EventBus:
        """
        Create custom EventBridge event bus for business process automation.
        
        Returns:
            events.EventBus: Custom event bus for workflow orchestration
        """
        event_bus = events.EventBus(
            self, "BusinessEventBus",
            event_bus_name=f"{self.project_name}-events"
        )

        # Add resource-based policy for secure access
        event_bus_policy = iam.PolicyDocument(
            statements=[
                iam.PolicyStatement(
                    sid="AllowBedrockAgentAccess",
                    effect=iam.Effect.ALLOW,
                    principals=[iam.ArnPrincipal(f"arn:aws:iam::{self.account}:root")],
                    actions=["events:PutEvents"],
                    resources=[event_bus.event_bus_arn]
                )
            ]
        )

        return event_bus

    def _create_lambda_functions(self) -> Dict[str, lambda_.Function]:
        """
        Create Lambda functions for business process handling.
        
        Returns:
            Dict[str, lambda_.Function]: Dictionary of Lambda functions by name
        """
        # Create execution role for Lambda functions
        lambda_role = iam.Role(
            self, "LambdaExecutionRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole"),
                iam.ManagedPolicy.from_aws_managed_policy_name("AWSXRayDaemonWriteAccess")
            ],
            inline_policies={
                "BusinessProcessPolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "dynamodb:PutItem",
                                "dynamodb:GetItem",
                                "dynamodb:UpdateItem",
                                "dynamodb:Query"
                            ],
                            resources=["*"]
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=["events:PutEvents"],
                            resources=[f"arn:aws:events:{self.region}:{self.account}:event-bus/*"]
                        )
                    ]
                )
            }
        )

        functions = {}

        # Approval Handler Lambda
        approval_code = self._get_approval_handler_code()
        functions['approval'] = lambda_.Function(
            self, "ApprovalHandler",
            function_name=f"{self.project_name}-approval",
            runtime=lambda_.Runtime.PYTHON_3_12,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(approval_code),
            role=lambda_role,
            timeout=Duration.seconds(30),
            memory_size=256,
            tracing=lambda_.Tracing.ACTIVE,
            environment={
                "PROJECT_NAME": self.project_name,
                "EVENT_BUS_NAME": f"{self.project_name}-events"
            },
            log_retention=logs.RetentionDays.ONE_WEEK
        )

        # Processing Handler Lambda
        processing_code = self._get_processing_handler_code()
        functions['processing'] = lambda_.Function(
            self, "ProcessingHandler",
            function_name=f"{self.project_name}-processing",
            runtime=lambda_.Runtime.PYTHON_3_12,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(processing_code),
            role=lambda_role,
            timeout=Duration.seconds(30),
            memory_size=256,
            tracing=lambda_.Tracing.ACTIVE,
            environment={
                "PROJECT_NAME": self.project_name,
                "EVENT_BUS_NAME": f"{self.project_name}-events"
            },
            log_retention=logs.RetentionDays.ONE_WEEK
        )

        # Notification Handler Lambda
        notification_code = self._get_notification_handler_code()
        functions['notification'] = lambda_.Function(
            self, "NotificationHandler",
            function_name=f"{self.project_name}-notification",
            runtime=lambda_.Runtime.PYTHON_3_12,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(notification_code),
            role=lambda_role,
            timeout=Duration.seconds(30),
            memory_size=256,
            tracing=lambda_.Tracing.ACTIVE,
            environment={
                "PROJECT_NAME": self.project_name,
                "EVENT_BUS_NAME": f"{self.project_name}-events"
            },
            log_retention=logs.RetentionDays.ONE_WEEK
        )

        # Agent Action Handler Lambda
        agent_action_code = self._get_agent_action_handler_code()
        functions['agent_action'] = lambda_.Function(
            self, "AgentActionHandler",
            function_name=f"{self.project_name}-agent-action",
            runtime=lambda_.Runtime.PYTHON_3_12,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(agent_action_code),
            role=self._create_agent_action_role(),
            timeout=Duration.seconds(60),
            memory_size=512,
            tracing=lambda_.Tracing.ACTIVE,
            environment={
                "PROJECT_NAME": self.project_name,
                "EVENT_BUS_NAME": f"{self.project_name}-events",
                "DOCUMENT_BUCKET": self.document_bucket.bucket_name
            },
            log_retention=logs.RetentionDays.ONE_WEEK
        )

        return functions

    def _create_agent_action_role(self) -> iam.Role:
        """
        Create IAM role for agent action Lambda with additional permissions.
        
        Returns:
            iam.Role: IAM role for agent action handler
        """
        return iam.Role(
            self, "AgentActionRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole"),
                iam.ManagedPolicy.from_aws_managed_policy_name("AWSXRayDaemonWriteAccess")
            ],
            inline_policies={
                "AgentActionPolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:GetObject",
                                "s3:ListBucket"
                            ],
                            resources=[
                                self.document_bucket.bucket_arn,
                                f"{self.document_bucket.bucket_arn}/*"
                            ]
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=["events:PutEvents"],
                            resources=[f"arn:aws:events:{self.region}:{self.account}:event-bus/*"]
                        )
                    ]
                )
            }
        )

    def _create_event_rules(self) -> Dict[str, events.Rule]:
        """
        Create EventBridge rules for intelligent event routing.
        
        Returns:
            Dict[str, events.Rule]: Dictionary of EventBridge rules
        """
        rules = {}

        # High-confidence approval rule
        rules['approval'] = events.Rule(
            self, "ApprovalRule",
            rule_name=f"{self.project_name}-approval-rule",
            event_bus=self.event_bus,
            event_pattern=events.EventPattern(
                source=["bedrock.agent"],
                detail_type=["Document Analysis Complete"],
                detail={
                    "recommendation": ["APPROVE"],
                    "confidence_score": events.Match.all_of(
                        events.Match.greater_than_or_equal_to(0.8)
                    )
                }
            ),
            description="Route high-confidence approvals",
            targets=[targets.LambdaFunction(self.lambda_functions['approval'])]
        )

        # Document processing rule
        rules['processing'] = events.Rule(
            self, "ProcessingRule",
            rule_name=f"{self.project_name}-processing-rule",
            event_bus=self.event_bus,
            event_pattern=events.EventPattern(
                source=["bedrock.agent"],
                detail_type=["Document Analysis Complete"],
                detail={
                    "document_type": ["invoice", "contract", "compliance"]
                }
            ),
            description="Route documents for automated processing",
            targets=[targets.LambdaFunction(self.lambda_functions['processing'])]
        )

        # Alert and notification rule
        rules['alert'] = events.Rule(
            self, "AlertRule",
            rule_name=f"{self.project_name}-alert-rule",
            event_bus=self.event_bus,
            event_pattern=events.EventPattern(
                source=["bedrock.agent"],
                detail_type=["Document Analysis Complete"],
                detail={
                    "alert_type": ["high_priority", "compliance_issue", "error"]
                }
            ),
            description="Route alerts and notifications",
            targets=[targets.LambdaFunction(self.lambda_functions['notification'])]
        )

        return rules

    def _create_bedrock_agent(self) -> Any:
        """
        Create Bedrock Agent with action groups for business process automation.
        
        Returns:
            Any: Bedrock Agent configuration (using L1 constructs)
        """
        # Create IAM role for Bedrock Agent
        agent_role = iam.Role(
            self, "BedrockAgentRole",
            role_name=f"{self.project_name}-agent-role",
            assumed_by=iam.ServicePrincipal("bedrock.amazonaws.com"),
            inline_policies={
                "BedrockAgentPolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "bedrock:InvokeModel",
                                "bedrock:Retrieve"
                            ],
                            resources=["*"]
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:GetObject",
                                "s3:ListBucket"
                            ],
                            resources=[
                                self.document_bucket.bucket_arn,
                                f"{self.document_bucket.bucket_arn}/*"
                            ]
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=["events:PutEvents"],
                            resources=[self.event_bus.event_bus_arn]
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=["lambda:InvokeFunction"],
                            resources=[self.lambda_functions['agent_action'].function_arn]
                        )
                    ]
                )
            }
        )

        # Grant Lambda invoke permission to Bedrock Agent
        self.lambda_functions['agent_action'].grant_invoke(agent_role)

        # Create action group schema in S3
        action_schema = self._get_action_schema()
        schema_deployment = cdk.BucketDeployment(
            self, "ActionSchemaDeployment",
            sources=[cdk.Source.data("action-schema.json", json.dumps(action_schema, indent=2))],
            destination_bucket=self.document_bucket,
            destination_key_prefix="schemas/"
        )

        # Create Bedrock Agent using L1 constructs
        agent = bedrock.CfnAgent(
            self, "BusinessProcessAgent",
            agent_name=f"{self.project_name}-agent",
            agent_resource_role_arn=agent_role.role_arn,
            foundation_model="anthropic.claude-3-sonnet-20240229-v1:0",
            instruction=(
                "You are a business process automation agent. Analyze documents uploaded to S3, "
                "extract key information, make recommendations for approval or processing, and "
                "trigger appropriate business workflows through EventBridge events. Focus on "
                "accuracy, compliance, and efficient processing."
            ),
            description="AI agent for intelligent business process automation",
            action_groups=[
                bedrock.CfnAgent.AgentActionGroupProperty(
                    action_group_name="DocumentProcessing",
                    description="Action group for business document processing and workflow automation",
                    action_group_executor=bedrock.CfnAgent.ActionGroupExecutorProperty(
                        lambda_=self.lambda_functions['agent_action'].function_arn
                    ),
                    api_schema=bedrock.CfnAgent.APISchemaProperty(
                        s3=bedrock.CfnAgent.S3IdentifierProperty(
                            s3_bucket_name=self.document_bucket.bucket_name,
                            s3_object_key="schemas/action-schema.json"
                        )
                    )
                )
            ]
        )

        # Create agent alias for production use
        agent_alias = bedrock.CfnAgentAlias(
            self, "AgentAlias",
            agent_alias_name="production",
            agent_id=agent.attr_agent_id,
            description="Production alias for business automation agent"
        )

        # Add dependency to ensure schema is uploaded first
        agent.node.add_dependency(schema_deployment)
        
        return {
            'agent': agent,
            'agent_alias': agent_alias,
            'agent_role': agent_role
        }

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for external integration."""
        CfnOutput(
            self, "DocumentBucketName",
            value=self.document_bucket.bucket_name,
            description="S3 bucket for document storage",
            export_name=f"{self.stack_name}-DocumentBucket"
        )

        CfnOutput(
            self, "EventBusName",
            value=self.event_bus.event_bus_name,
            description="EventBridge event bus for workflow orchestration",
            export_name=f"{self.stack_name}-EventBus"
        )

        CfnOutput(
            self, "BedrockAgentId",
            value=self.bedrock_agent['agent'].attr_agent_id,
            description="Bedrock Agent ID for business process automation",
            export_name=f"{self.stack_name}-AgentId"
        )

        CfnOutput(
            self, "BedrockAgentAliasId",
            value=self.bedrock_agent['agent_alias'].attr_agent_alias_id,
            description="Bedrock Agent Alias ID for production use",
            export_name=f"{self.stack_name}-AgentAliasId"
        )

    def _get_approval_handler_code(self) -> str:
        """Get the Python code for the approval handler Lambda function."""
        return '''
import json
import boto3
import uuid
from datetime import datetime

def lambda_handler(event, context):
    print(f"Processing approval event: {json.dumps(event)}")
    
    # Extract document details from EventBridge event
    detail = event['detail']
    document_name = detail['document_name']
    confidence_score = detail['confidence_score']
    recommendation = detail['recommendation']
    
    # Simulate approval logic based on AI recommendation
    if confidence_score > 0.85 and recommendation == 'APPROVE':
        status = 'AUTO_APPROVED'
        action = 'Document automatically approved'
    else:
        status = 'PENDING_REVIEW'
        action = 'Document requires human review'
    
    # Log the decision
    result = {
        'process_id': str(uuid.uuid4()),
        'timestamp': datetime.utcnow().isoformat(),
        'document_name': document_name,
        'status': status,
        'action': action,
        'confidence_score': confidence_score
    }
    
    print(f"Approval result: {json.dumps(result)}")
    return {'statusCode': 200, 'body': json.dumps(result)}
'''

    def _get_processing_handler_code(self) -> str:
        """Get the Python code for the processing handler Lambda function."""
        return '''
import json
import boto3
import uuid
from datetime import datetime

def lambda_handler(event, context):
    print(f"Processing automation event: {json.dumps(event)}")
    
    detail = event['detail']
    document_name = detail['document_name']
    document_type = detail['document_type']
    extracted_data = detail.get('extracted_data', {})
    
    # Simulate different processing based on document type
    processing_actions = {
        'invoice': 'Initiated payment processing workflow',
        'contract': 'Routed to legal team for final review',
        'compliance': 'Submitted to regulatory reporting system',
        'default': 'Archived for future reference'
    }
    
    action = processing_actions.get(document_type, processing_actions['default'])
    
    result = {
        'process_id': str(uuid.uuid4()),
        'timestamp': datetime.utcnow().isoformat(),
        'document_name': document_name,
        'document_type': document_type,
        'action': action,
        'data_extracted': len(extracted_data) > 0
    }
    
    print(f"Processing result: {json.dumps(result)}")
    return {'statusCode': 200, 'body': json.dumps(result)}
'''

    def _get_notification_handler_code(self) -> str:
        """Get the Python code for the notification handler Lambda function."""
        return '''
import json
import boto3
import uuid
from datetime import datetime

def lambda_handler(event, context):
    print(f"Processing notification event: {json.dumps(event)}")
    
    detail = event['detail']
    document_name = detail['document_name']
    alert_type = detail['alert_type']
    message = detail['message']
    
    # Simulate notification routing
    notification_channels = {
        'high_priority': ['email', 'slack', 'sms'],
        'medium_priority': ['email', 'slack'],
        'low_priority': ['email']
    }
    
    channels = notification_channels.get(alert_type, ['email'])
    
    result = {
        'notification_id': str(uuid.uuid4()),
        'timestamp': datetime.utcnow().isoformat(),
        'document_name': document_name,
        'alert_type': alert_type,
        'message': message,
        'channels': channels,
        'status': 'sent'
    }
    
    print(f"Notification result: {json.dumps(result)}")
    return {'statusCode': 200, 'body': json.dumps(result)}
'''

    def _get_agent_action_handler_code(self) -> str:
        """Get the Python code for the agent action handler Lambda function."""
        return '''
import json
import boto3
import os
from datetime import datetime

s3_client = boto3.client('s3')
events_client = boto3.client('events')

def lambda_handler(event, context):
    print(f"Agent action request: {json.dumps(event)}")
    
    # Parse agent request
    action_request = event['actionRequest']
    api_path = action_request['apiPath']
    parameters = action_request.get('parameters', [])
    
    # Extract parameters
    document_path = None
    document_type = None
    
    for param in parameters:
        if param['name'] == 'document_path':
            document_path = param['value']
        elif param['name'] == 'document_type':
            document_type = param['value']
    
    if api_path == '/analyze-document':
        result = analyze_document(document_path, document_type)
        
        # Publish event to EventBridge
        publish_event(result, document_type)
        
        return {
            'response': {
                'actionResponse': {
                    'responseBody': result
                }
            }
        }
    
    return {
        'response': {
            'actionResponse': {
                'responseBody': {'error': 'Unknown action'}
            }
        }
    }

def analyze_document(document_path, document_type):
    # Simulate document analysis with different results based on type
    analysis_results = {
        'invoice': {
            'recommendation': 'APPROVE',
            'confidence_score': 0.92,
            'extracted_data': {
                'amount': 1250.00,
                'vendor': 'TechSupplies Inc',
                'due_date': '2024-01-15'
            },
            'alert_type': 'medium_priority',
            'message': 'Invoice processed successfully'
        },
        'contract': {
            'recommendation': 'REVIEW',
            'confidence_score': 0.75,
            'extracted_data': {
                'contract_value': 50000.00,
                'term_length': '12 months',
                'party': 'Global Services LLC'
            },
            'alert_type': 'high_priority',
            'message': 'Contract requires legal review'
        },
        'compliance': {
            'recommendation': 'APPROVE',
            'confidence_score': 0.88,
            'extracted_data': {
                'regulation': 'SOX',
                'compliance_score': 95,
                'review_date': '2024-01-01'
            },
            'alert_type': 'low_priority',
            'message': 'Compliance document approved'
        }
    }
    
    return analysis_results.get(document_type, {
        'recommendation': 'REVIEW',
        'confidence_score': 0.5,
        'extracted_data': {},
        'alert_type': 'medium_priority',
        'message': 'Document requires manual review'
    })

def publish_event(analysis_result, document_type):
    event_detail = {
        'document_name': 'sample-document.pdf',
        'document_type': document_type,
        'timestamp': datetime.utcnow().isoformat(),
        **analysis_result
    }
    
    event_bus_name = os.environ.get('EVENT_BUS_NAME')
    
    try:
        events_client.put_events(
            Entries=[
                {
                    'Source': 'bedrock.agent',
                    'DetailType': 'Document Analysis Complete',
                    'Detail': json.dumps(event_detail),
                    'EventBusName': event_bus_name
                }
            ]
        )
        print(f"Event published successfully to {event_bus_name}")
    except Exception as e:
        print(f"Error publishing event: {str(e)}")
'''

    def _get_action_schema(self) -> Dict[str, Any]:
        """Get the OpenAPI schema for agent action groups."""
        return {
            "openAPIVersion": "3.0.0",
            "info": {
                "title": "Business Process Automation API",
                "version": "1.0.0",
                "description": "API for AI agent business process automation"
            },
            "paths": {
                "/analyze-document": {
                    "post": {
                        "description": "Analyze business document and trigger appropriate workflows",
                        "parameters": [
                            {
                                "name": "document_path",
                                "in": "query",
                                "description": "S3 path to the document",
                                "required": True,
                                "schema": {"type": "string"}
                            },
                            {
                                "name": "document_type",
                                "in": "query",
                                "description": "Type of document (invoice, contract, compliance)",
                                "required": True,
                                "schema": {"type": "string"}
                            }
                        ],
                        "responses": {
                            "200": {
                                "description": "Document analysis completed",
                                "content": {
                                    "application/json": {
                                        "schema": {
                                            "type": "object",
                                            "properties": {
                                                "recommendation": {"type": "string"},
                                                "confidence_score": {"type": "number"},
                                                "extracted_data": {"type": "object"},
                                                "next_actions": {"type": "array"}
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }


# CDK App instantiation
app = cdk.App()

# Create the business process automation stack
BusinessProcessAutomationStack(
    app, "BusinessProcessAutomationStack",
    description="Intelligent business process automation with Bedrock Agents and EventBridge",
    env=cdk.Environment(
        account=os.environ.get('CDK_DEFAULT_ACCOUNT'),
        region=os.environ.get('CDK_DEFAULT_REGION', 'us-east-1')
    )
)

app.synth()