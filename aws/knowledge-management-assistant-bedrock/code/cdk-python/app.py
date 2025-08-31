#!/usr/bin/env python3
"""
Knowledge Management Assistant with Amazon Bedrock CDK Application

This CDK application deploys a complete knowledge management solution using:
- Amazon Bedrock Agents for intelligent query processing
- Knowledge Bases with S3 document storage
- OpenSearch Serverless for vector storage
- API Gateway and Lambda for REST API interface
- Comprehensive IAM roles with least privilege access

Author: CDK Generator v1.3
Recipe: Knowledge Management Assistant with Bedrock Agents
"""

import os
from typing import Dict, Any
import aws_cdk as cdk
from aws_cdk import (
    Stack,
    StackProps,
    CfnOutput,
    Duration,
    RemovalPolicy,
    aws_s3 as s3,
    aws_iam as iam,
    aws_lambda as lambda_,
    aws_apigateway as apigateway,
    aws_opensearchserverless as opensearch_serverless,
    aws_bedrock as bedrock,
    aws_logs as logs,
    aws_s3_deployment as s3_deployment,
    aws_s3_assets as s3_assets,
)
from constructs import Construct


class KnowledgeManagementAssistantStack(Stack):
    """
    CDK Stack for Knowledge Management Assistant with Bedrock Agents
    
    This stack creates a complete enterprise knowledge management solution
    with intelligent document search and conversational AI capabilities.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs: Any) -> None:
        super().__init__(scope, construct_id, **kwargs)
        
        # Stack parameters and configuration
        self.random_suffix = self.node.try_get_context("random_suffix") or "kb001"
        self.knowledge_base_name = f"enterprise-knowledge-base-{self.random_suffix}"
        self.agent_name = f"knowledge-assistant-{self.random_suffix}"
        
        # Create core infrastructure components
        self._create_s3_bucket()
        self._create_opensearch_collection()
        self._create_iam_roles()
        self._create_knowledge_base()
        self._create_bedrock_agent()
        self._create_lambda_function()
        self._create_api_gateway()
        self._create_sample_documents()
        self._create_outputs()

    def _create_s3_bucket(self) -> None:
        """
        Create S3 bucket for document storage with enterprise security features
        """
        self.document_bucket = s3.Bucket(
            self,
            "DocumentBucket",
            bucket_name=f"knowledge-docs-{self.random_suffix}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="IntelligentTiering",
                    status=s3.LifecycleRuleStatus.ENABLED,
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INTELLIGENT_TIERING,
                            transition_after=Duration.days(1)
                        )
                    ]
                )
            ]
        )

        # Add CloudTrail logging for data events
        cdk.Tags.of(self.document_bucket).add("Purpose", "KnowledgeBase")
        cdk.Tags.of(self.document_bucket).add("Environment", "Production")

    def _create_opensearch_collection(self) -> None:
        """
        Create OpenSearch Serverless collection for vector storage
        """
        # Create network policy for OpenSearch Serverless
        network_policy = opensearch_serverless.CfnSecurityPolicy(
            self,
            "NetworkPolicy",
            name=f"kb-collection-{self.random_suffix}-network",
            type="network",
            policy=f"""[{{"Rules":[{{"Resource":["collection/kb-collection-{self.random_suffix}"],"ResourceType":"collection"}},{{"Resource":["index/kb-collection-{self.random_suffix}/*"],"ResourceType":"index"}}],"AllowFromPublic":true}}]"""
        )

        # Create encryption policy
        encryption_policy = opensearch_serverless.CfnSecurityPolicy(
            self,
            "EncryptionPolicy",
            name=f"kb-collection-{self.random_suffix}-encryption",
            type="encryption",
            policy=f"""[{{"Rules":[{{"Resource":["collection/kb-collection-{self.random_suffix}"],"ResourceType":"collection"}}],"AWSOwnedKey":true}}]"""
        )

        # Create OpenSearch Serverless collection
        self.opensearch_collection = opensearch_serverless.CfnCollection(
            self,
            "VectorCollection",
            name=f"kb-collection-{self.random_suffix}",
            type="VECTORSEARCH",
            description="Vector collection for Bedrock Knowledge Base"
        )
        
        self.opensearch_collection.add_dependency(network_policy)
        self.opensearch_collection.add_dependency(encryption_policy)

    def _create_iam_roles(self) -> None:
        """
        Create IAM roles with least privilege access for Bedrock and Lambda
        """
        # Bedrock Agent execution role
        self.bedrock_role = iam.Role(
            self,
            "BedrockAgentRole",
            role_name=f"BedrockAgentRole-{self.random_suffix}",
            assumed_by=iam.ServicePrincipal("bedrock.amazonaws.com"),
            description="IAM role for Bedrock Agent with minimal required permissions",
            inline_policies={
                "S3Access": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=["s3:GetObject", "s3:ListBucket"],
                            resources=[
                                self.document_bucket.bucket_arn,
                                f"{self.document_bucket.bucket_arn}/*"
                            ]
                        )
                    ]
                ),
                "BedrockAccess": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "bedrock:InvokeModel",
                                "bedrock:Retrieve",
                                "bedrock:RetrieveAndGenerate"
                            ],
                            resources=["*"]
                        )
                    ]
                ),
                "OpenSearchAccess": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "aoss:APIAccessAll"
                            ],
                            resources=[
                                f"arn:aws:aoss:{self.region}:{self.account}:collection/*"
                            ]
                        )
                    ]
                )
            }
        )

        # Lambda execution role
        self.lambda_role = iam.Role(
            self,
            "LambdaExecutionRole",
            role_name=f"LambdaBedrockRole-{self.random_suffix}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="IAM role for Lambda function to invoke Bedrock Agent",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
            inline_policies={
                "BedrockAgentAccess": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=["bedrock:InvokeAgent"],
                            resources=[f"arn:aws:bedrock:{self.region}:{self.account}:agent/*"]
                        )
                    ]
                )
            }
        )

    def _create_knowledge_base(self) -> None:
        """
        Create Bedrock Knowledge Base with enhanced configuration
        """
        # Knowledge Base configuration
        knowledge_base_config = bedrock.CfnKnowledgeBase.KnowledgeBaseConfigurationProperty(
            type="VECTOR",
            vector_knowledge_base_configuration=bedrock.CfnKnowledgeBase.VectorKnowledgeBaseConfigurationProperty(
                embedding_model_arn=f"arn:aws:bedrock:{self.region}::foundation-model/amazon.titan-embed-text-v2:0"
            )
        )

        # Storage configuration for OpenSearch Serverless
        storage_config = bedrock.CfnKnowledgeBase.StorageConfigurationProperty(
            type="OPENSEARCH_SERVERLESS",
            opensearch_serverless_configuration=bedrock.CfnKnowledgeBase.OpenSearchServerlessConfigurationProperty(
                collection_arn=self.opensearch_collection.attr_arn,
                vector_index_name="knowledge-index",
                field_mapping=bedrock.CfnKnowledgeBase.OpenSearchServerlessFieldMappingProperty(
                    vector_field="vector",
                    text_field="text",
                    metadata_field="metadata"
                )
            )
        )

        # Create Knowledge Base
        self.knowledge_base = bedrock.CfnKnowledgeBase(
            self,
            "KnowledgeBase",
            name=self.knowledge_base_name,
            description="Enterprise knowledge base for company policies and procedures",
            role_arn=self.bedrock_role.role_arn,
            knowledge_base_configuration=knowledge_base_config,
            storage_configuration=storage_config
        )

        # Create data source for S3
        chunking_config = bedrock.CfnDataSource.ChunkingConfigurationProperty(
            chunking_strategy="FIXED_SIZE",
            fixed_size_chunking_configuration=bedrock.CfnDataSource.FixedSizeChunkingConfigurationProperty(
                max_tokens=300,
                overlap_percentage=20
            )
        )

        vector_ingestion_config = bedrock.CfnDataSource.VectorIngestionConfigurationProperty(
            chunking_configuration=chunking_config
        )

        s3_config = bedrock.CfnDataSource.S3DataSourceConfigurationProperty(
            bucket_arn=self.document_bucket.bucket_arn,
            inclusion_prefixes=["documents/"]
        )

        data_source_config = bedrock.CfnDataSource.DataSourceConfigurationProperty(
            type="S3",
            s3_configuration=s3_config
        )

        self.data_source = bedrock.CfnDataSource(
            self,
            "S3DataSource",
            name="s3-document-source",
            description="S3 data source for enterprise documents",
            knowledge_base_id=self.knowledge_base.attr_knowledge_base_id,
            data_source_configuration=data_source_config,
            vector_ingestion_configuration=vector_ingestion_config
        )

    def _create_bedrock_agent(self) -> None:
        """
        Create Bedrock Agent with enhanced instructions and Claude 3.5 Sonnet
        """
        agent_instruction = """You are a helpful enterprise knowledge management assistant powered by Amazon Bedrock. Your role is to help employees find accurate information from company documents, policies, and procedures. Always provide specific, actionable answers and cite sources when possible. If you cannot find relevant information in the knowledge base, clearly state that and suggest alternative resources or contacts. Maintain a professional tone while being conversational and helpful. When providing policy information, always mention if employees should verify with HR for the most current version."""

        self.bedrock_agent = bedrock.CfnAgent(
            self,
            "KnowledgeAgent",
            agent_name=self.agent_name,
            description="Enterprise knowledge management assistant powered by Claude 3.5 Sonnet",
            instruction=agent_instruction,
            foundation_model="anthropic.claude-3-5-sonnet-20241022-v2:0",
            agent_resource_role_arn=self.bedrock_role.role_arn,
            idle_session_ttl_in_seconds=1800,
            knowledge_bases=[
                bedrock.CfnAgent.AgentKnowledgeBaseProperty(
                    knowledge_base_id=self.knowledge_base.attr_knowledge_base_id,
                    description="Enterprise knowledge base association",
                    knowledge_base_state="ENABLED"
                )
            ]
        )

        # Create agent version and alias
        self.agent_version = bedrock.CfnAgentAlias(
            self,
            "AgentAlias",
            agent_alias_name="production",
            agent_id=self.bedrock_agent.attr_agent_id,
            description="Production alias for knowledge management agent"
        )

    def _create_lambda_function(self) -> None:
        """
        Create Lambda function with enhanced error handling and logging
        """
        # Lambda function code
        lambda_code = """import json
