#!/usr/bin/env python3
"""
CDK Python application for Simple Daily Quote Generator with Lambda and S3.

This application creates a serverless architecture using AWS Lambda and S3 to serve
random inspirational quotes via a Function URL endpoint.
"""

import aws_cdk as cdk
from constructs import Construct
from aws_cdk import (
    Stack,
    aws_lambda as _lambda,
    aws_s3 as s3,
    aws_iam as iam,
    aws_s3_deployment as s3_deployment,
    RemovalPolicy,
    CfnOutput,
    Duration
)
import json
from typing import Dict, Any


class DailyQuoteGeneratorStack(Stack):
    """
    CDK Stack for the Daily Quote Generator application.
    
    Creates:
    - S3 bucket for storing quote data
    - Lambda function for serving quotes
    - IAM role with minimal permissions
    - Function URL for direct HTTP access
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Create S3 bucket for storing quotes
        quotes_bucket = s3.Bucket(
            self, "QuotesBucket",
            bucket_name=f"daily-quotes-{self.account}-{self.region}",
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,  # Enable cleanup of objects during stack deletion
            versioning=False,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteIncompleteMultipartUploads",
                    abort_incomplete_multipart_upload_after=Duration.days(1)
                )
            ]
        )

        # Create quotes data to upload to S3
        quotes_data: Dict[str, Any] = {
            "quotes": [
                {
                    "text": "The only way to do great work is to love what you do.",
                    "author": "Steve Jobs"
                },
                {
                    "text": "Innovation distinguishes between a leader and a follower.",
                    "author": "Steve Jobs"
                },
                {
                    "text": "Life is what happens to you while you're busy making other plans.",
                    "author": "John Lennon"
                },
                {
                    "text": "The future belongs to those who believe in the beauty of their dreams.",
                    "author": "Eleanor Roosevelt"
                },
                {
                    "text": "It is during our darkest moments that we must focus to see the light.",
                    "author": "Aristotle"
                },
                {
                    "text": "Success is not final, failure is not fatal: it is the courage to continue that counts.",
                    "author": "Winston Churchill"
                }
            ]
        }

        # Deploy quotes data to S3 bucket
        s3_deployment.BucketDeployment(
            self, "QuotesDeployment",
            sources=[
                s3_deployment.Source.json_data("quotes.json", quotes_data)
            ],
            destination_bucket=quotes_bucket,
            retain_on_delete=False
        )

        # Create Lambda function for quote generation
        quote_function = _lambda.Function(
            self, "QuoteFunction",
            function_name="daily-quote-generator",
            runtime=_lambda.Runtime.PYTHON_3_12,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline(self._get_lambda_code()),
            timeout=Duration.seconds(30),
            memory_size=128,
            architecture=_lambda.Architecture.ARM_64,  # ARM64 for better price-performance
            environment={
                "BUCKET_NAME": quotes_bucket.bucket_name
            },
            tracing=_lambda.Tracing.ACTIVE,  # Enable X-Ray tracing
            retry_attempts=0,  # No retries for this simple API
            dead_letter_queue_enabled=False
        )

        # Grant Lambda function read access to S3 bucket
        quotes_bucket.grant_read(quote_function)

        # Create Function URL for direct HTTP access
        function_url = quote_function.add_function_url(
            auth_type=_lambda.FunctionUrlAuthType.NONE,
            cors=_lambda.FunctionUrlCorsOptions(
                allow_credentials=False,
                allow_headers=["*"],
                allow_methods=[_lambda.HttpMethod.GET],
                allow_origins=["*"],
                max_age=Duration.days(1)
            )
        )

        # Add tags to all resources for cost tracking and governance
        cdk.Tags.of(self).add("Project", "DailyQuoteGenerator")
        cdk.Tags.of(self).add("Environment", "Production")
        cdk.Tags.of(self).add("CostCenter", "Engineering")

        # Output important information
        CfnOutput(
            self, "BucketName",
            value=quotes_bucket.bucket_name,
            description="S3 bucket containing quote data"
        )

        CfnOutput(
            self, "FunctionName",
            value=quote_function.function_name,
            description="Lambda function name for quote generation"
        )

        CfnOutput(
            self, "FunctionUrl",
            value=function_url.url,
            description="Direct HTTPS endpoint for the quote API"
        )

        CfnOutput(
            self, "FunctionArn",
            value=quote_function.function_arn,
            description="Lambda function ARN for monitoring and integration"
        )

    def _get_lambda_code(self) -> str:
        """
        Returns the Lambda function code as a string.
        
        Returns:
            str: Python code for the Lambda function
        """
        return '''
import json
import boto3
import random
import os
import logging
from typing import Dict, Any, List
from botocore.exceptions import ClientError

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda function handler for serving random quotes.
    
    Args:
        event: Lambda event object containing request information
        context: Lambda context object containing runtime information
        
    Returns:
        Dict containing HTTP response with quote data or error message
    """
    # Initialize S3 client
    s3 = boto3.client('s3')
    bucket_name = os.environ['BUCKET_NAME']
    
    try:
        logger.info(f"Fetching quotes from bucket: {bucket_name}")
        
        # Get quotes from S3
        response = s3.get_object(Bucket=bucket_name, Key='quotes.json')
        quotes_data = json.loads(response['Body'].read().decode('utf-8'))
        
        # Validate quotes data structure
        if 'quotes' not in quotes_data or not quotes_data['quotes']:
            raise ValueError("Invalid quotes data structure")
            
        quotes_list: List[Dict[str, str]] = quotes_data['quotes']
        
        # Select random quote
        random_quote = random.choice(quotes_list)
        
        # Validate quote structure
        if 'text' not in random_quote or 'author' not in random_quote:
            raise ValueError("Invalid quote structure")
            
        logger.info(f"Selected quote by: {random_quote['author']}")
        
        # Return successful response
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'GET',
                'Cache-Control': 'no-cache, no-store, must-revalidate',
                'X-Content-Type-Options': 'nosniff',
                'X-Frame-Options': 'DENY'
            },
            'body': json.dumps({
                'quote': random_quote['text'],
                'author': random_quote['author'],
                'timestamp': context.aws_request_id,
                'function_version': context.function_version
            }, ensure_ascii=False)
        }
        
    except ClientError as e:
        error_code = e.response['Error']['Code']
        logger.error(f"S3 client error: {error_code} - {str(e)}")
        
        if error_code == 'NoSuchBucket':
            error_message = "Quote storage not found"
        elif error_code == 'NoSuchKey':
            error_message = "Quote data not found"
        elif error_code == 'AccessDenied':
            error_message = "Access denied to quote storage"
        else:
            error_message = "Failed to access quote storage"
            
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': error_message,
                'request_id': context.aws_request_id
            })
        }
        
    except json.JSONDecodeError as e:
        logger.error(f"JSON decode error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Invalid quote data format',
                'request_id': context.aws_request_id
            })
        }
        
    except ValueError as e:
        logger.error(f"Data validation error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Quote data validation failed',
                'request_id': context.aws_request_id
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
                'request_id': context.aws_request_id
            })
        }
'''


app = cdk.App()

# Create the stack with descriptive naming
DailyQuoteGeneratorStack(
    app, "DailyQuoteGeneratorStack",
    description="Simple Daily Quote Generator using Lambda and S3",
    env=cdk.Environment(
        account=app.node.try_get_context("account"),
        region=app.node.try_get_context("region")
    )
)

app.synth()