#!/usr/bin/env python3
"""
CDK Python application for Asynchronous API Patterns with API Gateway and SQS.

This application creates a complete asynchronous job processing system using:
- Amazon API Gateway for REST API endpoints
- Amazon SQS for message queuing with dead letter queue
- AWS Lambda for job processing and status checking
- Amazon DynamoDB for job status tracking
- Amazon S3 for result storage
- IAM roles with least privilege permissions
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Duration,
    RemovalPolicy,
    Stack,
    aws_apigateway as apigw,
    aws_dynamodb as dynamodb,
    aws_iam as iam,
    aws_lambda as lambda_,
    aws_lambda_event_sources as lambda_event_sources,
    aws_s3 as s3,
    aws_sqs as sqs,
)
from constructs import Construct


class AsyncApiPatternsStack(Stack):
    """
    CDK Stack for Asynchronous API Patterns with API Gateway and SQS.
    
    Creates a complete serverless architecture for handling long-running
    asynchronous jobs with immediate API response and status tracking.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique resource names
        self.project_name = f"async-api-{construct_id.lower()}"

        # Create core infrastructure
        self.create_storage_resources()
        self.create_message_queues()
        self.create_lambda_functions()
        self.create_api_gateway()
        self.create_outputs()

    def create_storage_resources(self) -> None:
        """Create S3 bucket for results and DynamoDB table for job tracking."""
        
        # S3 bucket for storing job results
        self.results_bucket = s3.Bucket(
            self,
            "ResultsBucket",
            bucket_name=f"{self.project_name}-results-{self.account}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        # DynamoDB table for job status tracking
        self.jobs_table = dynamodb.Table(
            self,
            "JobsTable",
            table_name=f"{self.project_name}-jobs",
            partition_key=dynamodb.Attribute(
                name="jobId",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            point_in_time_recovery=True,
            removal_policy=RemovalPolicy.DESTROY,
        )

    def create_message_queues(self) -> None:
        """Create SQS queues for job processing with dead letter queue."""
        
        # Dead Letter Queue for failed messages
        self.dead_letter_queue = sqs.Queue(
            self,
            "DeadLetterQueue",
            queue_name=f"{self.project_name}-dlq",
            message_retention_period=Duration.days(14),
            visibility_timeout=Duration.minutes(5),
        )

        # Main processing queue with DLQ configuration
        self.main_queue = sqs.Queue(
            self,
            "MainQueue",
            queue_name=f"{self.project_name}-main-queue",
            message_retention_period=Duration.days(14),
            visibility_timeout=Duration.minutes(5),
            dead_letter_queue=sqs.DeadLetterQueue(
                max_receive_count=3,
                queue=self.dead_letter_queue
            ),
        )

    def create_lambda_functions(self) -> None:
        """Create Lambda functions for job processing and status checking."""
        
        # Common Lambda execution role
        lambda_role = iam.Role(
            self,
            "LambdaExecutionRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
        )

        # Grant permissions for DynamoDB operations
        self.jobs_table.grant_read_write_data(lambda_role)

        # Grant permissions for S3 operations
        self.results_bucket.grant_read_write(lambda_role)

        # Grant permissions for SQS operations
        self.main_queue.grant_consume_messages(lambda_role)

        # Job Processor Lambda Function
        self.job_processor = lambda_.Function(
            self,
            "JobProcessor",
            function_name=f"{self.project_name}-job-processor",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            role=lambda_role,
            code=lambda_.Code.from_inline(self._get_job_processor_code()),
            timeout=Duration.minutes(5),
            memory_size=512,
            environment={
                "JOBS_TABLE_NAME": self.jobs_table.table_name,
                "RESULTS_BUCKET_NAME": self.results_bucket.bucket_name,
            },
        )

        # Configure SQS trigger for job processor
        self.job_processor.add_event_source(
            lambda_event_sources.SqsEventSource(
                self.main_queue,
                batch_size=10,
                max_batching_window=Duration.seconds(5),
            )
        )

        # Status Checker Lambda Function
        self.status_checker = lambda_.Function(
            self,
            "StatusChecker",
            function_name=f"{self.project_name}-status-checker",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            role=lambda_role,
            code=lambda_.Code.from_inline(self._get_status_checker_code()),
            timeout=Duration.seconds(30),
            memory_size=256,
            environment={
                "JOBS_TABLE_NAME": self.jobs_table.table_name,
            },
        )

    def create_api_gateway(self) -> None:
        """Create API Gateway with submit and status endpoints."""
        
        # Create API Gateway REST API
        self.api = apigw.RestApi(
            self,
            "AsyncApi",
            rest_api_name=f"{self.project_name}-api",
            description="Asynchronous API with SQS integration",
            endpoint_configuration=apigw.EndpointConfiguration(
                types=[apigw.EndpointType.REGIONAL]
            ),
            default_cors_preflight_options=apigw.CorsOptions(
                allow_origins=apigw.Cors.ALL_ORIGINS,
                allow_methods=apigw.Cors.ALL_METHODS,
                allow_headers=["Content-Type", "Authorization"],
            ),
        )

        # Create IAM role for API Gateway SQS integration
        api_gateway_role = iam.Role(
            self,
            "ApiGatewayRole",
            assumed_by=iam.ServicePrincipal("apigateway.amazonaws.com"),
        )

        # Grant API Gateway permission to send messages to SQS
        self.main_queue.grant_send_messages(api_gateway_role)

        # Create /submit endpoint with direct SQS integration
        submit_resource = self.api.root.add_resource("submit")
        
        # Request template for SQS integration
        request_template = {
            "application/json": '{"jobId": "$context.requestId", "data": $input.json("$"), "timestamp": "$context.requestTime"}'
        }

        # Response template for successful submission
        response_template = {
            "application/json": '{"jobId": "$context.requestId", "status": "queued", "message": "Job submitted successfully"}'
        }

        # Add POST method to /submit with SQS integration
        submit_integration = apigw.AwsIntegration(
            service="sqs",
            path=f"{self.account}/{self.main_queue.queue_name}",
            integration_http_method="POST",
            options=apigw.IntegrationOptions(
                credentials_role=api_gateway_role,
                request_parameters={
                    "integration.request.header.Content-Type": "'application/x-amz-json-1.0'",
                    "integration.request.querystring.Action": "'SendMessage'",
                    "integration.request.querystring.MessageBody": "method.request.body",
                },
                request_templates=request_template,
                integration_responses=[
                    apigw.IntegrationResponse(
                        status_code="200",
                        response_templates=response_template,
                    )
                ],
            ),
        )

        submit_resource.add_method(
            "POST",
            submit_integration,
            method_responses=[
                apigw.MethodResponse(
                    status_code="200",
                    response_models={
                        "application/json": apigw.Model.EMPTY_MODEL
                    },
                )
            ],
        )

        # Create /status/{jobId} endpoint with Lambda integration
        status_resource = self.api.root.add_resource("status")
        job_id_resource = status_resource.add_resource("{jobId}")

        # Lambda integration for status checking
        status_integration = apigw.LambdaIntegration(
            self.status_checker,
            proxy=True,
        )

        job_id_resource.add_method(
            "GET",
            status_integration,
            request_parameters={
                "method.request.path.jobId": True,
            },
        )

    def create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        
        cdk.CfnOutput(
            self,
            "ApiEndpoint",
            value=self.api.url,
            description="API Gateway endpoint URL",
        )

        cdk.CfnOutput(
            self,
            "MainQueueUrl",
            value=self.main_queue.queue_url,
            description="Main SQS queue URL",
        )

        cdk.CfnOutput(
            self,
            "DeadLetterQueueUrl",
            value=self.dead_letter_queue.queue_url,
            description="Dead letter queue URL",
        )

        cdk.CfnOutput(
            self,
            "JobsTableName",
            value=self.jobs_table.table_name,
            description="DynamoDB jobs table name",
        )

        cdk.CfnOutput(
            self,
            "ResultsBucketName",
            value=self.results_bucket.bucket_name,
            description="S3 results bucket name",
        )

    def _get_job_processor_code(self) -> str:
        """Return the job processor Lambda function code."""
        return '''
import json
import boto3
import time
import os
from datetime import datetime, timezone

dynamodb = boto3.resource('dynamodb')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    """
    Process jobs from SQS queue.
    
    This function receives job messages from SQS, updates job status in DynamoDB,
    performs processing work, stores results in S3, and handles errors gracefully.
    """
    table_name = os.environ['JOBS_TABLE_NAME']
    results_bucket = os.environ['RESULTS_BUCKET_NAME']
    
    table = dynamodb.Table(table_name)
    
    for record in event['Records']:
        try:
            # Parse message from SQS
            message_body = json.loads(record['body'])
            job_id = message_body['jobId']
            job_data = message_body['data']
            
            print(f"Processing job {job_id}")
            
            # Create initial job record
            table.put_item(
                Item={
                    'jobId': job_id,
                    'status': 'processing',
                    'createdAt': message_body.get('timestamp', datetime.now(timezone.utc).isoformat()),
                    'updatedAt': datetime.now(timezone.utc).isoformat(),
                    'data': job_data
                }
            )
            
            # Simulate processing work (replace with actual processing logic)
            print(f"Starting processing for job {job_id}")
            time.sleep(10)  # Simulate work
            
            # Generate result
            result = {
                'jobId': job_id,
                'result': f'Processed data: {job_data}',
                'processedAt': datetime.now(timezone.utc).isoformat(),
                'processingDuration': '10 seconds'
            }
            
            # Store result in S3
            s3.put_object(
                Bucket=results_bucket,
                Key=f'results/{job_id}.json',
                Body=json.dumps(result, indent=2),
                ContentType='application/json'
            )
            
            # Update job status to completed
            table.update_item(
                Key={'jobId': job_id},
                UpdateExpression='SET #status = :status, #result = :result, #updatedAt = :timestamp',
                ExpressionAttributeNames={
                    '#status': 'status',
                    '#result': 'result',
                    '#updatedAt': 'updatedAt'
                },
                ExpressionAttributeValues={
                    ':status': 'completed',
                    ':result': f's3://{results_bucket}/results/{job_id}.json',
                    ':timestamp': datetime.now(timezone.utc).isoformat()
                }
            )
            
            print(f"Successfully processed job {job_id}")
            
        except Exception as e:
            print(f"Error processing job {job_id}: {str(e)}")
            
            # Update job status to failed
            try:
                table.update_item(
                    Key={'jobId': job_id},
                    UpdateExpression='SET #status = :status, #error = :error, #updatedAt = :timestamp',
                    ExpressionAttributeNames={
                        '#status': 'status',
                        '#error': 'error',
                        '#updatedAt': 'updatedAt'
                    },
                    ExpressionAttributeValues={
                        ':status': 'failed',
                        ':error': str(e),
                        ':timestamp': datetime.now(timezone.utc).isoformat()
                    }
                )
            except Exception as update_error:
                print(f"Failed to update job status: {str(update_error)}")
            
            # Re-raise the exception to trigger SQS retry/DLQ behavior
            raise
    
    return {'statusCode': 200, 'body': 'Processing complete'}
'''

    def _get_status_checker_code(self) -> str:
        """Return the status checker Lambda function code."""
        return '''
import json
import boto3
import os

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    """
    Check job status in DynamoDB.
    
    This function handles GET requests to /status/{jobId} and returns
    the current job status, including completion details and error information.
    """
    table_name = os.environ['JOBS_TABLE_NAME']
    table = dynamodb.Table(table_name)
    
    # Extract job ID from path parameters
    job_id = event['pathParameters']['jobId']
    
    print(f"Checking status for job {job_id}")
    
    try:
        # Get job record from DynamoDB
        response = table.get_item(Key={'jobId': job_id})
        
        if 'Item' not in response:
            return {
                'statusCode': 404,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*',
                    'Access-Control-Allow-Methods': 'GET, OPTIONS',
                    'Access-Control-Allow-Headers': 'Content-Type, Authorization'
                },
                'body': json.dumps({
                    'error': 'Job not found',
                    'jobId': job_id
                })
            }
        
        job = response['Item']
        
        # Prepare response with job details
        response_body = {
            'jobId': job['jobId'],
            'status': job['status'],
            'createdAt': job['createdAt'],
            'updatedAt': job.get('updatedAt', job['createdAt'])
        }
        
        # Add optional fields if they exist
        if 'result' in job:
            response_body['result'] = job['result']
        
        if 'error' in job:
            response_body['error'] = job['error']
            
        if 'data' in job:
            response_body['originalData'] = job['data']
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'GET, OPTIONS',
                'Access-Control-Allow-Headers': 'Content-Type, Authorization'
            },
            'body': json.dumps(response_body, indent=2)
        }
        
    except Exception as e:
        print(f"Error checking job status: {str(e)}")
        
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'GET, OPTIONS',
                'Access-Control-Allow-Headers': 'Content-Type, Authorization'
            },
            'body': json.dumps({
                'error': 'Internal server error',
                'message': str(e),
                'jobId': job_id
            })
        }
'''


class AsyncApiPatternsApp(cdk.App):
    """CDK Application for Asynchronous API Patterns."""

    def __init__(self):
        super().__init__()

        # Get environment configuration
        env_config = self._get_environment_config()

        # Create the main stack
        AsyncApiPatternsStack(
            self,
            "AsyncApiPatternsStack",
            env=env_config,
            description="Asynchronous API Patterns with API Gateway and SQS - Complete serverless job processing system"
        )

    def _get_environment_config(self) -> cdk.Environment:
        """Get CDK environment configuration from environment variables or defaults."""
        return cdk.Environment(
            account=os.environ.get('CDK_DEFAULT_ACCOUNT'),
            region=os.environ.get('CDK_DEFAULT_REGION', 'us-east-1')
        )


# Create and run the CDK application
if __name__ == "__main__":
    app = AsyncApiPatternsApp()
    app.synth()