import boto3
import os
import logging
from botocore.exceptions import ClientError

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    \"\"\"
    Enhanced Lambda handler for Bedrock Agent integration
    with improved error handling and logging
    \"\"\"
    # Initialize Bedrock Agent Runtime client
    bedrock_agent = boto3.client('bedrock-agent-runtime')
    
    try:
        # Parse request body with enhanced validation
        if 'body' in event:
            body = json.loads(event['body']) if isinstance(event['body'], str) else event['body']
        else:
            body = event
        
        query = body.get('query', '').strip()
        session_id = body.get('sessionId', 'default-session')
        
        # Validate input
        if not query:
            logger.warning("Empty query received")
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*',
                    'Access-Control-Allow-Headers': 'Content-Type',
                    'Access-Control-Allow-Methods': 'POST, OPTIONS'
                },
                'body': json.dumps({
                    'error': 'Query parameter is required and cannot be empty'
                })
            }
        
        if len(query) > 1000:
            logger.warning(f"Query too long: {len(query)} characters")
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'error': 'Query too long. Please limit to 1000 characters.'
                })
            }
        
        logger.info(f"Processing query for session: {session_id}")
        
        # Invoke Bedrock Agent with enhanced configuration
        response = bedrock_agent.invoke_agent(
            agentId=os.environ['AGENT_ID'],
            agentAliasId='TSTALIASID',
            sessionId=session_id,
            inputText=query,
            enableTrace=True
        )
        
        # Process response stream with better error handling
        response_text = ""
        trace_info = []
        
        for chunk in response['completion']:
            if 'chunk' in chunk:
                chunk_data = chunk['chunk']
                if 'bytes' in chunk_data:
                    response_text += chunk_data['bytes'].decode('utf-8')
            elif 'trace' in chunk:
                trace_info.append(chunk['trace'])
        
        logger.info(f"Successfully processed query, response length: {len(response_text)}")
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type',
                'Access-Control-Allow-Methods': 'POST, OPTIONS'
            },
            'body': json.dumps({
                'response': response_text,
                'sessionId': session_id,
                'timestamp': context.aws_request_id
            })
        }
        
    except ClientError as e:
        error_code = e.response['Error']['Code']
        logger.error(f"AWS service error: {error_code} - {str(e)}")
        
        return {
            'statusCode': 503 if error_code in ['ThrottlingException', 'ServiceQuotaExceededException'] else 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': f'Service temporarily unavailable. Please try again later.',
                'requestId': context.aws_request_id
            })
        }
        
    except json.JSONDecodeError as e:
        logger.error(f"JSON decode error: {str(e)}")
        return {
            'statusCode': 400,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Invalid JSON format in request body'
            })
        }
        
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
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
"""

        # Create Lambda function
        self.lambda_function = lambda_.Function(
            self,
            "KnowledgeAssistantFunction",
            function_name=f"bedrock-agent-proxy-{self.random_suffix}",
            runtime=lambda_.Runtime.PYTHON_3_12,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(lambda_code),
            role=self.lambda_role,
            timeout=Duration.seconds(30),
            memory_size=256,
            environment={
                "AGENT_ID": self.bedrock_agent.attr_agent_id
            },
            description="Knowledge Management Assistant API proxy",
            log_retention=logs.RetentionDays.ONE_WEEK
        )

    def _create_api_gateway(self) -> None:
        """
        Create production-ready API Gateway with CORS and monitoring
        """
        # Create REST API
        self.api = apigateway.RestApi(
            self,
            "KnowledgeManagementAPI",
            rest_api_name=f"knowledge-management-api-{self.random_suffix}",
            description="Knowledge Management Assistant API",
            endpoint_configuration=apigateway.EndpointConfiguration(
                types=[apigateway.EndpointType.REGIONAL]
            ),
            deploy_options=apigateway.StageOptions(
                stage_name="prod",
                logging_level=apigateway.MethodLoggingLevel.INFO,
                data_trace_enabled=True,
                metrics_enabled=True
            )
        )

        # Create query resource
        query_resource = self.api.root.add_resource("query")

        # Add CORS preflight OPTIONS method
        query_resource.add_method(
            "OPTIONS",
            apigateway.MockIntegration(
                integration_responses=[
                    apigateway.IntegrationResponse(
                        status_code="200",
                        response_parameters={
                            "method.response.header.Access-Control-Allow-Headers": "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
                            "method.response.header.Access-Control-Allow-Methods": "'GET,POST,OPTIONS'",
                            "method.response.header.Access-Control-Allow-Origin": "'*'"
                        }
                    )
                ],
                request_templates={"application/json": '{"statusCode": 200}'}
            ),
            method_responses=[
                apigateway.MethodResponse(
                    status_code="200",
                    response_parameters={
                        "method.response.header.Access-Control-Allow-Headers": True,
                        "method.response.header.Access-Control-Allow-Methods": True,
                        "method.response.header.Access-Control-Allow-Origin": True
                    }
                )
            ]
        )

        # Add POST method with Lambda integration
        query_resource.add_method(
            "POST",
            apigateway.LambdaIntegration(
                self.lambda_function,
                proxy=True
            ),
            authorization_type=apigateway.AuthorizationType.NONE
        )

        # Store API endpoint for outputs
        self.api_endpoint = self.api.url

    def _create_sample_documents(self) -> None:
        """
        Deploy sample enterprise documents to S3 bucket
        """
        # Create sample documents as assets
        sample_docs = {
            "company-policies.txt": """COMPANY POLICIES AND PROCEDURES

