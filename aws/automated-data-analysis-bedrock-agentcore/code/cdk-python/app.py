#!/usr/bin/env python3
"""
CDK Application for Automated Data Analysis with Bedrock AgentCore Runtime

This CDK application deploys a serverless data analysis system using AWS Bedrock
AgentCore Runtime with Code Interpreter to process datasets uploaded to S3 and
generate insights automatically.

Architecture:
- S3 buckets for data input and results storage
- Lambda function for workflow orchestration
- IAM roles with least privilege permissions
- CloudWatch dashboard for monitoring
- Event-driven processing with S3 triggers

Author: AWS CDK Generator
Version: 1.0
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    CfnOutput,
    Duration,
    RemovalPolicy,
    aws_s3 as s3,
    aws_lambda as _lambda,
    aws_iam as iam,
    aws_s3_notifications as s3n,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
)
from constructs import Construct
import json
from typing import Dict, Any


class AutomatedDataAnalysisStack(Stack):
    """
    CDK Stack for Automated Data Analysis with Bedrock AgentCore
    
    This stack creates all the necessary AWS resources for an automated
    data analysis pipeline using Bedrock AgentCore Runtime.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Stack parameters
        self.random_suffix = self.node.try_get_context("randomSuffix") or "demo"
        
        # Create S3 buckets for data storage
        self._create_s3_buckets()
        
        # Create IAM role for Lambda function
        self._create_iam_role()
        
        # Create Lambda function for workflow orchestration
        self._create_lambda_function()
        
        # Configure S3 event triggers
        self._configure_s3_triggers()
        
        # Create CloudWatch dashboard
        self._create_cloudwatch_dashboard()
        
        # Create stack outputs
        self._create_outputs()

    def _create_s3_buckets(self) -> None:
        """Create S3 buckets for data input and results storage."""
        
        # Data input bucket
        self.data_bucket = s3.Bucket(
            self,
            "DataBucket",
            bucket_name=f"data-analysis-input-{self.random_suffix}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="ArchiveOldVersions",
                    noncurrent_version_transitions=[
                        s3.NoncurrentVersionTransition(
                            storage_class=s3.StorageClass.INTELLIGENT_TIERING,
                            transition_after=Duration.days(30)
                        )
                    ],
                    noncurrent_version_expiration=Duration.days(90)
                )
            ]
        )
        
        # Results storage bucket
        self.results_bucket = s3.Bucket(
            self,
            "ResultsBucket",
            bucket_name=f"data-analysis-results-{self.random_suffix}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="ArchiveResults",
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.STANDARD_INFREQUENT_ACCESS,
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

    def _create_iam_role(self) -> None:
        """Create IAM role for Lambda function with necessary permissions."""
        
        # Create IAM role for Lambda
        self.lambda_role = iam.Role(
            self,
            "DataAnalysisLambdaRole",
            role_name=f"DataAnalysisOrchestratorRole-{self.random_suffix}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
            inline_policies={
                "BedrockAgentCoreAccess": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "bedrock-agentcore:CreateCodeInterpreter",
                                "bedrock-agentcore:StartCodeInterpreterSession",
                                "bedrock-agentcore:InvokeCodeInterpreter",
                                "bedrock-agentcore:StopCodeInterpreterSession",
                                "bedrock-agentcore:DeleteCodeInterpreter",
                                "bedrock-agentcore:ListCodeInterpreters",
                                "bedrock-agentcore:GetCodeInterpreter",
                                "bedrock-agentcore:GetCodeInterpreterSession"
                            ],
                            resources=["*"]
                        )
                    ]
                ),
                "S3DataAccess": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:GetObject",
                                "s3:PutObject",
                                "s3:DeleteObject"
                            ],
                            resources=[
                                f"{self.data_bucket.bucket_arn}/*",
                                f"{self.results_bucket.bucket_arn}/*"
                            ]
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=["s3:ListBucket"],
                            resources=[
                                self.data_bucket.bucket_arn,
                                self.results_bucket.bucket_arn
                            ]
                        )
                    ]
                )
            }
        )

    def _create_lambda_function(self) -> None:
        """Create Lambda function for workflow orchestration."""
        
        # Lambda function code
        lambda_code = '''
import json
import boto3
import logging
import os
import time
from urllib.parse import unquote_plus

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
s3 = boto3.client('s3')
bedrock_agentcore = boto3.client('bedrock-agentcore')

def lambda_handler(event, context):
    """
    Orchestrates automated data analysis using Bedrock AgentCore
    """
    try:
        # Parse S3 event
        for record in event['Records']:
            bucket_name = record['s3']['bucket']['name']
            object_key = unquote_plus(record['s3']['object']['key'])
            
            logger.info(f"Processing file: {object_key} from bucket: {bucket_name}")
            
            # Generate analysis based on file type
            file_extension = object_key.split('.')[-1].lower()
            analysis_code = generate_analysis_code(file_extension, bucket_name, object_key)
            
            # Create AgentCore session and execute analysis
            session_response = bedrock_agentcore.start_code_interpreter_session(
                codeInterpreterIdentifier='aws.codeinterpreter.v1',
                name=f'DataAnalysis-{int(time.time())}',
                sessionTimeoutSeconds=900
            )
            session_id = session_response['sessionId']
            
            logger.info(f"Started AgentCore session: {session_id}")
            
            # Execute the analysis code
            execution_response = bedrock_agentcore.invoke_code_interpreter(
                codeInterpreterIdentifier='aws.codeinterpreter.v1',
                sessionId=session_id,
                name='executeCode',
                arguments={
                    'language': 'python',
                    'code': analysis_code
                }
            )
            
            logger.info(f"Analysis execution completed for {object_key}")
            
            # Store results metadata
            results_key = f"analysis-results/{object_key.replace('.', '_')}_analysis.json"
            result_metadata = {
                'source_file': object_key,
                'session_id': session_id,
                'analysis_timestamp': context.aws_request_id,
                'execution_status': 'completed',
                'execution_response': execution_response
            }
            
            s3.put_object(
                Bucket=os.environ['RESULTS_BUCKET_NAME'],
                Key=results_key,
                Body=json.dumps(result_metadata, indent=2),
                ContentType='application/json'
            )
            
            # Clean up session
            bedrock_agentcore.stop_code_interpreter_session(
                codeInterpreterIdentifier='aws.codeinterpreter.v1',
                sessionId=session_id
            )
            
        return {
            'statusCode': 200,
            'body': json.dumps('Analysis completed successfully')
        }
        
    except Exception as e:
        logger.error(f"Error processing analysis: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }

def generate_analysis_code(file_type, bucket_name, object_key):
    """
    Generate appropriate analysis code based on file type
    """
    base_code = f"""
import pandas as pd
import matplotlib.pyplot as plt
import boto3
import io

# Download the file from S3
s3 = boto3.client('s3')
obj = s3.get_object(Bucket='{bucket_name}', Key='{object_key}')
"""
    
    if file_type in ['csv']:
        analysis_code = base_code + """
# Read CSV file
df = pd.read_csv(io.BytesIO(obj['Body'].read()))

# Perform comprehensive analysis
print("Dataset Overview:")
print(f"Shape: {df.shape}")
print(f"Columns: {list(df.columns)}")
print("\\nDataset Info:")
print(df.info())
print("\\nStatistical Summary:")
print(df.describe())
print("\\nMissing Values:")
print(df.isnull().sum())

# Generate basic visualizations if numeric columns exist
numeric_cols = df.select_dtypes(include=['number']).columns
if len(numeric_cols) > 0:
    plt.figure(figsize=(12, 8))
    for i, col in enumerate(numeric_cols[:4], 1):
        plt.subplot(2, 2, i)
        plt.hist(df[col].dropna(), bins=20, alpha=0.7)
        plt.title(f'Distribution of {col}')
        plt.xlabel(col)
        plt.ylabel('Frequency')
    plt.tight_layout()
    plt.savefig('/tmp/data_analysis.png', dpi=150, bbox_inches='tight')
    print("\\nVisualization saved as data_analysis.png")

print("\\nAnalysis completed successfully!")
"""
    elif file_type in ['json']:
        analysis_code = base_code + """
# Read JSON file
import json
data = json.loads(obj['Body'].read().decode('utf-8'))

# Analyze JSON structure
print("JSON Data Analysis:")
print(f"Data type: {type(data)}")
if isinstance(data, dict):
    print(f"Keys: {list(data.keys())}")
elif isinstance(data, list):
    print(f"List length: {len(data)}")
    if len(data) > 0:
        print(f"First item type: {type(data[0])}")
        if isinstance(data[0], dict):
            print(f"Sample keys: {list(data[0].keys())}")

print("\\nJSON analysis completed!")
"""
    else:
        analysis_code = base_code + """
# Generic file analysis
print(f"File size: {obj['ContentLength']} bytes")
print(f"Content type: {obj.get('ContentType', 'Unknown')}")
print("\\nGeneric file analysis completed!")
"""
    
    return analysis_code
'''
        
        # Create Lambda function
        self.lambda_function = _lambda.Function(
            self,
            "DataAnalysisOrchestrator",
            function_name=f"data-analysis-orchestrator-{self.random_suffix}",
            runtime=_lambda.Runtime.PYTHON_3_11,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline(lambda_code),
            role=self.lambda_role,
            timeout=Duration.minutes(5),
            memory_size=512,
            environment={
                "RESULTS_BUCKET_NAME": self.results_bucket.bucket_name
            },
            log_retention=logs.RetentionDays.ONE_WEEK,
            description="Orchestrates automated data analysis using Bedrock AgentCore Runtime"
        )

    def _configure_s3_triggers(self) -> None:
        """Configure S3 event triggers for Lambda function."""
        
        # Add S3 event notification to trigger Lambda
        self.data_bucket.add_event_notification(
            s3.EventType.OBJECT_CREATED,
            s3n.LambdaDestination(self.lambda_function),
            s3.NotificationKeyFilter(prefix="datasets/")
        )

    def _create_cloudwatch_dashboard(self) -> None:
        """Create CloudWatch dashboard for monitoring."""
        
        # Create CloudWatch dashboard
        self.dashboard = cloudwatch.Dashboard(
            self,
            "DataAnalysisDashboard",
            dashboard_name=f"DataAnalysisAutomation-{self.random_suffix}",
            widgets=[
                [
                    cloudwatch.GraphWidget(
                        title="Lambda Function Metrics",
                        left=[
                            self.lambda_function.metric_invocations(
                                period=Duration.minutes(5),
                                statistic="Sum"
                            ),
                            self.lambda_function.metric_duration(
                                period=Duration.minutes(5),
                                statistic="Average"
                            ),
                            self.lambda_function.metric_errors(
                                period=Duration.minutes(5),
                                statistic="Sum"
                            )
                        ],
                        width=12,
                        height=6
                    )
                ],
                [
                    cloudwatch.LogQueryWidget(
                        title="Recent Analysis Activities",
                        log_groups=[self.lambda_function.log_group],
                        query_lines=[
                            "fields @timestamp, @message",
                            "filter @message like /Processing file/",
                            "sort @timestamp desc",
                            "limit 20"
                        ],
                        width=12,
                        height=6
                    )
                ]
            ]
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        
        CfnOutput(
            self,
            "DataBucketName",
            value=self.data_bucket.bucket_name,
            description="Name of the S3 bucket for uploading datasets",
            export_name=f"{self.stack_name}-DataBucketName"
        )
        
        CfnOutput(
            self,
            "ResultsBucketName",
            value=self.results_bucket.bucket_name,
            description="Name of the S3 bucket containing analysis results",
            export_name=f"{self.stack_name}-ResultsBucketName"
        )
        
        CfnOutput(
            self,
            "LambdaFunctionName",
            value=self.lambda_function.function_name,
            description="Name of the Lambda function orchestrating data analysis",
            export_name=f"{self.stack_name}-LambdaFunctionName"
        )
        
        CfnOutput(
            self,
            "DashboardURL",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.dashboard.dashboard_name}",
            description="URL to the CloudWatch dashboard for monitoring",
            export_name=f"{self.stack_name}-DashboardURL"
        )
        
        CfnOutput(
            self,
            "UploadCommand",
            value=f"aws s3 cp your-dataset.csv s3://{self.data_bucket.bucket_name}/datasets/",
            description="Example command to upload datasets for analysis",
            export_name=f"{self.stack_name}-UploadCommand"
        )


# CDK App definition
app = cdk.App()

# Get context values
random_suffix = app.node.try_get_context("randomSuffix")
if not random_suffix:
    import secrets
    import string
    random_suffix = ''.join(secrets.choice(string.ascii_lowercase + string.digits) for _ in range(6))

# Create the stack
AutomatedDataAnalysisStack(
    app,
    "AutomatedDataAnalysisStack",
    env=Environment(
        account=app.node.try_get_context("account"),
        region=app.node.try_get_context("region")
    ),
    description="Automated Data Analysis with Bedrock AgentCore Runtime - CDK Python Stack",
    stack_name=f"automated-data-analysis-{random_suffix}",
    context={
        "randomSuffix": random_suffix
    }
)

# Synthesize the app
app.synth()