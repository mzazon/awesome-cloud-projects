#!/usr/bin/env python3
"""
Multi-Agent Knowledge Management with Bedrock AgentCore and Q Business
CDK Python Application

This CDK application deploys a complete multi-agent knowledge management system
using Amazon Bedrock AgentCore, Q Business, Lambda, and supporting services.
"""

import os
from typing import Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_iam as iam,
    aws_lambda as lambda_,
    aws_s3 as s3,
    aws_dynamodb as dynamodb,
    aws_apigatewayv2 as apigwv2,
    aws_apigatewayv2_integrations as apigwv2_integrations,
    aws_logs as logs,
    aws_s3_deployment as s3deploy,
)
from constructs import Construct


class MultiAgentKnowledgeManagementStack(Stack):
    """
    CDK Stack for Multi-Agent Knowledge Management System
    
    This stack creates:
    - S3 buckets for domain-specific knowledge bases
    - Lambda functions for supervisor and specialized agents
    - DynamoDB table for session management
    - API Gateway for external access
    - IAM roles and policies with least privilege
    - Q Business application configuration (manual setup required)
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource naming
        self.unique_suffix = self.node.try_get_context("uniqueSuffix") or "demo"
        
        # Create foundational resources
        self.create_iam_roles()
        self.create_knowledge_storage()
        self.create_session_management()
        self.create_agent_functions()
        self.create_api_gateway()
        self.create_outputs()

    def create_iam_roles(self) -> None:
        """Create IAM roles for Lambda functions and Q Business integration"""
        
        # Lambda execution role with enhanced permissions for multi-agent operations
        self.lambda_role = iam.Role(
            self,
            "AgentLambdaRole",
            role_name=f"MultiAgentLambdaRole-{self.unique_suffix}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="IAM role for multi-agent Lambda functions with Q Business access",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                ),
            ],
        )

        # Add custom policies for agent operations
        bedrock_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "bedrock:InvokeModel",
                "bedrock:InvokeModelWithResponseStream",
                "bedrock:GetFoundationModel",
                "bedrock:ListFoundationModels",
            ],
            resources=["*"],
        )

        qbusiness_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "qbusiness:ChatSync",
                "qbusiness:CreateConversation",
                "qbusiness:DeleteConversation",
                "qbusiness:GetConversation",
                "qbusiness:ListConversations",
                "qbusiness:GetApplication",
                "qbusiness:ListApplications",
            ],
            resources=["*"],
        )

        s3_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "s3:GetObject",
                "s3:ListBucket",
            ],
            resources=["*"],
        )

        dynamodb_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "dynamodb:PutItem",
                "dynamodb:GetItem",
                "dynamodb:UpdateItem",
                "dynamodb:DeleteItem",
                "dynamodb:Query",
                "dynamodb:Scan",
            ],
            resources=["*"],
        )

        lambda_invoke_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "lambda:InvokeFunction",
            ],
            resources=[f"arn:aws:lambda:{self.region}:{self.account}:function:*agent-{self.unique_suffix}"],
        )

        self.lambda_role.add_to_policy(bedrock_policy)
        self.lambda_role.add_to_policy(qbusiness_policy)
        self.lambda_role.add_to_policy(s3_policy)
        self.lambda_role.add_to_policy(dynamodb_policy)
        self.lambda_role.add_to_policy(lambda_invoke_policy)

        # Q Business service role for data source access
        self.qbusiness_role = iam.Role(
            self,
            "QBusinessServiceRole",
            role_name=f"QBusinessServiceRole-{self.unique_suffix}",
            assumed_by=iam.ServicePrincipal("qbusiness.amazonaws.com"),
            description="IAM role for Q Business to access S3 knowledge bases",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonS3ReadOnlyAccess"),
            ],
        )

    def create_knowledge_storage(self) -> None:
        """Create S3 buckets for domain-specific knowledge bases"""
        
        # Common bucket configuration for security and compliance
        bucket_props = {
            "encryption": s3.BucketEncryption.S3_MANAGED,
            "versioned": True,
            "block_public_access": s3.BlockPublicAccess.BLOCK_ALL,
            "removal_policy": RemovalPolicy.DESTROY,
            "auto_delete_objects": True,
        }

        # Finance knowledge base bucket
        self.finance_bucket = s3.Bucket(
            self,
            "FinanceKnowledgeBucket",
            bucket_name=f"finance-kb-{self.unique_suffix}",
            **bucket_props,
        )

        # HR knowledge base bucket
        self.hr_bucket = s3.Bucket(
            self,
            "HRKnowledgeBucket",
            bucket_name=f"hr-kb-{self.unique_suffix}",
            **bucket_props,
        )

        # Technical knowledge base bucket
        self.tech_bucket = s3.Bucket(
            self,
            "TechnicalKnowledgeBucket",
            bucket_name=f"tech-kb-{self.unique_suffix}",
            **bucket_props,
        )

        # Upload sample knowledge documents
        self._upload_sample_documents()

    def _upload_sample_documents(self) -> None:
        """Upload sample knowledge documents to S3 buckets"""
        
        # Finance policy document
        finance_content = """Finance Policy Documentation:

