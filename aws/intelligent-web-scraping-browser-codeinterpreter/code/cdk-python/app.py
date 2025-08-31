#!/usr/bin/env python3
"""
Intelligent Web Scraping with AgentCore Browser and Code Interpreter
CDK Python Application

This CDK application deploys infrastructure for an intelligent web scraping solution
that combines AWS Bedrock AgentCore Browser for automated web navigation with
AgentCore Code Interpreter for intelligent data processing and analysis.

Author: AWS CDK Generator
Version: 1.0
"""

import os
from typing import Any, Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    aws_lambda as lambda_,
    aws_iam as iam,
    aws_s3 as s3,
    aws_events as events,
    aws_events_targets as targets,
    aws_sqs as sqs,
    aws_logs as logs,
    aws_cloudwatch as cloudwatch,
    CfnOutput,
)
from constructs import Construct


class IntelligentWebScrapingStack(Stack):
    """
    CDK Stack for Intelligent Web Scraping with AgentCore Services
    
    This stack creates the complete infrastructure for an AI-powered web scraping
    solution including Lambda orchestration, S3 storage, EventBridge scheduling,
    and comprehensive monitoring with CloudWatch.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        project_name: Optional[str] = None,
        **kwargs: Any
    ) -> None:
        """
        Initialize the Intelligent Web Scraping Stack
        
        Args:
            scope: The parent construct
            construct_id: Unique identifier for this stack
            project_name: Optional project name for resource naming
            **kwargs: Additional keyword arguments
        """
        super().__init__(scope, construct_id, **kwargs)

        # Set project name with fallback
        self.project_name = project_name or "intelligent-scraper"
        
        # Create core infrastructure components
        self._create_s3_buckets()
        self._create_iam_roles()
        self._create_dead_letter_queue()
        self._create_lambda_function()
        self._create_eventbridge_scheduling()
        self._create_monitoring_resources()
        self._create_outputs()

    def _create_s3_buckets(self) -> None:
        """Create S3 buckets for input configurations and output data storage"""
        
        # Input bucket for scraping configurations
        self.input_bucket = s3.Bucket(
            self,
            "InputBucket",
            bucket_name=f"{self.project_name}-input-{self.account}-{self.region}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteOldVersions",
                    enabled=True,
                    noncurrent_version_expiration=Duration.days(30)
                )
            ]
        )
        
        # Output bucket for processed results
        self.output_bucket = s3.Bucket(
            self,
            "OutputBucket",
            bucket_name=f"{self.project_name}-output-{self.account}-{self.region}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="TransitionToIA",
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

    def _create_iam_roles(self) -> None:
        """Create IAM roles with appropriate permissions for Lambda and AgentCore services"""
        
        # Lambda execution role with comprehensive permissions
        self.lambda_role = iam.Role(
            self,
            "LambdaExecutionRole",
            role_name=f"{self.project_name}-lambda-role",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole")
            ],
            inline_policies={
                "AgentCoreAndS3Access": iam.PolicyDocument(
                    statements=[
                        # AgentCore Browser permissions
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "bedrock-agentcore:StartBrowserSession",
                                "bedrock-agentcore:StopBrowserSession",
                                "bedrock-agentcore:GetBrowserSession",
                                "bedrock-agentcore:UpdateBrowserStream",
                            ],
                            resources=["*"]
                        ),
                        # AgentCore Code Interpreter permissions
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "bedrock-agentcore:StartCodeInterpreterSession",
                                "bedrock-agentcore:StopCodeInterpreterSession",
                                "bedrock-agentcore:GetCodeInterpreterSession",
                                "bedrock-agentcore:ExecuteCode",
                            ],
                            resources=["*"]
                        ),
                        # S3 bucket access
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:GetObject",
                                "s3:PutObject",
                                "s3:ListBucket",
                                "s3:GetObjectVersion"
                            ],
                            resources=[
                                self.input_bucket.bucket_arn,
                                f"{self.input_bucket.bucket_arn}/*",
                                self.output_bucket.bucket_arn,
                                f"{self.output_bucket.bucket_arn}/*"
                            ]
                        ),
                        # CloudWatch metrics permissions
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "cloudwatch:PutMetricData"
                            ],
                            resources=["*"]
                        ),
                        # SQS permissions for DLQ
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "sqs:SendMessage",
                                "sqs:GetQueueAttributes"
                            ],
                            resources=["*"]
                        )
                    ]
                )
            }
        )

    def _create_dead_letter_queue(self) -> None:
        """Create SQS Dead Letter Queue for failed Lambda executions"""
        
        self.dead_letter_queue = sqs.Queue(
            self,
            "DeadLetterQueue",
            queue_name=f"{self.project_name}-dlq",
            visibility_timeout=Duration.minutes(5),
            retention_period=Duration.days(14),
            encryption=sqs.QueueEncryption.SQS_MANAGED
        )

    def _create_lambda_function(self) -> None:
        """Create the main Lambda function for workflow orchestration"""
        
        # Lambda function code
        lambda_code = """
