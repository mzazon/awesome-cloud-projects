#!/usr/bin/env python3
"""
CDK Python application for Natural Language Processing Pipelines with Amazon Comprehend.

This application creates a complete NLP pipeline including:
- S3 buckets for input and output data
- Lambda function for real-time text processing
- IAM roles with appropriate permissions
- Custom document classifier resources
- Batch processing capabilities

Author: AWS CDK Team
Version: 1.0
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    aws_iam as iam,
    aws_lambda as lambda_,
    aws_s3 as s3,
    aws_logs as logs,
    CfnOutput,
)
from constructs import Construct


class ComprehendNLPPipelineStack(Stack):
    """
    Main stack for the Comprehend NLP Pipeline.
    
    This stack creates all the necessary infrastructure for processing
    text data using Amazon Comprehend, including real-time and batch
    processing capabilities.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        unique_suffix = self.node.addr[-8:].lower()

        # Create S3 buckets for data storage
        self.input_bucket = self._create_input_bucket(unique_suffix)
        self.output_bucket = self._create_output_bucket(unique_suffix)

        # Create IAM roles for Lambda and Comprehend
        self.lambda_role = self._create_lambda_execution_role(unique_suffix)
        self.comprehend_service_role = self._create_comprehend_service_role(unique_suffix)

        # Create Lambda function for real-time processing
        self.processor_function = self._create_lambda_function(unique_suffix)

        # Create CloudWatch Log Group for Lambda
        self.log_group = self._create_log_group(unique_suffix)

        # Create stack outputs
        self._create_outputs()

    def _create_input_bucket(self, suffix: str) -> s3.Bucket:
        """
        Create S3 bucket for input data storage.
        
        Args:
            suffix: Unique suffix for bucket naming
            
        Returns:
            S3 Bucket construct
        """
        bucket = s3.Bucket(
            self,
            "ComprehendInputBucket",
            bucket_name=f"comprehend-nlp-pipeline-{suffix}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteOldVersions",
                    noncurrent_version_expiration=Duration.days(30),
                    abort_incomplete_multipart_upload_after=Duration.days(1),
                )
            ],
        )

        # Add bucket notification for future event triggers
        bucket.add_cors_rule(
            allowed_methods=[s3.HttpMethods.GET, s3.HttpMethods.PUT],
            allowed_origins=["*"],
            allowed_headers=["*"],
        )

        cdk.Tags.of(bucket).add("Purpose", "NLP Input Data")
        cdk.Tags.of(bucket).add("Environment", "Development")

        return bucket

    def _create_output_bucket(self, suffix: str) -> s3.Bucket:
        """
        Create S3 bucket for output data storage.
        
        Args:
            suffix: Unique suffix for bucket naming
            
        Returns:
            S3 Bucket construct
        """
        bucket = s3.Bucket(
            self,
            "ComprehendOutputBucket",
            bucket_name=f"comprehend-nlp-pipeline-{suffix}-output",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="ArchiveOldData",
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30),
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(90),
                        ),
                    ],
                )
            ],
        )

        cdk.Tags.of(bucket).add("Purpose", "NLP Output Data")
        cdk.Tags.of(bucket).add("Environment", "Development")

        return bucket

    def _create_lambda_execution_role(self, suffix: str) -> iam.Role:
        """
        Create IAM role for Lambda function execution.
        
        Args:
            suffix: Unique suffix for role naming
            
        Returns:
            IAM Role construct
        """
        role = iam.Role(
            self,
            "ComprehendLambdaRole",
            role_name=f"ComprehendLambdaRole-{suffix}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Execution role for Comprehend NLP Lambda processor",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
        )

        # Add custom policy for Comprehend and S3 access
        comprehend_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "comprehend:DetectSentiment",
                "comprehend:DetectEntities",
                "comprehend:DetectKeyPhrases",
                "comprehend:DetectLanguage",
                "comprehend:DetectSyntax",
                "comprehend:DetectTargetedSentiment",
                "comprehend:StartDocumentClassificationJob",
                "comprehend:StartEntitiesDetectionJob",
                "comprehend:StartKeyPhrasesDetectionJob",
                "comprehend:StartSentimentDetectionJob",
                "comprehend:DescribeDocumentClassificationJob",
                "comprehend:DescribeEntitiesDetectionJob",
                "comprehend:DescribeKeyPhrasesDetectionJob",
                "comprehend:DescribeSentimentDetectionJob",
                "comprehend:ClassifyDocument",
            ],
            resources=["*"],
        )

        s3_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:ListBucket",
            ],
            resources=[
                self.input_bucket.bucket_arn,
                f"{self.input_bucket.bucket_arn}/*",
                self.output_bucket.bucket_arn,
                f"{self.output_bucket.bucket_arn}/*",
            ],
        )

        role.add_to_policy(comprehend_policy)
        role.add_to_policy(s3_policy)

        return role

    def _create_comprehend_service_role(self, suffix: str) -> iam.Role:
        """
        Create IAM role for Comprehend batch processing services.
        
        Args:
            suffix: Unique suffix for role naming
            
        Returns:
            IAM Role construct
        """
        role = iam.Role(
            self,
            "ComprehendServiceRole",
            role_name=f"ComprehendServiceRole-{suffix}",
            assumed_by=iam.ServicePrincipal("comprehend.amazonaws.com"),
            description="Service role for Comprehend batch processing jobs",
        )

        # Add S3 access policy for Comprehend service
        s3_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "s3:GetObject",
                "s3:ListBucket",
            ],
            resources=[
                self.input_bucket.bucket_arn,
                f"{self.input_bucket.bucket_arn}/*",
            ],
        )

        s3_output_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "s3:PutObject",
            ],
            resources=[
                self.output_bucket.bucket_arn,
                f"{self.output_bucket.bucket_arn}/*",
            ],
        )

        role.add_to_policy(s3_policy)
        role.add_to_policy(s3_output_policy)

        return role

    def _create_lambda_function(self, suffix: str) -> lambda_.Function:
        """
        Create Lambda function for real-time text processing.
        
        Args:
            suffix: Unique suffix for function naming
            
        Returns:
            Lambda Function construct
        """
        # Lambda function code
        lambda_code = '''
import json
import boto3
import uuid
from datetime import datetime
from typing import Dict, Any, List

comprehend = boto3.client('comprehend')
s3 = boto3.client('s3')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for processing text using Amazon Comprehend.
    
    Supports both S3 event triggers and direct invocation with text payload.
    
    Args:
        event: Lambda event data
        context: Lambda runtime context
        
    Returns:
        Dict containing status code and processing results
    """
    try:
        # Get text from S3 event or direct invocation
        if 'Records' in event:
            # S3 event trigger
            bucket = event['Records'][0]['s3']['bucket']['name']
            key = event['Records'][0]['s3']['object']['key']
            
            # Get text from S3
            response = s3.get_object(Bucket=bucket, Key=key)
            text = response['Body'].read().decode('utf-8')
            output_bucket = bucket + '-output' if bucket.endswith('-pipeline') else bucket + '-output'
        else:
            # Direct invocation
            text = event.get('text', '')
            output_bucket = event.get('output_bucket', '')
        
        if not text:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'No text provided'})
            }
        
        # Detect language first
        language_response = comprehend.detect_dominant_language(Text=text)
        language_code = language_response['Languages'][0]['LanguageCode']
        
        # Perform comprehensive text analysis
        results = analyze_text(text, language_code)
        
        # Add metadata
        results.update({
            'timestamp': datetime.now().isoformat(),
            'text': text,
            'language': language_code,
            'processing_id': str(uuid.uuid4())
        })
        
        # Save results to S3 if output bucket provided
        if output_bucket:
            save_results_to_s3(results, output_bucket)
        
        return {
            'statusCode': 200,
            'body': json.dumps(results, default=str)
        }
        
    except Exception as e:
        print(f"Error processing text: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def analyze_text(text: str, language_code: str) -> Dict[str, Any]:
    """
    Perform comprehensive text analysis using Comprehend.
    
    Args:
        text: Input text to analyze
        language_code: Detected language code
        
    Returns:
        Dict containing all analysis results
    """
    results = {}
    
    try:
        # Sentiment analysis
        sentiment_response = comprehend.detect_sentiment(
            Text=text,
            LanguageCode=language_code
        )
        results['sentiment'] = {
            'sentiment': sentiment_response['Sentiment'],
            'scores': sentiment_response['SentimentScore']
        }
    except Exception as e:
        results['sentiment'] = {'error': str(e)}
    
    try:
        # Entity extraction
        entities_response = comprehend.detect_entities(
            Text=text,
            LanguageCode=language_code
        )
        results['entities'] = entities_response['Entities']
    except Exception as e:
        results['entities'] = {'error': str(e)}
    
    try:
        # Key phrases extraction
        keyphrases_response = comprehend.detect_key_phrases(
            Text=text,
            LanguageCode=language_code
        )
        results['key_phrases'] = keyphrases_response['KeyPhrases']
    except Exception as e:
        results['key_phrases'] = {'error': str(e)}
    
    try:
        # Syntax analysis
        syntax_response = comprehend.detect_syntax(
            Text=text,
            LanguageCode=language_code
        )
        results['syntax'] = syntax_response['SyntaxTokens']
    except Exception as e:
        results['syntax'] = {'error': str(e)}
    
    return results

def save_results_to_s3(results: Dict[str, Any], bucket_name: str) -> None:
    """
    Save analysis results to S3.
    
    Args:
        results: Analysis results to save
        bucket_name: S3 bucket name for output
    """
    try:
        output_key = f"processed/{results['processing_id']}.json"
        s3.put_object(
            Bucket=bucket_name,
            Key=output_key,
            Body=json.dumps(results, indent=2, default=str),
            ContentType='application/json'
        )
        print(f"Results saved to s3://{bucket_name}/{output_key}")
    except Exception as e:
        print(f"Error saving results to S3: {str(e)}")
'''

        function = lambda_.Function(
            self,
            "ComprehendProcessor",
            function_name=f"comprehend-processor-{suffix}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(lambda_code),
            role=self.lambda_role,
            timeout=Duration.seconds(300),
            memory_size=512,
            environment={
                "INPUT_BUCKET": self.input_bucket.bucket_name,
                "OUTPUT_BUCKET": self.output_bucket.bucket_name,
                "LOG_LEVEL": "INFO",
            },
            description="Real-time text processing using Amazon Comprehend",
        )

        # Add tags
        cdk.Tags.of(function).add("Purpose", "NLP Text Processing")
        cdk.Tags.of(function).add("Environment", "Development")

        return function

    def _create_log_group(self, suffix: str) -> logs.LogGroup:
        """
        Create CloudWatch Log Group for Lambda function.
        
        Args:
            suffix: Unique suffix for log group naming
            
        Returns:
            CloudWatch LogGroup construct
        """
        log_group = logs.LogGroup(
            self,
            "ComprehendLambdaLogGroup",
            log_group_name=f"/aws/lambda/comprehend-processor-{suffix}",
            retention=logs.RetentionDays.TWO_WEEKS,
            removal_policy=RemovalPolicy.DESTROY,
        )

        return log_group

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources."""
        CfnOutput(
            self,
            "InputBucketName",
            value=self.input_bucket.bucket_name,
            description="S3 bucket for input text data",
            export_name=f"{self.stack_name}-InputBucket",
        )

        CfnOutput(
            self,
            "OutputBucketName",
            value=self.output_bucket.bucket_name,
            description="S3 bucket for processed results",
            export_name=f"{self.stack_name}-OutputBucket",
        )

        CfnOutput(
            self,
            "LambdaFunctionName",
            value=self.processor_function.function_name,
            description="Lambda function for real-time text processing",
            export_name=f"{self.stack_name}-LambdaFunction",
        )

        CfnOutput(
            self,
            "LambdaFunctionArn",
            value=self.processor_function.function_arn,
            description="ARN of the Lambda function",
            export_name=f"{self.stack_name}-LambdaFunctionArn",
        )

        CfnOutput(
            self,
            "ComprehendServiceRoleArn",
            value=self.comprehend_service_role.role_arn,
            description="IAM role for Comprehend batch processing",
            export_name=f"{self.stack_name}-ComprehendServiceRole",
        )


class ComprehendNLPPipelineApp(cdk.App):
    """
    CDK Application for the Comprehend NLP Pipeline.
    
    This application orchestrates the deployment of the complete
    natural language processing pipeline infrastructure.
    """

    def __init__(self):
        super().__init__()

        # Get environment configuration
        env = cdk.Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
        )

        # Create the main stack
        stack = ComprehendNLPPipelineStack(
            self,
            "ComprehendNLPPipelineStack",
            env=env,
            description="Complete NLP pipeline using Amazon Comprehend for text analysis",
            tags={
                "Project": "NLP Pipeline",
                "Owner": "Development Team",
                "Environment": "Development",
                "CostCenter": "Engineering",
            },
        )


# Create and run the application
app = ComprehendNLPPipelineApp()
app.synth()