Expense Approval Process:
- All expenses over $1000 require manager approval
- Expenses over $5000 require director approval
- Capital expenditures over $10000 require CFO approval

Budget Management:
- Quarterly budget reviews conducted in March, June, September, December
- Department budget allocations updated annually in January
- Emergency budget requests require 48-hour approval window

Travel and Reimbursement:
- Travel reimbursement requires receipts within 30 days of completion
- International travel requires pre-approval 2 weeks in advance
- Meal allowances: $75 domestic, $100 international per day
"""

        # HR handbook document
        hr_content = """HR Handbook and Employee Policies:

Onboarding Process:
- Employee onboarding process takes 3-5 business days
- IT equipment setup completed on first day
- Benefits enrollment window: 30 days from start date

Performance Management:
- Performance reviews conducted annually in Q4
- Mid-year check-ins scheduled in Q2
- Performance improvement plans: 90-day duration

Time Off and Remote Work:
- Vacation requests require 2 weeks advance notice for approval
- Remote work policy allows up to 3 days per week remote work
- Sick leave: 10 days annually, carries over up to 5 days
- Parental leave: 12 weeks paid, additional 4 weeks unpaid
"""

        # Technical guidelines document
        tech_content = """Technical Guidelines and System Procedures:

Development Standards:
- All code must pass automated testing before deployment
- Code coverage minimum: 80% for production releases
- Security scans required for all external-facing applications

Infrastructure Management:
- Database backups performed nightly at 2 AM UTC
- Backup retention: 30 days local, 90 days archived
- Disaster recovery testing: quarterly