import json
import boto3
import time
import logging
import uuid
from datetime import datetime
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    try:
        s3 = boto3.client('s3')
        agentcore = boto3.client('bedrock-agentcore')
        cloudwatch = boto3.client('cloudwatch')
        
        # Get configuration from S3
        bucket_input = event.get('bucket_input', context.function_name.split('-')[0] + '-input')
        bucket_output = event.get('bucket_output', context.function_name.split('-')[0] + '-output')
        
        try:
            config_response = s3.get_object(
                Bucket=bucket_input,
                Key='scraper-config.json'
            )
            config = json.loads(config_response['Body'].read())
        except ClientError as e:
            logger.warning(f"Could not load scraper config: {e}")
            # Use default configuration
            config = {
                'scraping_scenarios': [
                    {
                        'name': 'demo_scenario',
                        'description': 'Demo scraping scenario',
                        'target_url': 'https://books.toscrape.com/',
                        'extraction_rules': {
                            'product_titles': {'selector': 'h3 a', 'attribute': 'title'},
                            'prices': {'selector': '.price_color', 'attribute': 'textContent'},
                            'availability': {'selector': '.availability', 'attribute': 'textContent'}
                        },
                        'session_config': {'timeout_seconds': 30}
                    }
                ]
            }
        
        logger.info(f"Processing {len(config['scraping_scenarios'])} scenarios")
        
        all_scraped_data = []
        
        for scenario in config['scraping_scenarios']:
            logger.info(f"Processing scenario: {scenario['name']}")
            
            # Start browser session (simulation for preview)
            try:
                session_response = agentcore.start_browser_session(
                    browserIdentifier='default-browser',
                    name=f"{scenario['name']}-{int(time.time())}",
                    sessionTimeoutSeconds=scenario['session_config']['timeout_seconds']
                )
                browser_session_id = session_response['sessionId']
                logger.info(f"Started browser session: {browser_session_id}")
                
                # Simulate scraping results (replace with actual implementation)
                scenario_data = {
                    'scenario_name': scenario['name'],
                    'target_url': scenario['target_url'],
                    'timestamp': datetime.utcnow().isoformat(),
                    'session_id': browser_session_id,
                    'extracted_data': {
                        'product_titles': ['Sample Book 1', 'Sample Book 2', 'Sample Book 3'],
                        'prices': ['£51.77', '£53.74', '£50.10'],
                        'availability': ['In stock', 'In stock', 'Out of stock']
                    }
                }
                
                all_scraped_data.append(scenario_data)
                
                # Stop browser session
                agentcore.stop_browser_session(sessionId=browser_session_id)
                
            except Exception as e:
                logger.error(f"Browser session error for scenario {scenario['name']}: {e}")
                # Continue with next scenario
                continue
        
        # Start Code Interpreter session for data processing
        try:
            code_session_response = agentcore.start_code_interpreter_session(
                codeInterpreterIdentifier='default-code-interpreter',
                name=f"data-processor-{int(time.time())}",
                sessionTimeoutSeconds=300
            )
            code_session_id = code_session_response['sessionId']
            logger.info(f"Started code interpreter session: {code_session_id}")
            
            # Process data with analysis
            processing_results = process_scraped_data(all_scraped_data)
            
            # Stop code interpreter session
            agentcore.stop_code_interpreter_session(sessionId=code_session_id)
            
        except Exception as e:
            logger.error(f"Code interpreter error: {e}")
            # Fall back to local processing
            processing_results = process_scraped_data(all_scraped_data)
        
        # Save results to S3
        result_data = {
            'raw_data': all_scraped_data,
            'analysis': processing_results,
            'execution_metadata': {
                'timestamp': datetime.utcnow().isoformat(),
                'function_name': context.function_name,
                'request_id': context.aws_request_id
            }
        }
        
        result_key = f'scraping-results-{int(time.time())}.json'
        s3.put_object(
            Bucket=bucket_output,
            Key=result_key,
            Body=json.dumps(result_data, indent=2),
            ContentType='application/json'
        )
        
        # Send metrics to CloudWatch
        cloudwatch.put_metric_data(
            Namespace=f'IntelligentScraper/{context.function_name}',
            MetricData=[
                {
                    'MetricName': 'ScrapingJobs',
                    'Value': len(config['scraping_scenarios']),
                    'Unit': 'Count'
                },
                {
                    'MetricName': 'DataPointsExtracted',
                    'Value': sum(len(data.get('extracted_data', {}).get('product_titles', [])) for data in all_scraped_data),
                    'Unit': 'Count'
                }
            ]
        )
        
        logger.info(f"Results saved to s3://{bucket_output}/{result_key}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Scraping completed successfully',
                'scenarios_processed': len(config['scraping_scenarios']),
                'total_data_points': sum(len(data.get('extracted_data', {}).get('product_titles', [])) for data in all_scraped_data),
                'result_location': f's3://{bucket_output}/{result_key}'
            })
        }
        
    except Exception as e:
        logger.error(f"Error in scraping workflow: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'request_id': context.aws_request_id
            })
        }