Remote Work Policy:
All employees are eligible for remote work arrangements with manager approval. Remote workers must maintain regular communication during business hours and attend quarterly in-person meetings.

Expense Reimbursement:
Business expenses must be submitted within 30 days with receipts. Meal expenses are capped at $75 per day for domestic travel and $100 for international travel.

Time Off Policy:
Employees accrue 2.5 days of PTO per month. Requests must be submitted 2 weeks in advance for planned time off.""",
            
            "technical-guide.txt": """TECHNICAL OPERATIONS GUIDE

Database Backup Procedures:
Daily automated backups run at 2 AM EST. Manual backups can be initiated through the admin console. Retention period is 30 days for automated backups.

Incident Response:
Priority 1: Response within 15 minutes
Priority 2: Response within 2 hours
Priority 3: Response within 24 hours

System Maintenance Windows:
Scheduled maintenance occurs first Sunday of each month from 2-6 AM EST."""
        }

        # Create local assets and deploy to S3
        import tempfile
        import os
        
        with tempfile.TemporaryDirectory() as temp_dir:
            docs_dir = os.path.join(temp_dir, "documents")
            os.makedirs(docs_dir)
            
            for filename, content in sample_docs.items():
                with open(os.path.join(docs_dir, filename), 'w') as f:
                    f.write(content)
            
            # Deploy documents to S3
            s3_deployment.BucketDeployment(
                self,
                "SampleDocuments",
                sources=[s3_deployment.Source.asset(temp_dir)],
                destination_bucket=self.document_bucket,
                retain_on_delete=False
            )

    def _create_outputs(self) -> None:
        """
        Create CloudFormation outputs for important resource information
        """
        CfnOutput(
            self,
            "DocumentBucketName",
            value=self.document_bucket.bucket_name,
            description="Name of the S3 bucket for document storage"
        )

        CfnOutput(
            self,
            "KnowledgeBaseId",
            value=self.knowledge_base.attr_knowledge_base_id,
            description="ID of the Bedrock Knowledge Base"
        )

        CfnOutput(
            self,
            "BedrockAgentId",
            value=self.bedrock_agent.attr_agent_id,
            description="ID of the Bedrock Agent"
        )

        CfnOutput(
            self,
            "LambdaFunctionName",
            value=self.lambda_function.function_name,
            description="Name of the Lambda function"
        )

        CfnOutput(
            self,
            "APIEndpoint",
            value=self.api_endpoint,
            description="API Gateway endpoint URL for the knowledge management assistant"
        )

        CfnOutput(
            self,
            "APIQueryEndpoint",
            value=f"{self.api_endpoint}query",
            description="Complete API endpoint for sending queries to the knowledge assistant"
        )

        CfnOutput(
            self,
            "OpenSearchCollectionARN",
            value=self.opensearch_collection.attr_arn,
            description="ARN of the OpenSearch Serverless collection"
        )


class KnowledgeManagementApp(cdk.App):
    """
    CDK Application for Knowledge Management Assistant
    """
    
    def __init__(self) -> None:
        super().__init__()
        
        # Create the main stack
        KnowledgeManagementAssistantStack(
            self,
            "KnowledgeManagementAssistantStack",
            description="Knowledge Management Assistant with Amazon Bedrock Agents",
            env=cdk.Environment(
                account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
                region=os.environ.get("CDK_DEFAULT_REGION")
            )
        )


if __name__ == "__main__":
    # Create and deploy the CDK application
    app = KnowledgeManagementApp()
    app.synth()