#!/usr/bin/env python3
"""
CDK Python application for Intelligent Document QA System with AWS Bedrock and Amazon Kendra.

This application deploys a complete document question-answering system that combines
Amazon Kendra's machine learning-powered search capabilities with AWS Bedrock's 
generative AI models to provide contextual answers with proper citations.

Architecture:
- S3 bucket for document storage
- Amazon Kendra index for intelligent search
- Lambda function for QA processing using Bedrock
- API Gateway for REST endpoints
- IAM roles with least privilege access

Author: AWS CDK Generator
Version: 1.0
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    aws_s3 as s3,
    aws_iam as iam,
    aws_kendra as kendra,
    aws_lambda as lambda_,
    aws_apigateway as apigateway,
    aws_logs as logs,
    CfnOutput,
)
from constructs import Construct


class IntelligentDocumentQAStack(Stack):
    """
    CDK Stack for deploying an Intelligent Document QA System.
    
    This stack creates all the necessary infrastructure for a document QA system
    that can understand natural language questions and provide contextual answers
    from a collection of documents using Amazon Kendra and AWS Bedrock.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        unique_suffix = self.node.addr[-8:].lower()

        # Create S3 bucket for document storage
        self.document_bucket = self._create_document_bucket(unique_suffix)
        
        # Create IAM roles
        self.kendra_role = self._create_kendra_service_role(unique_suffix)
        self.lambda_role = self._create_lambda_execution_role(unique_suffix)
        
        # Create Kendra index and data source
        self.kendra_index = self._create_kendra_index(unique_suffix)
        self.data_source = self._create_kendra_data_source(unique_suffix)
        
        # Create Lambda function for QA processing
        self.qa_lambda = self._create_qa_lambda_function(unique_suffix)
        
        # Create API Gateway
        self.api_gateway = self._create_api_gateway(unique_suffix)
        
        # Create CloudWatch log groups
        self._create_log_groups(unique_suffix)
        
        # Output important values
        self._create_outputs()

    def _create_document_bucket(self, suffix: str) -> s3.Bucket:
        """Create S3 bucket for storing documents to be indexed by Kendra."""
        bucket = s3.Bucket(
            self,
            "DocumentBucket",
            bucket_name=f"intelligent-qa-documents-{suffix}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="ArchiveOldVersions",
                    enabled=True,
                    noncurrent_version_transitions=[
                        s3.NoncurrentVersionTransition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30)
                        ),
                        s3.NoncurrentVersionTransition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(90)
                        )
                    ]
                )
            ]
        )
        
        # Add tags for cost tracking
        cdk.Tags.of(bucket).add("Application", "IntelligentDocumentQA")
        cdk.Tags.of(bucket).add("Component", "DocumentStorage")
        
        return bucket

    def _create_kendra_service_role(self, suffix: str) -> iam.Role:
        """Create IAM role for Kendra service with necessary permissions."""
        role = iam.Role(
            self,
            "KendraServiceRole",
            role_name=f"KendraServiceRole-{suffix}",
            assumed_by=iam.ServicePrincipal("kendra.amazonaws.com"),
            description="Service role for Amazon Kendra to access S3 and CloudWatch"
        )
        
        # Add CloudWatch permissions for Kendra logging
        role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name("CloudWatchLogsFullAccess")
        )
        
        # Add S3 permissions for document access
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:ListBucket",
                    "s3:GetBucketLocation"
                ],
                resources=[
                    self.document_bucket.bucket_arn,
                    f"{self.document_bucket.bucket_arn}/*"
                ]
            )
        )
        
        return role

    def _create_lambda_execution_role(self, suffix: str) -> iam.Role:
        """Create IAM role for Lambda function with Kendra and Bedrock permissions."""
        role = iam.Role(
            self,
            "LambdaExecutionRole",
            role_name=f"IntelligentQALambdaRole-{suffix}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Execution role for QA Lambda function with Kendra and Bedrock access"
        )
        
        # Add basic Lambda execution permissions
        role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name(
                "service-role/AWSLambdaBasicExecutionRole"
            )
        )
        
        # Add Kendra query permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "kendra:Query",
                    "kendra:DescribeIndex",
                    "kendra:ListDataSources"
                ],
                resources=[f"arn:aws:kendra:{self.region}:{self.account}:index/*"]
            )
        )
        
        # Add Bedrock model invocation permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["bedrock:InvokeModel"],
                resources=[
                    f"arn:aws:bedrock:{self.region}::foundation-model/anthropic.claude-3-sonnet-20240229-v1:0",
                    f"arn:aws:bedrock:{self.region}::foundation-model/anthropic.claude-3-haiku-20240307-v1:0"
                ]
            )
        )
        
        return role

    def _create_kendra_index(self, suffix: str) -> kendra.CfnIndex:
        """Create Amazon Kendra index for intelligent document search."""
        index = kendra.CfnIndex(
            self,
            "KendraIndex",
            name=f"intelligent-qa-index-{suffix}",
            role_arn=self.kendra_role.role_arn,
            edition="DEVELOPER_EDITION",  # Use ENTERPRISE_EDITION for production
            description="Kendra index for intelligent document QA system",
            server_side_encryption_configuration=kendra.CfnIndex.ServerSideEncryptionConfigurationProperty(
                kms_key_id="alias/aws/kendra"
            ),
            tags=[
                cdk.CfnTag(key="Application", value="IntelligentDocumentQA"),
                cdk.CfnTag(key="Component", value="SearchIndex")
            ]
        )
        
        return index

    def _create_kendra_data_source(self, suffix: str) -> kendra.CfnDataSource:
        """Create Kendra data source for S3 document repository."""
        data_source = kendra.CfnDataSource(
            self,
            "KendraDataSource",
            index_id=self.kendra_index.attr_id,
            name=f"s3-document-source-{suffix}",
            type="S3",
            role_arn=self.kendra_role.role_arn,
            description="S3 data source for document indexing",
            data_source_configuration=kendra.CfnDataSource.DataSourceConfigurationProperty(
                s3_configuration=kendra.CfnDataSource.S3DataSourceConfigurationProperty(
                    bucket_name=self.document_bucket.bucket_name,
                    inclusion_prefixes=["documents/"],
                    documents_metadata_configuration=kendra.CfnDataSource.DocumentsMetadataConfigurationProperty(
                        s3_prefix="metadata/"
                    ),
                    access_control_list_configuration=kendra.CfnDataSource.AccessControlListConfigurationProperty(
                        key_path="access-control/"
                    )
                )
            ),
            schedule="cron(0 9 * * ? *)",  # Daily sync at 9 AM UTC
            tags=[
                cdk.CfnTag(key="Application", value="IntelligentDocumentQA"),
                cdk.CfnTag(key="Component", value="DataSource")
            ]
        )
        
        # Ensure data source is created after the index
        data_source.add_dependency(self.kendra_index)
        
        return data_source

    def _create_qa_lambda_function(self, suffix: str) -> lambda_.Function:
        """Create Lambda function for processing QA requests."""
        # Lambda function code
        lambda_code = '''
import json
import boto3
import os
import logging
from typing import Dict, List, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
kendra_client = boto3.client('kendra')
bedrock_client = boto3.client('bedrock-runtime')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Process document QA requests using Kendra and Bedrock.
    
    Args:
        event: API Gateway event containing the question
        context: Lambda context object
        
    Returns:
        API Gateway response with answer and sources
    """
    try:
        # Extract question from request
        if 'body' in event:
            body = json.loads(event['body']) if isinstance(event['body'], str) else event['body']
            question = body.get('question', '')
        else:
            question = event.get('question', '')
            
        if not question:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({'error': 'Question is required'})
            }
        
        logger.info(f"Processing question: {question}")
        
        # Query Kendra for relevant documents
        kendra_response = query_kendra(question)
        
        # Extract relevant passages and sources
        passages, sources = extract_passages_and_sources(kendra_response)
        
        if not passages:
            return {
                'statusCode': 200,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'question': question,
                    'answer': 'I could not find relevant information in the documents to answer your question.',
                    'sources': [],
                    'confidence': 'low'
                })
            }
        
        # Generate answer using Bedrock
        answer = generate_answer_with_bedrock(question, passages)
        
        # Return response
        response_body = {
            'question': question,
            'answer': answer,
            'sources': sources,
            'confidence': 'high' if len(passages) >= 3 else 'medium'
        }
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps(response_body)
        }
        
    except Exception as e:
        logger.error(f"Error processing request: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': 'Internal server error'})
        }

def query_kendra(question: str) -> Dict[str, Any]:
    """Query Kendra index for relevant documents."""
    index_id = os.environ['KENDRA_INDEX_ID']
    
    try:
        response = kendra_client.query(
            IndexId=index_id,
            QueryText=question,
            PageSize=10,
            QueryResultTypeFilter='DOCUMENT',
            SortingConfiguration={
                'DocumentAttributeKey': '_last_updated_at',
                'SortOrder': 'DESC'
            }
        )
        return response
    except Exception as e:
        logger.error(f"Error querying Kendra: {str(e)}")
        raise

def extract_passages_and_sources(kendra_response: Dict[str, Any]) -> tuple:
    """Extract text passages and source information from Kendra response."""
    passages = []
    sources = []
    
    for item in kendra_response.get('ResultItems', []):
        if item.get('Type') == 'DOCUMENT':
            # Extract text content
            excerpt = item.get('DocumentExcerpt', {})
            text = excerpt.get('Text', '').strip()
            
            if text and len(text) > 50:  # Only include substantial content
                passages.append({
                    'text': text,
                    'title': item.get('DocumentTitle', {}).get('Text', 'Untitled'),
                    'uri': item.get('DocumentURI', ''),
                    'score': item.get('ScoreAttributes', {}).get('ScoreConfidence', 'MEDIUM')
                })
                
                # Track unique sources
                source_title = item.get('DocumentTitle', {}).get('Text', 'Untitled')
                source_uri = item.get('DocumentURI', '')
                
                if not any(s['uri'] == source_uri for s in sources):
                    sources.append({
                        'title': source_title,
                        'uri': source_uri
                    })
    
    return passages[:5], sources[:5]  # Limit to top 5 results

def generate_answer_with_bedrock(question: str, passages: List[Dict[str, Any]]) -> str:
    """Generate answer using Bedrock Claude model."""
    # Prepare context from passages
    context_parts = []
    for i, passage in enumerate(passages, 1):
        context_parts.append(f"Document {i}: {passage['title']}\\n{passage['text']}")
    
    context_text = "\\n\\n".join(context_parts)
    
    # Create prompt for Claude
    prompt = f"""Based on the following document excerpts, please answer this question: {question}

Document excerpts:
{context_text}

Please provide a comprehensive and accurate answer based only on the information in the documents above. If the documents don't contain enough information to fully answer the question, please indicate what information is missing. 

Include relevant citations by referencing the document titles when appropriate. Be concise but thorough.

Answer:"""
    
    try:
        # Call Bedrock Claude model
        response = bedrock_client.invoke_model(
            modelId='anthropic.claude-3-sonnet-20240229-v1:0',
            body=json.dumps({
                'anthropic_version': 'bedrock-2023-05-31',
                'max_tokens': 1000,
                'temperature': 0.1,
                'messages': [{'role': 'user', 'content': prompt}]
            })
        )
        
        response_body = json.loads(response['body'].read())
        answer = response_body['content'][0]['text']
        
        return answer.strip()
        
    except Exception as e:
        logger.error(f"Error calling Bedrock: {str(e)}")
        return "I encountered an error while generating the answer. Please try again."
'''
        
        # Create Lambda function
        qa_function = lambda_.Function(
            self,
            "QAProcessorFunction",
            function_name=f"intelligent-qa-processor-{suffix}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(lambda_code),
            role=self.lambda_role,
            timeout=Duration.minutes(5),
            memory_size=512,
            environment={
                "KENDRA_INDEX_ID": self.kendra_index.attr_id,
                "LOG_LEVEL": "INFO"
            },
            description="Lambda function for processing document QA requests using Kendra and Bedrock",
            retry_attempts=2
        )
        
        # Add tags
        cdk.Tags.of(qa_function).add("Application", "IntelligentDocumentQA")
        cdk.Tags.of(qa_function).add("Component", "QAProcessor")
        
        return qa_function

    def _create_api_gateway(self, suffix: str) -> apigateway.RestApi:
        """Create API Gateway for QA system REST endpoints."""
        # Create CloudWatch log group for API Gateway
        log_group = logs.LogGroup(
            self,
            "ApiGatewayLogGroup",
            log_group_name=f"/aws/apigateway/intelligent-qa-{suffix}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY
        )
        
        # Create API Gateway
        api = apigateway.RestApi(
            self,
            "QASystemAPI",
            rest_api_name=f"intelligent-qa-api-{suffix}",
            description="REST API for Intelligent Document QA System",
            endpoint_configuration=apigateway.EndpointConfiguration(
                types=[apigateway.EndpointType.REGIONAL]
            ),
            cloud_watch_role=True,
            deploy_options=apigateway.StageOptions(
                stage_name="prod",
                logging_level=apigateway.MethodLoggingLevel.INFO,
                data_trace_enabled=True,
                metrics_enabled=True,
                access_log_destination=apigateway.LogGroupLogDestination(log_group),
                access_log_format=apigateway.AccessLogFormat.json_with_standard_fields()
            ),
            default_cors_preflight_options=apigateway.CorsOptions(
                allow_origins=apigateway.Cors.ALL_ORIGINS,
                allow_methods=apigateway.Cors.ALL_METHODS,
                allow_headers=["Content-Type", "X-Amz-Date", "Authorization", "X-Api-Key"]
            )
        )
        
        # Create Lambda integration
        lambda_integration = apigateway.LambdaIntegration(
            self.qa_lambda,
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
        
        # Create /ask resource and POST method
        ask_resource = api.root.add_resource("ask")
        ask_resource.add_method(
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
        health_resource = api.root.add_resource("health")
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
        
        return api

    def _create_log_groups(self, suffix: str) -> None:
        """Create CloudWatch log groups for monitoring and debugging."""
        # Log group for Lambda function
        logs.LogGroup(
            self,
            "LambdaLogGroup",
            log_group_name=f"/aws/lambda/intelligent-qa-processor-{suffix}",
            retention=logs.RetentionDays.TWO_WEEKS,
            removal_policy=RemovalPolicy.DESTROY
        )
        
        # Log group for Kendra
        logs.LogGroup(
            self,
            "KendraLogGroup",
            log_group_name=f"/aws/kendra/intelligent-qa-index-{suffix}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information."""
        CfnOutput(
            self,
            "DocumentBucketName",
            value=self.document_bucket.bucket_name,
            description="S3 bucket name for storing documents",
            export_name=f"{self.stack_name}-DocumentBucketName"
        )
        
        CfnOutput(
            self,
            "KendraIndexId",
            value=self.kendra_index.attr_id,
            description="Kendra index ID for document search",
            export_name=f"{self.stack_name}-KendraIndexId"
        )
        
        CfnOutput(
            self,
            "ApiGatewayUrl",
            value=self.api_gateway.url,
            description="API Gateway endpoint URL for QA system",
            export_name=f"{self.stack_name}-ApiGatewayUrl"
        )
        
        CfnOutput(
            self,
            "QAEndpoint",
            value=f"{self.api_gateway.url}ask",
            description="Direct URL for QA endpoint",
            export_name=f"{self.stack_name}-QAEndpoint"
        )
        
        CfnOutput(
            self,
            "LambdaFunctionName",
            value=self.qa_lambda.function_name,
            description="Lambda function name for QA processing",
            export_name=f"{self.stack_name}-LambdaFunctionName"
        )


class IntelligentDocumentQAApp(cdk.App):
    """CDK Application for Intelligent Document QA System."""
    
    def __init__(self):
        super().__init__()
        
        # Get configuration from environment or use defaults
        env = cdk.Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
        )
        
        # Create the main stack
        IntelligentDocumentQAStack(
            self,
            "IntelligentDocumentQAStack",
            env=env,
            description="CDK stack for Intelligent Document QA System with Bedrock and Kendra",
            tags={
                "Application": "IntelligentDocumentQA",
                "Environment": "Development",
                "ManagedBy": "CDK"
            }
        )


# Entry point for CDK CLI
if __name__ == "__main__":
    app = IntelligentDocumentQAApp()
    app.synth()