def process_scraped_data(scraped_data):
    \"\"\"Process and analyze scraped data\"\"\"
    total_items = sum(len(data.get('extracted_data', {}).get('product_titles', [])) for data in scraped_data)
    
    # Analyze prices
    all_prices = []
    for data in scraped_data:
        for price_str in data.get('extracted_data', {}).get('prices', []):
            # Extract numeric value from price string
            numeric_price = ''.join(filter(lambda x: x.isdigit() or x == '.', price_str))
            if numeric_price:
                all_prices.append(float(numeric_price))
    
    # Calculate availability stats
    all_availability = []
    for data in scraped_data:
        all_availability.extend(data.get('extracted_data', {}).get('availability', []))
    
    in_stock_count = sum(1 for status in all_availability if 'stock' in status.lower())
    
    analysis = {
        'total_products_scraped': total_items,
        'price_analysis': {
            'average_price': sum(all_prices) / len(all_prices) if all_prices else 0,
            'min_price': min(all_prices) if all_prices else 0,
            'max_price': max(all_prices) if all_prices else 0,
            'price_count': len(all_prices)
        },
        'availability_analysis': {
            'total_items_checked': len(all_availability),
            'in_stock_count': in_stock_count,
            'out_of_stock_count': len(all_availability) - in_stock_count,
            'availability_rate': (in_stock_count / len(all_availability) * 100) if all_availability else 0
        },
        'data_quality_score': (total_items / max(1, len(scraped_data))) * 100,
        'processing_timestamp': datetime.utcnow().isoformat()
    }
    
    return analysis