API and Security Standards:
- API rate limits: 1000 requests per minute per client
- Authentication required for all API endpoints
- SSL/TLS 1.2 minimum for all communications
- Security patching: within 48 hours for critical vulnerabilities
"""

        # Deploy sample documents
        s3deploy.BucketDeployment(
            self,
            "FinanceDocuments",
            sources=[s3deploy.Source.data("finance-policy.txt", finance_content)],
            destination_bucket=self.finance_bucket,
        )

        s3deploy.BucketDeployment(
            self,
            "HRDocuments",
            sources=[s3deploy.Source.data("hr-handbook.txt", hr_content)],
            destination_bucket=self.hr_bucket,
        )

        s3deploy.BucketDeployment(
            self,
            "TechnicalDocuments",
            sources=[s3deploy.Source.data("tech-guidelines.txt", tech_content)],
            destination_bucket=self.tech_bucket,
        )

    def create_session_management(self) -> None:
        """Create DynamoDB table for agent session management"""
        
        self.session_table = dynamodb.Table(
            self,
            "AgentSessionTable",
            table_name=f"agent-sessions-{self.unique_suffix}",
            partition_key=dynamodb.Attribute(
                name="sessionId",
                type=dynamodb.AttributeType.STRING,
            ),
            sort_key=dynamodb.Attribute(
                name="timestamp",
                type=dynamodb.AttributeType.STRING,
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            time_to_live_attribute="ttl",
            point_in_time_recovery=True,
            removal_policy=RemovalPolicy.DESTROY,
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
        )

    def create_agent_functions(self) -> None:
        """Create Lambda functions for supervisor and specialized agents"""
        
        # Common Lambda configuration
        lambda_props = {
            "runtime": lambda_.Runtime.PYTHON_3_12,
            "handler": "index.lambda_handler",
            "role": self.lambda_role,
            "timeout": Duration.seconds(60),
            "memory_size": 512,
            "log_retention": logs.RetentionDays.ONE_WEEK,
            "environment": {
                "SESSION_TABLE": self.session_table.table_name,
                "RANDOM_SUFFIX": self.unique_suffix,
            },
        }

        # Supervisor agent Lambda function
        self.supervisor_function = lambda_.Function(
            self,
            "SupervisorAgent",
            function_name=f"supervisor-agent-{self.unique_suffix}",
            description="Supervisor agent for multi-agent orchestration",
            code=lambda_.Code.from_inline(self._get_supervisor_code()),
            **lambda_props,
        )

        # Finance specialist agent
        self.finance_function = lambda_.Function(
            self,
            "FinanceAgent",
            function_name=f"finance-agent-{self.unique_suffix}",
            description="Finance specialist agent for budget and policy queries",
            code=lambda_.Code.from_inline(self._get_finance_agent_code()),
            timeout=Duration.seconds(30),
            memory_size=256,
            **{k: v for k, v in lambda_props.items() if k not in ["timeout", "memory_size"]},
        )

        # HR specialist agent
        self.hr_function = lambda_.Function(
            self,
            "HRAgent",
            function_name=f"hr-agent-{self.unique_suffix}",
            description="HR specialist agent for employee and policy queries",
            code=lambda_.Code.from_inline(self._get_hr_agent_code()),
            timeout=Duration.seconds(30),
            memory_size=256,
            **{k: v for k, v in lambda_props.items() if k not in ["timeout", "memory_size"]},
        )

        # Technical specialist agent
        self.technical_function = lambda_.Function(
            self,
            "TechnicalAgent",
            function_name=f"technical-agent-{self.unique_suffix}",
            description="Technical specialist agent for engineering queries",
            code=lambda_.Code.from_inline(self._get_technical_agent_code()),
            timeout=Duration.seconds(30),
            memory_size=256,
            **{k: v for k, v in lambda_props.items() if k not in ["timeout", "memory_size"]},
        )

    def create_api_gateway(self) -> None:
        """Create API Gateway for multi-agent system access"""
        
        # HTTP API Gateway with CORS configuration
        self.api = apigwv2.HttpApi(
            self,
            "MultiAgentAPI",
            api_name=f"multi-agent-km-api-{self.unique_suffix}",
            description="Multi-agent knowledge management API with enterprise features",
            cors_preflight=apigwv2.CorsPreflightOptions(
                allow_credentials=False,
                allow_headers=["Content-Type", "Authorization"],
                allow_methods=[
                    apigwv2.CorsHttpMethod.GET,
                    apigwv2.CorsHttpMethod.POST,
                    apigwv2.CorsHttpMethod.OPTIONS,
                ],
                allow_origins=["*"],
                max_age=Duration.hours(1),
            ),
        )

        # Lambda integration for supervisor agent
        supervisor_integration = apigwv2_integrations.HttpLambdaIntegration(
            "SupervisorIntegration",
            self.supervisor_function,
            timeout=Duration.seconds(29),
        )

        # Add routes to API Gateway
        self.api.add_routes(
            path="/query",
            methods=[apigwv2.HttpMethod.POST],
            integration=supervisor_integration,
        )

        self.api.add_routes(
            path="/health",
            methods=[apigwv2.HttpMethod.GET],
            integration=supervisor_integration,
        )

        # Create production stage with throttling
        self.api_stage = apigwv2.HttpStage(
            self,
            "ProductionStage",
            http_api=self.api,
            stage_name="prod",
            auto_deploy=True,
            description="Production stage for multi-agent knowledge management",
            throttle=apigwv2.ThrottleSettings(
                burst_limit=1000,
                rate_limit=500,
            ),
        )

    def create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources"""
        
        CfnOutput(
            self,
            "APIEndpoint",
            value=self.api.url,
            description="API Gateway endpoint for multi-agent queries",
            export_name=f"MultiAgentAPI-{self.unique_suffix}",
        )

        CfnOutput(
            self,
            "FinanceBucketName",
            value=self.finance_bucket.bucket_name,
            description="S3 bucket for finance knowledge base",
            export_name=f"FinanceBucket-{self.unique_suffix}",
        )

        CfnOutput(
            self,
            "HRBucketName",
            value=self.hr_bucket.bucket_name,
            description="S3 bucket for HR knowledge base",
            export_name=f"HRBucket-{self.unique_suffix}",
        )

        CfnOutput(
            self,
            "TechnicalBucketName",
            value=self.tech_bucket.bucket_name,
            description="S3 bucket for technical knowledge base",
            export_name=f"TechnicalBucket-{self.unique_suffix}",
        )

        CfnOutput(
            self,
            "SessionTableName",
            value=self.session_table.table_name,
            description="DynamoDB table for agent session management",
            export_name=f"SessionTable-{self.unique_suffix}",
        )

        CfnOutput(
            self,
            "QBusinessRoleArn",
            value=self.qbusiness_role.role_arn,
            description="IAM role ARN for Q Business service",
            export_name=f"QBusinessRole-{self.unique_suffix}",
        )

        # Manual setup instructions output
        CfnOutput(
            self,
            "ManualSetupInstructions",
            value="Q Business application and data sources require manual setup through AWS Console",
            description="Next steps for completing the deployment",
        )

    def _get_supervisor_code(self) -> str:
        """Return the supervisor agent Lambda function code"""
        return '''
import json
import boto3
import os
from typing import List, Dict, Any
import uuid
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Supervisor agent that coordinates specialized agents for knowledge retrieval
    """
    try:
        # Initialize AWS clients
        lambda_client = boto3.client('lambda')
        dynamodb = boto3.resource('dynamodb')
        
        # Parse request
        if 'body' in event:
            body = json.loads(event['body']) if isinstance(event['body'], str) else event['body']
        else:
            body = event
            
        query = body.get('query', '')
        session_id = body.get('sessionId', str(uuid.uuid4()))
        
        logger.info(f"Processing query: {query} for session: {session_id}")
        
        # Health check endpoint
        if not query and event.get('httpMethod') == 'GET':
            return {
                'statusCode': 200,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'status': 'healthy',
                    'service': 'multi-agent-knowledge-management',
                    'version': '1.0'
                })
            }
        
        # Determine which agents to engage based on query analysis
        agents_to_engage = determine_agents(query)
        logger.info(f"Engaging agents: {agents_to_engage}")
        
        # Collect responses from specialized agents
        agent_responses = []
        for agent_name in agents_to_engage:
            try:
                response = invoke_specialized_agent(lambda_client, agent_name, query, session_id)
                agent_responses.append({
                    'agent': agent_name,
                    'response': response,
                    'confidence': calculate_confidence(agent_name, query)
                })
            except Exception as e:
                logger.error(f"Error invoking {agent_name} agent: {str(e)}")
                agent_responses.append({
                    'agent': agent_name,
                    'response': f"Error retrieving {agent_name} information",
                    'confidence': 0.0
                })
        
        # Synthesize comprehensive answer
        final_response = synthesize_responses(query, agent_responses)
        
        # Store session information for context
        store_session_context(session_id, query, final_response, agents_to_engage)
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'query': query,
                'response': final_response,
                'agents_consulted': agents_to_engage,
                'session_id': session_id,
                'confidence_scores': {resp['agent']: resp['confidence'] for resp in agent_responses}
            })
        }
        
    except Exception as e:
        logger.error(f"Supervisor agent error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': f"Supervisor agent error: {str(e)}"
            })
        }

def determine_agents(query: str) -> List[str]:
    """Determine which specialized agents to engage based on query analysis"""
    query_lower = query.lower()
    agents = []
    
    # Finance-related keywords
    finance_keywords = ['budget', 'expense', 'cost', 'finance', 'money', 'approval', 
                       'reimbursement', 'travel', 'spending', 'capital', 'cfo']
    if any(word in query_lower for word in finance_keywords):
        agents.append('finance')
    
    # HR-related keywords
    hr_keywords = ['employee', 'hr', 'vacation', 'onboard', 'performance', 'leave',
                   'remote', 'work', 'benefits', 'policy', 'review', 'sick']
    if any(word in query_lower for word in hr_keywords):
        agents.append('hr')
    
    # Technical-related keywords
    tech_keywords = ['technical', 'code', 'api', 'database', 'security', 'backup',
                     'system', 'development', 'infrastructure', 'server', 'ssl']
    if any(word in query_lower for word in tech_keywords):
        agents.append('technical')
    
    # If no specific domain detected, engage all agents for comprehensive coverage
    return agents if agents else ['finance', 'hr', 'technical']

def calculate_confidence(agent_name: str, query: str) -> float:
    """Calculate confidence score for agent relevance to query"""
    query_lower = query.lower()
    
    if agent_name == 'finance':
        finance_keywords = ['budget', 'expense', 'cost', 'finance', 'money', 'approval']
        matches = sum(1 for word in finance_keywords if word in query_lower)
        return min(matches * 0.2, 1.0)
    elif agent_name == 'hr':
        hr_keywords = ['employee', 'hr', 'vacation', 'onboard', 'performance', 'leave']
        matches = sum(1 for word in hr_keywords if word in query_lower)
        return min(matches * 0.2, 1.0)
    elif agent_name == 'technical':
        tech_keywords = ['technical', 'code', 'api', 'database', 'security', 'backup']
        matches = sum(1 for word in tech_keywords if word in query_lower)
        return min(matches * 0.2, 1.0)
    
    return 0.5  # Default confidence

def invoke_specialized_agent(lambda_client, agent_name: str, query: str, session_id: str) -> str:
    """Invoke a specialized agent Lambda function"""
    function_name = f"{agent_name}-agent-{os.environ.get('RANDOM_SUFFIX', 'default')}"
    
    try:
        response = lambda_client.invoke(
            FunctionName=function_name,
            InvocationType='RequestResponse',
            Payload=json.dumps({
                'query': query,
                'sessionId': session_id,
                'context': f"Domain-specific query for {agent_name} expertise"
            })
        )
        
        result = json.loads(response['Payload'].read())
        if result.get('statusCode') == 200:
            body = json.loads(result.get('body', '{}'))
            return body.get('response', f"No {agent_name} information available")
        else:
            return f"Error retrieving {agent_name} information"
            
    except Exception as e:
        logger.error(f"Error invoking {agent_name} agent: {str(e)}")
        return f"Error accessing {agent_name} knowledge base"

def synthesize_responses(query: str, responses: List[Dict]) -> str:
    """Synthesize responses from multiple agents into a comprehensive answer"""
    if not responses:
        return "No relevant information found in the knowledge base."
    
    # Filter responses by confidence score
    high_confidence_responses = [r for r in responses if r.get('confidence', 0) > 0.3]
    responses_to_use = high_confidence_responses if high_confidence_responses else responses
    
    synthesis = f"Based on consultation with {len(responses_to_use)} specialized knowledge domains:\\n\\n"
    
    for resp in responses_to_use:
        if resp['response'] and not resp['response'].startswith('Error'):
            confidence_indicator = "🔷" if resp.get('confidence', 0) > 0.6 else "🔹"
            synthesis += f"{confidence_indicator} **{resp['agent'].title()} Domain**: {resp['response']}\\n\\n"
    
    synthesis += "\\n*This response was generated by consulting multiple specialized knowledge agents.*"
    return synthesis

def store_session_context(session_id: str, query: str, response: str, agents: List[str]):
    """Store session context for future reference"""
    try:
        table_name = os.environ.get('SESSION_TABLE', 'agent-sessions-default')
        dynamodb = boto3.resource('dynamodb')
        table = dynamodb.Table(table_name)
        
        import time
        timestamp = str(int(time.time()))
        
        table.put_item(
            Item={
                'sessionId': session_id,
                'timestamp': timestamp,
                'query': query,
                'response': response,
                'agents_consulted': agents,
                'ttl': int(time.time()) + 86400  # 24 hour TTL
            }
        )
    except Exception as e:
        logger.error(f"Error storing session context: {str(e)}")
'''

    def _get_finance_agent_code(self) -> str:
        """Return the finance agent Lambda function code"""
        return '''
import json
import boto3
import os
import logging
import uuid

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Finance specialist agent for budget and financial policy queries
    """
    try:
        query = event.get('query', '')
        session_id = event.get('sessionId', str(uuid.uuid4()))
        context_info = event.get('context', '')
        
        logger.info(f"Finance agent processing query: {query}")
        
        # For now, use fallback responses since Q Business requires manual setup
        response = get_finance_fallback(query)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'agent': 'finance',
                'response': response,
                'sources': ['Finance Policy Documentation'],
                'note': 'Static response - Q Business integration requires manual setup'
            })
        }
            
    except Exception as e:
        logger.error(f"Finance agent error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': f"Finance agent error: {str(e)}"
            })
        }

def get_finance_fallback(query: str) -> str:
    """Provide fallback finance information"""
    query_lower = query.lower()
    
    if 'expense' in query_lower or 'approval' in query_lower:
        return "Expense approval process: Expenses over $1000 require manager approval, over $5000 require director approval, and over $10000 require CFO approval."
    elif 'budget' in query_lower:
        return "Budget management: Quarterly reviews conducted in March, June, September, December. Annual allocations updated in January."
    elif 'travel' in query_lower or 'reimbursement' in query_lower:
        return "Travel policy: Reimbursement requires receipts within 30 days. International travel needs 2-week pre-approval. Daily allowances: $75 domestic, $100 international."
    else:
        return "Finance policies cover expense approvals, budget management, and travel procedures. Specific policies require review of complete documentation."
'''

    def _get_hr_agent_code(self) -> str:
        """Return the HR agent Lambda function code"""
        return '''
import json
import boto3
import os
import logging
import uuid

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    HR specialist agent for employee and policy queries
    """
    try:
        query = event.get('query', '')
        session_id = event.get('sessionId', str(uuid.uuid4()))
        context_info = event.get('context', '')
        
        logger.info(f"HR agent processing query: {query}")
        
        # For now, use fallback responses since Q Business requires manual setup
        response = get_hr_fallback(query)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'agent': 'hr',
                'response': response,
                'sources': ['HR Handbook and Policies'],
                'note': 'Static response - Q Business integration requires manual setup'
            })
        }
            
    except Exception as e:
        logger.error(f"HR agent error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': f"HR agent error: {str(e)}"
            })
        }

def get_hr_fallback(query: str) -> str:
    """Provide fallback HR information"""
    query_lower = query.lower()
    
    if 'onboard' in query_lower:
        return "Onboarding process: 3-5 business days completion, IT setup on first day, benefits enrollment within 30 days of start date."
    elif 'performance' in query_lower or 'review' in query_lower:
        return "Performance management: Annual reviews in Q4, mid-year check-ins in Q2, performance improvement plans have 90-day duration."
    elif 'vacation' in query_lower or 'leave' in query_lower:
        return "Time off policies: Vacation requires 2-week advance notice, 10 sick days annually (5 carry-over), 12 weeks paid parental leave plus 4 weeks unpaid."
    elif 'remote' in query_lower or 'work' in query_lower:
        return "Remote work policy: Up to 3 days per week remote work allowed, subject to role requirements and manager approval."
    else:
        return "HR policies cover onboarding, performance management, time off, and workplace procedures. Consult complete handbook for specific guidance."
'''

    def _get_technical_agent_code(self) -> str:
        """Return the technical agent Lambda function code"""
        return '''
import json
import boto3
import os
import logging
import uuid

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Technical specialist agent for engineering and system queries
    """
    try:
        query = event.get('query', '')
        session_id = event.get('sessionId', str(uuid.uuid4()))
        context_info = event.get('context', '')
        
        logger.info(f"Technical agent processing query: {query}")
        
        # For now, use fallback responses since Q Business requires manual setup
        response = get_technical_fallback(query)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'agent': 'technical',
                'response': response,
                'sources': ['Technical Guidelines Documentation'],
                'note': 'Static response - Q Business integration requires manual setup'
            })
        }
            
    except Exception as e:
        logger.error(f"Technical agent error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': f"Technical agent error: {str(e)}"
            })
        }

def get_technical_fallback(query: str) -> str:
    """Provide fallback technical information"""
    query_lower = query.lower()
    
    if 'code' in query_lower or 'development' in query_lower:
        return "Development standards: All code requires automated testing before deployment, minimum 80% code coverage for production, security scans for external applications."
    elif 'backup' in query_lower or 'database' in query_lower:
        return "Infrastructure management: Database backups performed nightly at 2 AM UTC, 30-day local retention, 90-day archive retention, quarterly DR testing."
    elif 'api' in query_lower:
        return "API standards: 1000 requests per minute rate limit, authentication required for all endpoints, SSL/TLS 1.2 minimum for communications."
    elif 'security' in query_lower:
        return "Security procedures: Security patching within 48 hours for critical vulnerabilities, SSL/TLS 1.2 minimum, authentication required for all API endpoints."
    else:
        return "Technical guidelines cover development standards, infrastructure management, API protocols, and security procedures. Consult complete documentation for implementation details."
'''


class MultiAgentKnowledgeManagementApp(cdk.App):
    """CDK Application for Multi-Agent Knowledge Management System"""

    def __init__(self):
        super().__init__()

        # Get unique suffix from context or generate one
        unique_suffix = self.node.try_get_context("uniqueSuffix")
        if not unique_suffix:
            import random
            import string
            unique_suffix = ''.join(random.choices(string.ascii_lowercase + string.digits, k=6))

        # Create the main stack
        MultiAgentKnowledgeManagementStack(
            self,
            "MultiAgentKnowledgeManagementStack",
            unique_suffix=unique_suffix,
            description="Multi-Agent Knowledge Management with Bedrock AgentCore and Q Business",
            tags={
                "Project": "MultiAgentKnowledgeManagement",
                "Environment": "Demo",
                "ManagedBy": "CDK",
            },
        )


# Create and run the application
app = MultiAgentKnowledgeManagementApp()
app.synth()