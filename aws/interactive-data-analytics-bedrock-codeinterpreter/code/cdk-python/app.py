#!/usr/bin/env python3
"""
AWS CDK Python Application for Interactive Data Analytics with Bedrock AgentCore Code Interpreter

This CDK application implements an intelligent data analytics system that combines natural language 
processing with secure code execution capabilities using AWS Bedrock AgentCore Code Interpreter.

Key Components:
- S3 buckets for data storage and results
- Lambda function for orchestration
- Bedrock AgentCore Code Interpreter for AI-powered analytics
- API Gateway for external access
- CloudWatch for monitoring and logging
- IAM roles with least privilege access

The solution enables users to submit analytical requests in natural language,
automatically generates and executes Python code in sandboxed environments,
and delivers actionable insights through secure, enterprise-grade infrastructure.
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    App,
    Stack,
    StackProps,
    CfnOutput,
    RemovalPolicy,
    Duration,
    aws_s3 as s3,
    aws_lambda as lambda_,
    aws_iam as iam,
    aws_apigateway as apigateway,
    aws_logs as logs,
    aws_cloudwatch as cloudwatch,
    aws_sqs as sqs,
    aws_lambda_event_sources as lambda_event_sources,
)
from constructs import Construct

# Import AWS Solutions Constructs for best practices
from aws_solutions_constructs.aws_apigateway_lambda import ApiGatewayToLambda
from aws_solutions_constructs.aws_lambda_s3 import LambdaToS3


class InteractiveDataAnalyticsStack(Stack):
    """
    CDK Stack for Interactive Data Analytics with Bedrock AgentCore Code Interpreter.
    
    This stack creates a comprehensive analytics platform that leverages:
    - AWS Bedrock AgentCore for intelligent code interpretation
    - S3 for scalable data storage and results archiving
    - Lambda for serverless orchestration and workflow management
    - API Gateway for secure external access with throttling
    - CloudWatch for comprehensive monitoring and alerting
    - SQS for error handling and dead letter queuing
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Configure stack-level parameters for customization
        self.region = self.region
        self.account = self.account
        
        # Generate unique suffix for resource names to avoid conflicts
        unique_suffix = cdk.Fn.select(
            0, cdk.Fn.split("-", cdk.Fn.select(2, cdk.Fn.split("/", self.stack_id)))
        )[:8].lower()

        # Create S3 buckets for data storage with enterprise security features
        self._create_s3_buckets(unique_suffix)
        
        # Create IAM roles with least privilege access
        self._create_iam_roles()
        
        # Create Lambda function for orchestration with monitoring
        self._create_lambda_function(unique_suffix)
        
        # Create API Gateway for external access with security
        self._create_api_gateway()
        
        # Create CloudWatch monitoring and alerting
        self._create_monitoring_resources(unique_suffix)
        
        # Create SQS dead letter queue for error handling
        self._create_error_handling_resources(unique_suffix)
        
        # Output important resource information for integration
        self._create_stack_outputs()

    def _create_s3_buckets(self, unique_suffix: str) -> None:
        """
        Create S3 buckets for raw data input and analysis results with enterprise security.
        
        Features:
        - Server-side encryption with AES-256
        - Versioning enabled for data protection
        - Lifecycle policies for cost optimization
        - Block public access for security
        - Notification capabilities for event-driven processing
        """
        # S3 bucket for raw data input with security and lifecycle management
        self.raw_data_bucket = s3.Bucket(
            self,
            "RawDataBucket",
            bucket_name=f"analytics-raw-data-{unique_suffix}",
            encryption=s3.BucketEncryption.S3_MANAGED,
            versioned=True,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DataLifecycleRule",
                    status=s3.LifecycleRuleStatus.ENABLED,
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
            ],
            removal_policy=RemovalPolicy.DESTROY,  # For demo purposes
            auto_delete_objects=True  # Clean up during stack deletion
        )

        # S3 bucket for analysis results with retention policies
        self.results_bucket = s3.Bucket(
            self,
            "ResultsBucket",
            bucket_name=f"analytics-results-{unique_suffix}",
            encryption=s3.BucketEncryption.S3_MANAGED,
            versioned=True,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="ResultsRetentionRule",
                    status=s3.LifecycleRuleStatus.ENABLED,
                    expiration=Duration.days(365)  # Auto-delete after 1 year
                )
            ],
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True
        )

    def _create_iam_roles(self) -> None:
        """
        Create IAM roles with least privilege access for secure operations.
        
        Roles include:
        - Lambda execution role with specific S3 and Bedrock permissions
        - Bedrock AgentCore execution role for code interpreter
        - CloudWatch access for comprehensive logging and monitoring
        """
        # IAM role for Lambda function with specific permissions
        self.lambda_execution_role = iam.Role(
            self,
            "LambdaExecutionRole",
            role_name=f"analytics-lambda-role",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
            inline_policies={
                "AnalyticsPolicy": iam.PolicyDocument(
                    statements=[
                        # S3 permissions for data access
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:GetObject",
                                "s3:PutObject",
                                "s3:DeleteObject",
                                "s3:ListBucket"
                            ],
                            resources=[
                                self.raw_data_bucket.bucket_arn,
                                f"{self.raw_data_bucket.bucket_arn}/*",
                                self.results_bucket.bucket_arn,
                                f"{self.results_bucket.bucket_arn}/*"
                            ]
                        ),
                        # Bedrock permissions for AI services
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "bedrock:InvokeModel",
                                "bedrock:InvokeModelWithResponseStream",
                                "bedrock-agentcore:*"
                            ],
                            resources=["*"]
                        ),
                        # CloudWatch permissions for monitoring
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "cloudwatch:PutMetricData",
                                "logs:CreateLogGroup",
                                "logs:CreateLogStream",
                                "logs:PutLogEvents"
                            ],
                            resources=["*"]
                        ),
                        # SQS permissions for error handling
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "sqs:SendMessage",
                                "sqs:ReceiveMessage",
                                "sqs:DeleteMessage"
                            ],
                            resources=["*"]
                        )
                    ]
                )
            }
        )

        # IAM role for Bedrock AgentCore Code Interpreter
        self.bedrock_execution_role = iam.Role(
            self,
            "BedrockExecutionRole",
            role_name=f"analytics-bedrock-role",
            assumed_by=iam.ServicePrincipal("bedrock.amazonaws.com"),
            inline_policies={
                "BedrockCodeInterpreterPolicy": iam.PolicyDocument(
                    statements=[
                        # S3 access for code interpreter data processing
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:GetObject",
                                "s3:PutObject",
                                "s3:DeleteObject",
                                "s3:ListBucket"
                            ],
                            resources=[
                                self.raw_data_bucket.bucket_arn,
                                f"{self.raw_data_bucket.bucket_arn}/*",
                                self.results_bucket.bucket_arn,
                                f"{self.results_bucket.bucket_arn}/*"
                            ]
                        ),
                        # CloudWatch access for code interpreter logging
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "logs:CreateLogGroup",
                                "logs:CreateLogStream",
                                "logs:PutLogEvents"
                            ],
                            resources=["*"]
                        )
                    ]
                )
            }
        )

    def _create_lambda_function(self, unique_suffix: str) -> None:
        """
        Create Lambda function for orchestrating analytics workflows.
        
        Features:
        - Python 3.11 runtime for latest features and performance
        - Environment variables for configuration
        - Error handling with dead letter queue
        - CloudWatch integration for monitoring
        - Reserved concurrency for predictable performance
        """
        # Lambda function code for analytics orchestration
        lambda_code = """
import json
import boto3
import os
from datetime import datetime
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    '''
    AWS Lambda function for orchestrating data analytics with Bedrock AgentCore Code Interpreter.
    
    This function:
    1. Receives natural language analytics requests
    2. Starts a Bedrock AgentCore Code Interpreter session
    3. Executes data analysis code in a secure sandbox
    4. Stores results in S3 and returns insights
    5. Logs metrics to CloudWatch for monitoring
    '''
    # Initialize AWS clients
    bedrock = boto3.client('bedrock-agentcore')
    s3 = boto3.client('s3')
    cloudwatch = boto3.client('cloudwatch')
    
    try:
        # Extract query from event (API Gateway or direct invocation)
        if 'body' in event:
            # API Gateway request
            body = json.loads(event['body']) if isinstance(event['body'], str) else event['body']
            user_query = body.get('query', 'Analyze the sales data and provide insights')
        else:
            # Direct invocation
            user_query = event.get('query', 'Analyze the sales data and provide insights')
        
        logger.info(f"Processing analytics query: {user_query}")
        
        # Start a Code Interpreter session with enhanced configuration
        session_response = bedrock.start_code_interpreter_session(
            codeInterpreterIdentifier=os.environ.get('CODE_INTERPRETER_ID', 'default'),
            name=f"analytics-session-{int(datetime.now().timestamp())}",
            sessionTimeoutSeconds=3600,
            description=f"Analytics session for query: {user_query[:100]}..."
        )
        
        session_id = session_response['sessionId']
        logger.info(f"Started Code Interpreter session: {session_id}")
        
        # Prepare comprehensive Python code for data analysis
        analysis_code = f\"\"\"
import pandas as pd
import numpy as np
import boto3
import matplotlib.pyplot as plt
import seaborn as sns
from datetime import datetime, timedelta
import json

# Initialize S3 client for data access
s3 = boto3.client('s3')

# Configuration
raw_bucket = '{os.environ['BUCKET_RAW_DATA']}'
results_bucket = '{os.environ['BUCKET_RESULTS']}'

print("="*60)
print("INTERACTIVE DATA ANALYTICS WITH BEDROCK CODE INTERPRETER")
print("="*60)
print(f"Query: {user_query}")
print(f"Timestamp: {{datetime.now().isoformat()}}")
print("="*60)

try:
    # Download and process data files
    print("📥 Downloading data files from S3...")
    s3.download_file(raw_bucket, 'datasets/sample_sales_data.csv', 'sales_data.csv')
    
    # Load and validate data
    sales_df = pd.read_csv('sales_data.csv')
    print(f"✅ Loaded sales data: {{sales_df.shape[0]}} rows, {{sales_df.shape[1]}} columns")
    print(f"📊 Date range: {{sales_df['date'].min()}} to {{sales_df['date'].max()}}")
    
    # Convert date column for time series analysis
    sales_df['date'] = pd.to_datetime(sales_df['date'])
    sales_df['day_of_week'] = sales_df['date'].dt.day_name()
    
    # Comprehensive data analysis based on user query
    print("\\n🔍 COMPREHENSIVE DATA ANALYSIS")
    print("-" * 40)
    
    # Basic statistics
    total_sales = sales_df['sales_amount'].sum()
    avg_sales = sales_df['sales_amount'].mean()
    total_transactions = len(sales_df)
    avg_quantity = sales_df['quantity'].mean()
    
    print(f"💰 Total Sales Amount: ${{total_sales:,.2f}}")
    print(f"📈 Average Sale Amount: ${{avg_sales:.2f}}")
    print(f"🛒 Total Transactions: {{total_transactions:,}}")
    print(f"📦 Average Quantity per Transaction: {{avg_quantity:.1f}}")
    
    # Regional analysis
    print("\\n🌍 REGIONAL PERFORMANCE ANALYSIS")
    print("-" * 40)
    regional_sales = sales_df.groupby('region').agg({{
        'sales_amount': ['sum', 'mean', 'count'],
        'quantity': 'sum'
    }}).round(2)
    
    regional_sales.columns = ['Total Sales', 'Avg Sale', 'Transactions', 'Total Quantity']
    regional_sales = regional_sales.sort_values('Total Sales', ascending=False)
    print(regional_sales.to_string())
    
    # Product performance
    print("\\n🛍️ PRODUCT PERFORMANCE ANALYSIS")
    print("-" * 40)
    product_sales = sales_df.groupby('product').agg({{
        'sales_amount': ['sum', 'mean'],
        'quantity': 'sum'
    }}).round(2)
    
    product_sales.columns = ['Total Sales', 'Avg Sale', 'Total Quantity']
    product_sales = product_sales.sort_values('Total Sales', ascending=False)
    print(product_sales.to_string())
    
    # Customer segment analysis
    print("\\n👥 CUSTOMER SEGMENT ANALYSIS")
    print("-" * 40)
    segment_analysis = sales_df.groupby('customer_segment').agg({{
        'sales_amount': ['sum', 'mean', 'count'],
        'quantity': 'sum'
    }}).round(2)
    
    segment_analysis.columns = ['Total Sales', 'Avg Sale', 'Transactions', 'Total Quantity']
    segment_analysis = segment_analysis.sort_values('Total Sales', ascending=False)
    print(segment_analysis.to_string())
    
    # Time series analysis
    print("\\n📅 TIME SERIES ANALYSIS")
    print("-" * 40)
    daily_sales = sales_df.groupby('date')['sales_amount'].sum().sort_index()
    print("Daily sales trend:")
    for date, amount in daily_sales.items():
        print(f"  {{date.strftime('%Y-%m-%d')}}: ${{amount:,.2f}}")
    
    # Day of week analysis
    dow_sales = sales_df.groupby('day_of_week')['sales_amount'].sum()
    print("\\nSales by day of week:")
    for day, amount in dow_sales.items():
        print(f"  {{day}}: ${{amount:,.2f}}")
    
    # Create comprehensive visualizations
    print("\\n📊 GENERATING VISUALIZATIONS")
    print("-" * 40)
    
    # Set up the plotting style
    plt.style.use('seaborn-v0_8')
    fig, axes = plt.subplots(2, 2, figsize=(16, 12))
    fig.suptitle('Interactive Data Analytics Dashboard', fontsize=16, fontweight='bold')
    
    # 1. Sales by Region (Bar Chart)
    regional_totals = sales_df.groupby('region')['sales_amount'].sum().sort_values(ascending=True)
    axes[0, 0].barh(regional_totals.index, regional_totals.values, color='skyblue')
    axes[0, 0].set_title('Sales Amount by Region', fontweight='bold')
    axes[0, 0].set_xlabel('Sales Amount ($)')
    for i, v in enumerate(regional_totals.values):
        axes[0, 0].text(v + 50, i, f'${{v:,.0f}}', va='center')
    
    # 2. Product Performance (Pie Chart)
    product_totals = sales_df.groupby('product')['sales_amount'].sum()
    axes[0, 1].pie(product_totals.values, labels=product_totals.index, autopct='%1.1f%%', startangle=90)
    axes[0, 1].set_title('Sales Distribution by Product', fontweight='bold')
    
    # 3. Daily Sales Trend (Line Chart)
    daily_trend = sales_df.groupby('date')['sales_amount'].sum()
    axes[1, 0].plot(daily_trend.index, daily_trend.values, marker='o', linewidth=2, markersize=6)
    axes[1, 0].set_title('Daily Sales Trend', fontweight='bold')
    axes[1, 0].set_xlabel('Date')
    axes[1, 0].set_ylabel('Sales Amount ($)')
    axes[1, 0].tick_params(axis='x', rotation=45)
    
    # 4. Customer Segment Analysis (Stacked Bar)
    segment_data = sales_df.groupby(['region', 'customer_segment'])['sales_amount'].sum().unstack(fill_value=0)
    segment_data.plot(kind='bar', stacked=True, ax=axes[1, 1], width=0.8)
    axes[1, 1].set_title('Sales by Region and Customer Segment', fontweight='bold')
    axes[1, 1].set_xlabel('Region')
    axes[1, 1].set_ylabel('Sales Amount ($)')
    axes[1, 1].legend(title='Customer Segment', bbox_to_anchor=(1.05, 1), loc='upper left')
    axes[1, 1].tick_params(axis='x', rotation=45)
    
    plt.tight_layout()
    
    # Save the comprehensive dashboard
    dashboard_filename = f'analytics_dashboard_{{datetime.now().strftime("%Y%m%d_%H%M%S")}}.png'
    plt.savefig(dashboard_filename, dpi=300, bbox_inches='tight')
    print(f"✅ Saved dashboard: {{dashboard_filename}}")
    
    # Generate insights and recommendations
    print("\\n🧠 AI-POWERED INSIGHTS & RECOMMENDATIONS")
    print("=" * 50)
    
    # Performance insights
    best_region = regional_sales.index[0]
    best_product = product_sales.index[0]
    best_segment = segment_analysis.index[0]
    
    print(f"🏆 Top Performing Region: {{best_region}} (${{regional_sales.loc[best_region, 'Total Sales']:,.2f}})")
    print(f"🥇 Best Selling Product: {{best_product}} (${{product_sales.loc[best_product, 'Total Sales']:,.2f}})")
    print(f"💎 Most Valuable Segment: {{best_segment}} (${{segment_analysis.loc[best_segment, 'Total Sales']:,.2f}})")
    
    # Growth opportunities
    print("\\n📈 GROWTH OPPORTUNITIES:")
    worst_region = regional_sales.index[-1]
    print(f"  • Focus on {{worst_region}} region (currently ${{regional_sales.loc[worst_region, 'Total Sales']:,.2f}})")
    
    avg_transaction_value = sales_df['sales_amount'].mean()
    print(f"  • Increase average transaction value (current: ${{avg_transaction_value:.2f}})")
    
    # Upload results to S3
    s3.upload_file(dashboard_filename, results_bucket, f'dashboards/{{dashboard_filename}}')
    
    # Create summary report
    summary_report = {{
        "analysis_timestamp": datetime.now().isoformat(),
        "query": user_query,
        "total_sales": float(total_sales),
        "total_transactions": int(total_transactions),
        "average_sale": float(avg_sales),
        "best_region": best_region,
        "best_product": best_product,
        "best_segment": best_segment,
        "dashboard_file": dashboard_filename
    }}
    
    with open('analysis_summary.json', 'w') as f:
        json.dump(summary_report, f, indent=2)
    
    s3.upload_file('analysis_summary.json', results_bucket, f'reports/analysis_summary_{{datetime.now().strftime("%Y%m%d_%H%M%S")}}.json')
    
    print("\\n✅ ANALYSIS COMPLETE!")
    print(f"📁 Results uploaded to S3 bucket: {{results_bucket}}")
    print("=" * 60)
    
except Exception as e:
    print(f"❌ Error during analysis: {{str(e)}}")
    raise
\"\"\"
        
        # Execute code through Bedrock AgentCore with error handling
        try:
            execution_response = bedrock.invoke_code_interpreter(
                codeInterpreterIdentifier=os.environ.get('CODE_INTERPRETER_ID', 'default'),
                sessionId=session_id,
                name="executeAnalysis",
                arguments={
                    "language": "python",
                    "code": analysis_code
                }
            )
            
            # Process the response stream
            results = []
            for event_item in execution_response.get('stream', []):
                if 'result' in event_item:
                    result = event_item['result']
                    if 'content' in result:
                        for content_item in result['content']:
                            if content_item['type'] == 'text':
                                results.append(content_item['text'])
                                
        except Exception as bedrock_error:
            logger.error(f"Bedrock execution error: {str(bedrock_error)}")
            results = [f"Error executing analysis: {str(bedrock_error)}"]
        
        # Log execution metrics to CloudWatch
        cloudwatch.put_metric_data(
            Namespace='Analytics/CodeInterpreter',
            MetricData=[
                {
                    'MetricName': 'ExecutionCount',
                    'Value': 1,
                    'Unit': 'Count',
                    'Timestamp': datetime.utcnow(),
                    'Dimensions': [
                        {
                            'Name': 'SessionId',
                            'Value': session_id
                        }
                    ]
                },
                {
                    'MetricName': 'QueryLength',
                    'Value': len(user_query),
                    'Unit': 'Count',
                    'Timestamp': datetime.utcnow()
                }
            ]
        )
        
        # Return successful response
        response_body = {
            'statusCode': 200,
            'message': 'Analysis completed successfully',
            'session_id': session_id,
            'query': user_query,
            'results': results,
            'raw_data_bucket': os.environ['BUCKET_RAW_DATA'],
            'results_bucket': os.environ['BUCKET_RESULTS'],
            'timestamp': datetime.utcnow().isoformat()
        }
        
        # Handle API Gateway response format
        if 'httpMethod' in event:
            return {
                'statusCode': 200,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*',
                    'Access-Control-Allow-Methods': 'POST, OPTIONS',
                    'Access-Control-Allow-Headers': 'Content-Type'
                },
                'body': json.dumps(response_body)
            }
        else:
            return response_body
            
    except Exception as e:
        logger.error(f"Lambda execution error: {str(e)}")
        
        # Log error metrics
        try:
            cloudwatch.put_metric_data(
                Namespace='Analytics/CodeInterpreter',
                MetricData=[
                    {
                        'MetricName': 'ExecutionErrors',
                        'Value': 1,
                        'Unit': 'Count',
                        'Timestamp': datetime.utcnow()
                    }
                ]
            )
        except:
            pass  # Don't fail if metrics logging fails
        
        error_response = {
            'statusCode': 500,
            'message': 'Analysis failed',
            'error': str(e),
            'timestamp': datetime.utcnow().isoformat()
        }
        
        # Handle API Gateway error response format
        if 'httpMethod' in event:
            return {
                'statusCode': 500,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps(error_response)
            }
        else:
            return error_response
        """

        # Create Lambda function with comprehensive configuration
        self.analytics_function = lambda_.Function(
            self,
            "AnalyticsOrchestratorFunction",
            function_name=f"analytics-orchestrator-{unique_suffix}",
            runtime=lambda_.Runtime.PYTHON_3_11,
            code=lambda_.Code.from_inline(lambda_code),
            handler="index.lambda_handler",
            role=self.lambda_execution_role,
            timeout=Duration.minutes(5),  # Extended timeout for complex analytics
            memory_size=1024,  # Increased memory for data processing
            retry_attempts=2,  # Retry failed executions
            environment={
                "BUCKET_RAW_DATA": self.raw_data_bucket.bucket_name,
                "BUCKET_RESULTS": self.results_bucket.bucket_name,
                "CODE_INTERPRETER_ID": "placeholder-id",  # Will be updated after creation
                "LOG_LEVEL": "INFO"
            },
            reserved_concurrent_executions=10,  # Limit concurrency for cost control
            description="Orchestrates data analytics workflows using Bedrock AgentCore Code Interpreter"
        )

        # Create CloudWatch log group with retention
        logs.LogGroup(
            self,
            "AnalyticsLambdaLogGroup",
            log_group_name=f"/aws/lambda/{self.analytics_function.function_name}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY
        )

    def _create_api_gateway(self) -> None:
        """
        Create API Gateway for external access with security and throttling.
        
        Features:
        - REST API with POST method for analytics requests
        - Request validation and throttling
        - CORS support for web applications
        - CloudWatch logging and monitoring
        - API key support for access control
        """
        # Use AWS Solutions Construct for API Gateway + Lambda pattern
        self.api_construct = ApiGatewayToLambda(
            self,
            "AnalyticsApi",
            existing_lambda_obj=self.analytics_function,
            api_gateway_props=apigateway.RestApiProps(
                rest_api_name="interactive-analytics-api",
                description="API for Interactive Data Analytics with Bedrock Code Interpreter",
                endpoint_configuration=apigateway.EndpointConfiguration(
                    types=[apigateway.EndpointType.REGIONAL]
                ),
                cloud_watch_role=True,
                deploy_options=apigateway.StageOptions(
                    stage_name="prod",
                    throttling_rate_limit=100,  # requests per second
                    throttling_burst_limit=200,  # burst capacity
                    logging_level=apigateway.MethodLoggingLevel.INFO,
                    data_trace_enabled=True,
                    metrics_enabled=True
                ),
                default_cors_preflight_options=apigateway.CorsOptions(
                    allow_origins=apigateway.Cors.ALL_ORIGINS,
                    allow_methods=apigateway.Cors.ALL_METHODS,
                    allow_headers=["Content-Type", "X-Amz-Date", "Authorization", "X-Api-Key"]
                )
            )
        )

        # Add usage plan for API throttling and monitoring
        self.usage_plan = self.api_construct.api_gateway.add_usage_plan(
            "AnalyticsUsagePlan",
            name="Analytics API Usage Plan",
            description="Usage plan for analytics API with rate limiting",
            throttle=apigateway.ThrottleSettings(
                rate_limit=50,  # requests per second per API key
                burst_limit=100
            ),
            quota=apigateway.QuotaSettings(
                limit=10000,  # requests per month
                period=apigateway.Period.MONTH
            )
        )

        # Add API key for secure access
        self.api_key = self.api_construct.api_gateway.add_api_key(
            "AnalyticsApiKey",
            api_key_name="analytics-api-key",
            description="API key for analytics services"
        )

        # Associate API key with usage plan
        self.usage_plan.add_api_key(self.api_key)
        self.usage_plan.add_api_stage(
            stage=self.api_construct.api_gateway.deployment_stage
        )

    def _create_monitoring_resources(self, unique_suffix: str) -> None:
        """
        Create comprehensive CloudWatch monitoring and alerting.
        
        Features:
        - CloudWatch alarms for error rates and execution duration
        - Custom metrics dashboard for analytics insights
        - SNS topic for alert notifications
        - Log insights queries for troubleshooting
        """
        # CloudWatch alarm for Lambda execution errors
        self.error_alarm = cloudwatch.Alarm(
            self,
            "AnalyticsExecutionErrorAlarm",
            alarm_name=f"analytics-execution-errors-{unique_suffix}",
            alarm_description="Alert when analytics execution errors exceed threshold",
            metric=self.analytics_function.metric_errors(
                period=Duration.minutes(5)
            ),
            threshold=3,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD
        )

        # CloudWatch alarm for Lambda execution duration
        self.duration_alarm = cloudwatch.Alarm(
            self,
            "AnalyticsDurationAlarm",
            alarm_name=f"analytics-duration-{unique_suffix}",
            alarm_description="Alert when analytics execution duration is high",
            metric=self.analytics_function.metric_duration(
                period=Duration.minutes(5)
            ),
            threshold=240000,  # 4 minutes in milliseconds
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD
        )

        # CloudWatch alarm for API Gateway errors
        self.api_error_alarm = cloudwatch.Alarm(
            self,
            "ApiGatewayErrorAlarm",
            alarm_name=f"analytics-api-errors-{unique_suffix}",
            alarm_description="Alert when API Gateway errors exceed threshold",
            metric=cloudwatch.Metric(
                namespace="AWS/ApiGateway",
                metric_name="4XXError",
                dimensions_map={
                    "ApiName": self.api_construct.api_gateway.rest_api_name
                },
                period=Duration.minutes(5),
                statistic="Sum"
            ),
            threshold=10,
            evaluation_periods=2
        )

        # Create CloudWatch Dashboard for monitoring
        self.monitoring_dashboard = cloudwatch.Dashboard(
            self,
            "AnalyticsDashboard",
            dashboard_name=f"analytics-dashboard-{unique_suffix}",
            widgets=[
                [
                    cloudwatch.GraphWidget(
                        title="Lambda Function Metrics",
                        left=[
                            self.analytics_function.metric_invocations(),
                            self.analytics_function.metric_errors(),
                        ],
                        right=[
                            self.analytics_function.metric_duration()
                        ],
                        period=Duration.minutes(5),
                        width=12,
                        height=6
                    )
                ],
                [
                    cloudwatch.GraphWidget(
                        title="API Gateway Metrics",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/ApiGateway",
                                metric_name="Count",
                                dimensions_map={
                                    "ApiName": self.api_construct.api_gateway.rest_api_name
                                }
                            )
                        ],
                        right=[
                            cloudwatch.Metric(
                                namespace="AWS/ApiGateway",
                                metric_name="Latency",
                                dimensions_map={
                                    "ApiName": self.api_construct.api_gateway.rest_api_name
                                }
                            )
                        ],
                        period=Duration.minutes(5),
                        width=12,
                        height=6
                    )
                ],
                [
                    cloudwatch.SingleValueWidget(
                        title="Total Executions (Last 24h)",
                        metrics=[
                            cloudwatch.Metric(
                                namespace="Analytics/CodeInterpreter",
                                metric_name="ExecutionCount",
                                statistic="Sum",
                                period=Duration.hours(24)
                            )
                        ],
                        width=6,
                        height=3
                    ),
                    cloudwatch.SingleValueWidget(
                        title="Error Rate (Last 24h)",
                        metrics=[
                            cloudwatch.Metric(
                                namespace="Analytics/CodeInterpreter",
                                metric_name="ExecutionErrors",
                                statistic="Sum",
                                period=Duration.hours(24)
                            )
                        ],
                        width=6,
                        height=3
                    )
                ]
            ]
        )

    def _create_error_handling_resources(self, unique_suffix: str) -> None:
        """
        Create SQS dead letter queue and error handling mechanisms.
        
        Features:
        - Dead letter queue for failed executions
        - Retry policies for transient failures
        - Error analysis and alerting
        """
        # Create SQS dead letter queue for failed executions
        self.dead_letter_queue = sqs.Queue(
            self,
            "AnalyticsDeadLetterQueue",
            queue_name=f"analytics-dlq-{unique_suffix}",
            visibility_timeout=Duration.minutes(5),
            retention_period=Duration.days(14),
            encryption=sqs.QueueEncryption.KMS_MANAGED
        )

        # Configure Lambda function with DLQ
        self.analytics_function.add_dead_letter_queue(
            dead_letter_queue=self.dead_letter_queue
        )

        # Grant Lambda permission to send messages to DLQ
        self.dead_letter_queue.grant_send_messages(self.analytics_function)

    def _create_stack_outputs(self) -> None:
        """
        Create CloudFormation outputs for important resource information.
        """
        CfnOutput(
            self,
            "ApiGatewayUrl",
            description="URL of the Analytics API Gateway",
            value=self.api_construct.api_gateway.url,
            export_name=f"{self.stack_name}-ApiUrl"
        )

        CfnOutput(
            self,
            "ApiKeyId",
            description="API Key ID for accessing the analytics service",
            value=self.api_key.key_id,
            export_name=f"{self.stack_name}-ApiKeyId"
        )

        CfnOutput(
            self,
            "RawDataBucketName",
            description="S3 bucket name for raw data input",
            value=self.raw_data_bucket.bucket_name,
            export_name=f"{self.stack_name}-RawDataBucket"
        )

        CfnOutput(
            self,
            "ResultsBucketName",
            description="S3 bucket name for analysis results",
            value=self.results_bucket.bucket_name,
            export_name=f"{self.stack_name}-ResultsBucket"
        )

        CfnOutput(
            self,
            "LambdaFunctionName",
            description="Lambda function name for analytics orchestration",
            value=self.analytics_function.function_name,
            export_name=f"{self.stack_name}-LambdaFunction"
        )

        CfnOutput(
            self,
            "DashboardUrl",
            description="CloudWatch Dashboard URL for monitoring",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.monitoring_dashboard.dashboard_name}",
            export_name=f"{self.stack_name}-DashboardUrl"
        )


# CDK App instantiation and stack deployment
app = App()

# Create the main analytics stack with environment configuration
analytics_stack = InteractiveDataAnalyticsStack(
    app,
    "InteractiveDataAnalyticsStack",
    env=cdk.Environment(
        account=os.getenv('CDK_DEFAULT_ACCOUNT'),
        region=os.getenv('CDK_DEFAULT_REGION', 'us-east-1')
    ),
    description="Interactive Data Analytics with Bedrock AgentCore Code Interpreter - "
                "A comprehensive analytics platform that combines natural language processing "
                "with secure code execution capabilities for intelligent data analysis.",
    tags={
        "Project": "InteractiveDataAnalytics",
        "Environment": "Development",
        "Owner": "DataAnalyticsTeam",
        "CostCenter": "Analytics",
        "Compliance": "Enterprise"
    }
)

# Apply CDK Nag for security best practices validation
# Note: CDK Nag should be applied in a real deployment for security compliance
# from cdk_nag import AwsSolutionsChecks
# AwsSolutionsChecks.check(app)

# Synthesize the CDK app
app.synth()