"""
        
        # Create Lambda function
        self.lambda_function = lambda_.Function(
            self,
            "ScrapingOrchestratorFunction",
            function_name=f"{self.project_name}-orchestrator",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(lambda_code),
            role=self.lambda_role,
            timeout=Duration.minutes(15),
            memory_size=1024,
            retry_attempts=2,
            dead_letter_queue=self.dead_letter_queue,
            environment={
                "S3_BUCKET_INPUT": self.input_bucket.bucket_name,
                "S3_BUCKET_OUTPUT": self.output_bucket.bucket_name,
                "ENVIRONMENT": "production",
                "LOG_LEVEL": "INFO"
            },
            description="Intelligent web scraping orchestrator using AgentCore services"
        )

    def _create_eventbridge_scheduling(self) -> None:
        """Create EventBridge rule for scheduled scraping execution"""
        
        # EventBridge rule for scheduled execution
        self.schedule_rule = events.Rule(
            self,
            "ScrapingScheduleRule",
            rule_name=f"{self.project_name}-schedule",
            description="Scheduled intelligent web scraping execution",
            schedule=events.Schedule.rate(Duration.hours(6)),
            enabled=True
        )
        
        # Add Lambda function as target
        self.schedule_rule.add_target(
            targets.LambdaFunction(
                self.lambda_function,
                event=events.RuleTargetInput.from_object({
                    "bucket_input": self.input_bucket.bucket_name,
                    "bucket_output": self.output_bucket.bucket_name,
                    "scheduled_execution": True
                })
            )
        )

    def _create_monitoring_resources(self) -> None:
        """Create CloudWatch monitoring resources including dashboards and log groups"""
        
        # Create log group for Lambda function
        self.log_group = logs.LogGroup(
            self,
            "LambdaLogGroup",
            log_group_name=f"/aws/lambda/{self.lambda_function.function_name}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY
        )
        
        # Create CloudWatch dashboard
        self.dashboard = cloudwatch.Dashboard(
            self,
            "ScrapingMonitoringDashboard",
            dashboard_name=f"{self.project_name}-monitoring"
        )
        
        # Add widgets to dashboard
        self.dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Scraping Activity",
                left=[
                    cloudwatch.Metric(
                        namespace=f"IntelligentScraper/{self.lambda_function.function_name}",
                        metric_name="ScrapingJobs",
                        statistic="Sum"
                    ),
                    cloudwatch.Metric(
                        namespace=f"IntelligentScraper/{self.lambda_function.function_name}",
                        metric_name="DataPointsExtracted",
                        statistic="Sum"
                    )
                ],
                width=12,
                height=6
            ),
            cloudwatch.GraphWidget(
                title="Lambda Performance",
                left=[
                    self.lambda_function.metric_duration(),
                    self.lambda_function.metric_errors(),
                    self.lambda_function.metric_invocations()
                ],
                width=12,
                height=6
            )
        )
        
        # Add log insights widget
        self.dashboard.add_widgets(
            cloudwatch.LogQueryWidget(
                title="Recent Errors",
                log_groups=[self.log_group],
                query_lines=[
                    "fields @timestamp, @message",
                    "filter @message like /ERROR/",
                    "sort @timestamp desc",
                    "limit 20"
                ],
                width=24,
                height=6
            )
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource references"""
        
        CfnOutput(
            self,
            "InputBucketName",
            value=self.input_bucket.bucket_name,
            description="S3 bucket for scraping configurations",
            export_name=f"{self.stack_name}-InputBucket"
        )
        
        CfnOutput(
            self,
            "OutputBucketName",
            value=self.output_bucket.bucket_name,
            description="S3 bucket for scraping results",
            export_name=f"{self.stack_name}-OutputBucket"
        )
        
        CfnOutput(
            self,
            "LambdaFunctionName",
            value=self.lambda_function.function_name,
            description="Lambda function for scraping orchestration",
            export_name=f"{self.stack_name}-LambdaFunction"
        )
        
        CfnOutput(
            self,
            "LambdaFunctionArn",
            value=self.lambda_function.function_arn,
            description="ARN of the Lambda function",
            export_name=f"{self.stack_name}-LambdaFunctionArn"
        )
        
        CfnOutput(
            self,
            "DashboardUrl",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.dashboard.dashboard_name}",
            description="CloudWatch dashboard URL for monitoring",
            export_name=f"{self.stack_name}-DashboardUrl"
        )
        
        CfnOutput(
            self,
            "DeadLetterQueueUrl",
            value=self.dead_letter_queue.queue_url,
            description="SQS Dead Letter Queue URL",
            export_name=f"{self.stack_name}-DLQUrl"
        )


class IntelligentWebScrapingApp(cdk.App):
    """
    CDK Application for Intelligent Web Scraping
    
    This application creates the complete infrastructure stack for the intelligent
    web scraping solution with configurable deployment options.
    """

    def __init__(self) -> None:
        """Initialize the CDK application"""
        super().__init__()
        
        # Get configuration from context or environment variables
        project_name = self.node.try_get_context("project_name") or os.environ.get("PROJECT_NAME", "intelligent-scraper")
        env_name = self.node.try_get_context("environment") or os.environ.get("ENVIRONMENT", "dev")
        
        # Create the main stack
        IntelligentWebScrapingStack(
            self,
            f"IntelligentWebScrapingStack-{env_name}",
            project_name=f"{project_name}-{env_name}",
            description="Intelligent Web Scraping with AgentCore Browser and Code Interpreter",
            env=cdk.Environment(
                account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
                region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
            ),
            tags={
                "Application": "IntelligentWebScraping",
                "Environment": env_name,
                "ManagedBy": "CDK",
                "CostCenter": "DataEngineering",
                "Owner": "DataTeam"
            }
        )


# Application entry point
app = IntelligentWebScrapingApp()
app.synth()