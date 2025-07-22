#!/usr/bin/env python3
"""
CDK Python application for Extracting Insights from Text with Amazon Comprehend

This application creates a complete NLP pipeline using Amazon Comprehend, AWS Lambda, 
Amazon S3, and Amazon EventBridge for both real-time and batch text processing.
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_s3 as s3,
    aws_lambda as lambda_,
    aws_iam as iam,
    aws_events as events,
    aws_events_targets as targets,
    aws_logs as logs,
    CfnOutput,
    RemovalPolicy,
    Duration,
)
from constructs import Construct
import json


class ComprehendNLPStack(Stack):
    """
    CDK Stack for Amazon Comprehend NLP Solution
    
    This stack creates:
    - S3 buckets for input and output data
    - IAM roles for Comprehend and Lambda services
    - Lambda function for real-time text processing
    - EventBridge rule for automated processing
    - CloudWatch logs for monitoring
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Create S3 buckets for input and output data
        self.input_bucket = s3.Bucket(
            self, "ComprehendInputBucket",
            bucket_name=f"comprehend-nlp-input-{self.account}-{self.region}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        self.output_bucket = s3.Bucket(
            self, "ComprehendOutputBucket",
            bucket_name=f"comprehend-nlp-output-{self.account}-{self.region}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        # Create IAM service role for Amazon Comprehend
        comprehend_role = iam.Role(
            self, "ComprehendServiceRole",
            assumed_by=iam.ServicePrincipal("comprehend.amazonaws.com"),
            description="Service role for Amazon Comprehend batch processing",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("ComprehendFullAccess")
            ],
        )

        # Add S3 permissions to Comprehend role
        comprehend_role.add_to_policy(
            iam.PolicyStatement(
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
        )

        # Create Lambda function for real-time text processing
        self.processor_function = lambda_.Function(
            self, "ComprehendProcessor",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_lambda_code()),
            timeout=Duration.seconds(60),
            memory_size=512,
            environment={
                "INPUT_BUCKET": self.input_bucket.bucket_name,
                "OUTPUT_BUCKET": self.output_bucket.bucket_name,
            },
            description="Lambda function for real-time text processing with Amazon Comprehend",
        )

        # Grant Lambda function permissions to use Comprehend
        self.processor_function.add_to_role_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "comprehend:DetectSentiment",
                    "comprehend:DetectEntities",
                    "comprehend:DetectKeyPhrases",
                    "comprehend:DetectDominantLanguage",
                    "comprehend:BatchDetectSentiment",
                    "comprehend:BatchDetectEntities",
                    "comprehend:BatchDetectKeyPhrases",
                ],
                resources=["*"],
            )
        )

        # Grant Lambda function permissions to access S3 buckets
        self.input_bucket.grant_read_write(self.processor_function)
        self.output_bucket.grant_read_write(self.processor_function)

        # Create EventBridge rule for S3 object creation events
        s3_event_rule = events.Rule(
            self, "S3ProcessingRule",
            description="Process new files uploaded to S3 input bucket",
            event_pattern=events.EventPattern(
                source=["aws.s3"],
                detail_type=["Object Created"],
                detail={
                    "bucket": {"name": [self.input_bucket.bucket_name]},
                    "object": {"key": [{"prefix": "input/"}]},
                },
            ),
        )

        # Add Lambda function as target for EventBridge rule
        s3_event_rule.add_target(
            targets.LambdaFunction(
                self.processor_function,
                retry_attempts=3,
            )
        )

        # Create CloudWatch log group for Lambda function
        log_group = logs.LogGroup(
            self, "ProcessorLogGroup",
            log_group_name=f"/aws/lambda/{self.processor_function.function_name}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )

        # Create Lambda function for batch processing results
        self.batch_processor_function = lambda_.Function(
            self, "BatchResultsProcessor",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_batch_processor_code()),
            timeout=Duration.seconds(300),
            memory_size=1024,
            environment={
                "OUTPUT_BUCKET": self.output_bucket.bucket_name,
            },
            description="Lambda function for processing batch job results",
        )

        # Grant batch processor permissions
        self.output_bucket.grant_read_write(self.batch_processor_function)
        self.batch_processor_function.add_to_role_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "comprehend:DescribeSentimentDetectionJob",
                    "comprehend:DescribeEntitiesDetectionJob",
                    "comprehend:DescribeTopicsDetectionJob",
                    "comprehend:DescribeKeyPhrasesDetectionJob",
                ],
                resources=["*"],
            )
        )

        # Create deployment script as Lambda function
        deployment_function = lambda_.Function(
            self, "DeploymentHelper",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_deployment_helper_code()),
            timeout=Duration.seconds(300),
            memory_size=512,
            environment={
                "INPUT_BUCKET": self.input_bucket.bucket_name,
                "OUTPUT_BUCKET": self.output_bucket.bucket_name,
                "COMPREHEND_ROLE_ARN": comprehend_role.role_arn,
            },
            description="Helper function for deploying sample data and configurations",
        )

        # Grant deployment helper necessary permissions
        self.input_bucket.grant_read_write(deployment_function)
        deployment_function.add_to_role_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "comprehend:StartSentimentDetectionJob",
                    "comprehend:StartEntitiesDetectionJob",
                    "comprehend:StartTopicsDetectionJob",
                    "comprehend:StartKeyPhrasesDetectionJob",
                ],
                resources=["*"],
            )
        )

        deployment_function.add_to_role_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["iam:PassRole"],
                resources=[comprehend_role.role_arn],
            )
        )

        # Stack outputs
        CfnOutput(
            self, "InputBucketName",
            value=self.input_bucket.bucket_name,
            description="S3 bucket for input text files",
        )

        CfnOutput(
            self, "OutputBucketName",
            value=self.output_bucket.bucket_name,
            description="S3 bucket for processed results",
        )

        CfnOutput(
            self, "ProcessorFunctionArn",
            value=self.processor_function.function_arn,
            description="ARN of the real-time text processor Lambda function",
        )

        CfnOutput(
            self, "ComprehendRoleArn",
            value=comprehend_role.role_arn,
            description="ARN of the Comprehend service role",
        )

        CfnOutput(
            self, "DeploymentHelperArn",
            value=deployment_function.function_arn,
            description="ARN of the deployment helper Lambda function",
        )

    def _get_lambda_code(self) -> str:
        """
        Returns the Lambda function code for real-time text processing.
        
        Returns:
            str: Python code for the Lambda function
        """
        return '''
import json
import boto3
import os
import logging
from datetime import datetime
from typing import Dict, List, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
comprehend = boto3.client('comprehend')
s3 = boto3.client('s3')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda handler for real-time text processing with Amazon Comprehend.
    
    Args:
        event: Lambda event data
        context: Lambda context object
        
    Returns:
        Dict containing processing results
    """
    try:
        logger.info(f"Processing event: {json.dumps(event)}")
        
        # Extract text from different event sources
        text = extract_text_from_event(event)
        
        if not text:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'No text provided for processing'})
            }
        
        # Validate text length (Comprehend limit is 5,000 UTF-8 characters)
        if len(text) > 5000:
            text = text[:5000]
            logger.warning("Text truncated to 5000 characters")
        
        # Process text with multiple Comprehend APIs
        results = process_text_with_comprehend(text)
        
        # Store results in S3 if output bucket is configured
        if os.environ.get('OUTPUT_BUCKET'):
            store_results_in_s3(results, text)
        
        return {
            'statusCode': 200,
            'body': json.dumps(results, default=str),
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            }
        }
        
    except Exception as e:
        logger.error(f"Error processing text: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': f'Processing failed: {str(e)}'})
        }

def extract_text_from_event(event: Dict[str, Any]) -> str:
    """
    Extract text content from various event sources.
    
    Args:
        event: Lambda event data
        
    Returns:
        str: Extracted text content
    """
    # Direct text input
    if 'text' in event:
        return event['text']
    
    # API Gateway event
    if 'body' in event:
        try:
            body = json.loads(event['body']) if isinstance(event['body'], str) else event['body']
            if 'text' in body:
                return body['text']
        except json.JSONDecodeError:
            pass
    
    # S3 event - read file content
    if 'Records' in event:
        for record in event['Records']:
            if record.get('eventSource') == 'aws:s3':
                bucket = record['s3']['bucket']['name']
                key = record['s3']['object']['key']
                
                try:
                    response = s3.get_object(Bucket=bucket, Key=key)
                    content = response['Body'].read().decode('utf-8')
                    return content
                except Exception as e:
                    logger.error(f"Error reading S3 object {bucket}/{key}: {str(e)}")
    
    # EventBridge event
    if 'detail' in event and 'object' in event['detail']:
        try:
            bucket = event['detail']['bucket']['name']
            key = event['detail']['object']['key']
            
            response = s3.get_object(Bucket=bucket, Key=key)
            content = response['Body'].read().decode('utf-8')
            return content
        except Exception as e:
            logger.error(f"Error reading S3 object from EventBridge: {str(e)}")
    
    return ""

def process_text_with_comprehend(text: str) -> Dict[str, Any]:
    """
    Process text using multiple Amazon Comprehend APIs.
    
    Args:
        text: Input text to process
        
    Returns:
        Dict containing all analysis results
    """
    results = {
        'timestamp': datetime.utcnow().isoformat(),
        'text_length': len(text),
        'text_preview': text[:100] + "..." if len(text) > 100 else text
    }
    
    try:
        # Detect dominant language
        language_response = comprehend.detect_dominant_language(Text=text)
        dominant_language = language_response['Languages'][0]['LanguageCode']
        results['dominant_language'] = {
            'language_code': dominant_language,
            'confidence': language_response['Languages'][0]['Score']
        }
        
        # Use detected language for subsequent analysis
        lang_code = dominant_language if dominant_language in ['en', 'es', 'fr', 'de', 'it', 'pt', 'ar', 'hi', 'ja', 'ko', 'zh', 'zh-TW'] else 'en'
        
        # Sentiment analysis
        sentiment_response = comprehend.detect_sentiment(Text=text, LanguageCode=lang_code)
        results['sentiment'] = {
            'sentiment': sentiment_response['Sentiment'],
            'confidence_scores': sentiment_response['SentimentScore']
        }
        
        # Entity detection
        entities_response = comprehend.detect_entities(Text=text, LanguageCode=lang_code)
        results['entities'] = [
            {
                'text': entity['Text'],
                'type': entity['Type'],
                'confidence': entity['Score'],
                'begin_offset': entity['BeginOffset'],
                'end_offset': entity['EndOffset']
            }
            for entity in entities_response['Entities']
        ]
        
        # Key phrase extraction
        key_phrases_response = comprehend.detect_key_phrases(Text=text, LanguageCode=lang_code)
        results['key_phrases'] = [
            {
                'text': phrase['Text'],
                'confidence': phrase['Score'],
                'begin_offset': phrase['BeginOffset'],
                'end_offset': phrase['EndOffset']
            }
            for phrase in key_phrases_response['KeyPhrases']
        ]
        
        # Add summary statistics
        results['summary'] = {
            'total_entities': len(results['entities']),
            'total_key_phrases': len(results['key_phrases']),
            'entity_types': list(set(entity['type'] for entity in results['entities'])),
            'sentiment_summary': sentiment_response['Sentiment']
        }
        
    except Exception as e:
        logger.error(f"Error in Comprehend processing: {str(e)}")
        results['error'] = str(e)
    
    return results

def store_results_in_s3(results: Dict[str, Any], original_text: str) -> None:
    """
    Store processing results in S3 for later analysis.
    
    Args:
        results: Processing results from Comprehend
        original_text: Original input text
    """
    try:
        output_bucket = os.environ.get('OUTPUT_BUCKET')
        if not output_bucket:
            return
        
        # Create a unique filename
        timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S_%f')
        filename = f"realtime_results/{timestamp}_results.json"
        
        # Prepare output data
        output_data = {
            'original_text': original_text,
            'processing_results': results,
            'processing_timestamp': datetime.utcnow().isoformat()
        }
        
        # Store in S3
        s3.put_object(
            Bucket=output_bucket,
            Key=filename,
            Body=json.dumps(output_data, indent=2, default=str),
            ContentType='application/json'
        )
        
        logger.info(f"Results stored in S3: {output_bucket}/{filename}")
        
    except Exception as e:
        logger.error(f"Error storing results in S3: {str(e)}")
'''

    def _get_batch_processor_code(self) -> str:
        """
        Returns the Lambda function code for batch processing results.
        
        Returns:
            str: Python code for the batch processor Lambda function
        """
        return '''
import json
import boto3
import os
import logging
from datetime import datetime
from typing import Dict, List, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
comprehend = boto3.client('comprehend')
s3 = boto3.client('s3')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda handler for processing batch job results.
    
    Args:
        event: Lambda event data
        context: Lambda context object
        
    Returns:
        Dict containing processing status
    """
    try:
        logger.info(f"Processing batch event: {json.dumps(event)}")
        
        # Extract job information from event
        job_id = event.get('job_id')
        job_type = event.get('job_type', 'sentiment')
        
        if not job_id:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'Job ID not provided'})
            }
        
        # Get job status and results
        job_status = get_job_status(job_id, job_type)
        
        if job_status['status'] == 'COMPLETED':
            # Process completed job results
            results = process_job_results(job_id, job_type, job_status)
            
            # Store aggregated results
            store_aggregated_results(job_id, job_type, results)
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'job_id': job_id,
                    'job_type': job_type,
                    'status': 'processed',
                    'results_summary': results
                })
            }
        else:
            return {
                'statusCode': 202,
                'body': json.dumps({
                    'job_id': job_id,
                    'job_type': job_type,
                    'status': job_status['status'],
                    'message': 'Job still in progress'
                })
            }
            
    except Exception as e:
        logger.error(f"Error processing batch results: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': f'Processing failed: {str(e)}'})
        }

def get_job_status(job_id: str, job_type: str) -> Dict[str, Any]:
    """
    Get status of a Comprehend batch job.
    
    Args:
        job_id: Job ID to check
        job_type: Type of job (sentiment, entities, topics, key_phrases)
        
    Returns:
        Dict containing job status information
    """
    try:
        if job_type == 'sentiment':
            response = comprehend.describe_sentiment_detection_job(JobId=job_id)
            job_props = response['SentimentDetectionJobProperties']
        elif job_type == 'entities':
            response = comprehend.describe_entities_detection_job(JobId=job_id)
            job_props = response['EntitiesDetectionJobProperties']
        elif job_type == 'topics':
            response = comprehend.describe_topics_detection_job(JobId=job_id)
            job_props = response['TopicsDetectionJobProperties']
        elif job_type == 'key_phrases':
            response = comprehend.describe_key_phrases_detection_job(JobId=job_id)
            job_props = response['KeyPhrasesDetectionJobProperties']
        else:
            raise ValueError(f"Unknown job type: {job_type}")
        
        return {
            'status': job_props['JobStatus'],
            'output_location': job_props.get('OutputDataConfig', {}).get('S3Uri'),
            'input_location': job_props.get('InputDataConfig', {}).get('S3Uri'),
            'submit_time': job_props.get('SubmitTime'),
            'end_time': job_props.get('EndTime')
        }
        
    except Exception as e:
        logger.error(f"Error getting job status: {str(e)}")
        raise

def process_job_results(job_id: str, job_type: str, job_status: Dict[str, Any]) -> Dict[str, Any]:
    """
    Process and analyze completed job results.
    
    Args:
        job_id: Job ID
        job_type: Type of job
        job_status: Job status information
        
    Returns:
        Dict containing processed results summary
    """
    try:
        output_location = job_status.get('output_location')
        if not output_location:
            return {'error': 'No output location found'}
        
        # Parse S3 URI
        s3_uri_parts = output_location.replace('s3://', '').split('/', 1)
        bucket = s3_uri_parts[0]
        prefix = s3_uri_parts[1] if len(s3_uri_parts) > 1 else ''
        
        # List and process result files
        response = s3.list_objects_v2(Bucket=bucket, Prefix=prefix)
        result_files = response.get('Contents', [])
        
        aggregated_results = {
            'job_id': job_id,
            'job_type': job_type,
            'total_files': len(result_files),
            'processed_timestamp': datetime.utcnow().isoformat()
        }
        
        # Process each result file
        for file_obj in result_files:
            if file_obj['Key'].endswith('.json'):
                try:
                    file_content = s3.get_object(Bucket=bucket, Key=file_obj['Key'])
                    file_data = json.loads(file_content['Body'].read().decode('utf-8'))
                    
                    # Process based on job type
                    if job_type == 'sentiment':
                        process_sentiment_results(file_data, aggregated_results)
                    elif job_type == 'entities':
                        process_entities_results(file_data, aggregated_results)
                    elif job_type == 'topics':
                        process_topics_results(file_data, aggregated_results)
                    elif job_type == 'key_phrases':
                        process_key_phrases_results(file_data, aggregated_results)
                        
                except Exception as e:
                    logger.error(f"Error processing file {file_obj['Key']}: {str(e)}")
        
        return aggregated_results
        
    except Exception as e:
        logger.error(f"Error processing job results: {str(e)}")
        return {'error': str(e)}

def process_sentiment_results(file_data: Dict, aggregated_results: Dict) -> None:
    """Process sentiment analysis results."""
    if 'sentiment_counts' not in aggregated_results:
        aggregated_results['sentiment_counts'] = {
            'POSITIVE': 0, 'NEGATIVE': 0, 'NEUTRAL': 0, 'MIXED': 0
        }
    
    for item in file_data:
        sentiment = item.get('Sentiment', 'NEUTRAL')
        aggregated_results['sentiment_counts'][sentiment] += 1

def process_entities_results(file_data: Dict, aggregated_results: Dict) -> None:
    """Process entity detection results."""
    if 'entity_counts' not in aggregated_results:
        aggregated_results['entity_counts'] = {}
    
    for item in file_data:
        for entity in item.get('Entities', []):
            entity_type = entity.get('Type', 'UNKNOWN')
            aggregated_results['entity_counts'][entity_type] = \
                aggregated_results['entity_counts'].get(entity_type, 0) + 1

def process_topics_results(file_data: Dict, aggregated_results: Dict) -> None:
    """Process topic modeling results."""
    aggregated_results['topics_summary'] = {
        'total_topics': len(file_data.get('topics', [])),
        'topic_details': file_data.get('topics', [])
    }

def process_key_phrases_results(file_data: Dict, aggregated_results: Dict) -> None:
    """Process key phrases results."""
    if 'key_phrases_summary' not in aggregated_results:
        aggregated_results['key_phrases_summary'] = {
            'total_phrases': 0,
            'top_phrases': []
        }
    
    for item in file_data:
        aggregated_results['key_phrases_summary']['total_phrases'] += \
            len(item.get('KeyPhrases', []))

def store_aggregated_results(job_id: str, job_type: str, results: Dict[str, Any]) -> None:
    """Store aggregated results in S3."""
    try:
        output_bucket = os.environ.get('OUTPUT_BUCKET')
        if not output_bucket:
            return
        
        timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S')
        filename = f"aggregated_results/{job_type}_{job_id}_{timestamp}.json"
        
        s3.put_object(
            Bucket=output_bucket,
            Key=filename,
            Body=json.dumps(results, indent=2, default=str),
            ContentType='application/json'
        )
        
        logger.info(f"Aggregated results stored: {output_bucket}/{filename}")
        
    except Exception as e:
        logger.error(f"Error storing aggregated results: {str(e)}")
'''

    def _get_deployment_helper_code(self) -> str:
        """
        Returns the Lambda function code for deployment helper.
        
        Returns:
            str: Python code for the deployment helper Lambda function
        """
        return '''
import json
import boto3
import os
import logging
from datetime import datetime
from typing import Dict, List, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
comprehend = boto3.client('comprehend')
s3 = boto3.client('s3')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda handler for deployment helper operations.
    
    Args:
        event: Lambda event data
        context: Lambda context object
        
    Returns:
        Dict containing deployment status
    """
    try:
        action = event.get('action', 'setup')
        
        if action == 'setup':
            return setup_sample_data()
        elif action == 'start_batch_jobs':
            return start_batch_jobs()
        elif action == 'cleanup':
            return cleanup_resources()
        else:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': f'Unknown action: {action}'})
            }
            
    except Exception as e:
        logger.error(f"Error in deployment helper: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': f'Deployment failed: {str(e)}'})
        }

def setup_sample_data() -> Dict[str, Any]:
    """
    Set up sample data for testing the NLP pipeline.
    
    Returns:
        Dict containing setup status
    """
    try:
        input_bucket = os.environ.get('INPUT_BUCKET')
        if not input_bucket:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'Input bucket not configured'})
            }
        
        sample_texts = [
            {
                'filename': 'positive_review.txt',
                'content': 'This product is absolutely amazing! The quality exceeded my expectations and the customer service was outstanding. I would definitely recommend this to anyone looking for a reliable solution.'
            },
            {
                'filename': 'negative_review.txt',
                'content': 'The device stopped working after just two weeks. Very disappointed with the build quality. The support team was unhelpful and took forever to respond.'
            },
            {
                'filename': 'neutral_review.txt',
                'content': 'The product is okay, nothing special. It works as described but doesn\\'t stand out from similar products. Price is reasonable for what you get.'
            },
            {
                'filename': 'support_ticket.txt',
                'content': 'Customer reporting login issues with mobile app. Error message: "Invalid credentials" appears even with correct password. Customer using iPhone 12, iOS 15.2.'
            },
            {
                'filename': 'billing_inquiry.txt',
                'content': 'Billing inquiry - customer charged twice for premium subscription. Transaction dates: March 15th and March 16th. Customer account: premium-user@example.com'
            },
            {
                'filename': 'technical_feedback.txt',
                'content': 'Our cloud infrastructure migration was successful. The new serverless architecture improved scalability and reduced costs by 40%. DevOps team recommends similar approach for other applications.'
            }
        ]
        
        uploaded_files = []
        for sample in sample_texts:
            key = f"input/{sample['filename']}"
            s3.put_object(
                Bucket=input_bucket,
                Key=key,
                Body=sample['content'],
                ContentType='text/plain'
            )
            uploaded_files.append(key)
            logger.info(f"Uploaded sample file: {key}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Sample data uploaded successfully',
                'files': uploaded_files,
                'bucket': input_bucket
            })
        }
        
    except Exception as e:
        logger.error(f"Error setting up sample data: {str(e)}")
        raise

def start_batch_jobs() -> Dict[str, Any]:
    """
    Start batch processing jobs for demonstration.
    
    Returns:
        Dict containing job information
    """
    try:
        input_bucket = os.environ.get('INPUT_BUCKET')
        output_bucket = os.environ.get('OUTPUT_BUCKET')
        comprehend_role_arn = os.environ.get('COMPREHEND_ROLE_ARN')
        
        if not all([input_bucket, output_bucket, comprehend_role_arn]):
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'Required environment variables not set'})
            }
        
        timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S')
        started_jobs = []
        
        # Start sentiment analysis job
        try:
            sentiment_job = comprehend.start_sentiment_detection_job(
                JobName=f'sentiment-analysis-{timestamp}',
                LanguageCode='en',
                InputDataConfig={
                    'S3Uri': f's3://{input_bucket}/input/',
                    'InputFormat': 'ONE_DOC_PER_FILE'
                },
                OutputDataConfig={
                    'S3Uri': f's3://{output_bucket}/sentiment/'
                },
                DataAccessRoleArn=comprehend_role_arn
            )
            started_jobs.append({
                'type': 'sentiment',
                'job_id': sentiment_job['JobId'],
                'status': 'SUBMITTED'
            })
            logger.info(f"Started sentiment job: {sentiment_job['JobId']}")
        except Exception as e:
            logger.error(f"Error starting sentiment job: {str(e)}")
        
        # Start entity detection job
        try:
            entities_job = comprehend.start_entities_detection_job(
                JobName=f'entities-detection-{timestamp}',
                LanguageCode='en',
                InputDataConfig={
                    'S3Uri': f's3://{input_bucket}/input/',
                    'InputFormat': 'ONE_DOC_PER_FILE'
                },
                OutputDataConfig={
                    'S3Uri': f's3://{output_bucket}/entities/'
                },
                DataAccessRoleArn=comprehend_role_arn
            )
            started_jobs.append({
                'type': 'entities',
                'job_id': entities_job['JobId'],
                'status': 'SUBMITTED'
            })
            logger.info(f"Started entities job: {entities_job['JobId']}")
        except Exception as e:
            logger.error(f"Error starting entities job: {str(e)}")
        
        # Start key phrases job
        try:
            key_phrases_job = comprehend.start_key_phrases_detection_job(
                JobName=f'key-phrases-{timestamp}',
                LanguageCode='en',
                InputDataConfig={
                    'S3Uri': f's3://{input_bucket}/input/',
                    'InputFormat': 'ONE_DOC_PER_FILE'
                },
                OutputDataConfig={
                    'S3Uri': f's3://{output_bucket}/key-phrases/'
                },
                DataAccessRoleArn=comprehend_role_arn
            )
            started_jobs.append({
                'type': 'key_phrases',
                'job_id': key_phrases_job['JobId'],
                'status': 'SUBMITTED'
            })
            logger.info(f"Started key phrases job: {key_phrases_job['JobId']}")
        except Exception as e:
            logger.error(f"Error starting key phrases job: {str(e)}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Batch jobs started successfully',
                'jobs': started_jobs,
                'timestamp': timestamp
            })
        }
        
    except Exception as e:
        logger.error(f"Error starting batch jobs: {str(e)}")
        raise

def cleanup_resources() -> Dict[str, Any]:
    """
    Clean up resources created during testing.
    
    Returns:
        Dict containing cleanup status
    """
    try:
        input_bucket = os.environ.get('INPUT_BUCKET')
        output_bucket = os.environ.get('OUTPUT_BUCKET')
        
        cleanup_actions = []
        
        # Clean up input bucket
        if input_bucket:
            try:
                response = s3.list_objects_v2(Bucket=input_bucket, Prefix='input/')
                if 'Contents' in response:
                    for obj in response['Contents']:
                        s3.delete_object(Bucket=input_bucket, Key=obj['Key'])
                        cleanup_actions.append(f"Deleted {obj['Key']}")
            except Exception as e:
                logger.error(f"Error cleaning input bucket: {str(e)}")
        
        # Clean up output bucket
        if output_bucket:
            try:
                response = s3.list_objects_v2(Bucket=output_bucket)
                if 'Contents' in response:
                    for obj in response['Contents']:
                        s3.delete_object(Bucket=output_bucket, Key=obj['Key'])
                        cleanup_actions.append(f"Deleted {obj['Key']}")
            except Exception as e:
                logger.error(f"Error cleaning output bucket: {str(e)}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Cleanup completed',
                'actions': cleanup_actions
            })
        }
        
    except Exception as e:
        logger.error(f"Error during cleanup: {str(e)}")
        raise
'''


class ComprehendNLPApp(cdk.App):
    """
    CDK Application for Amazon Comprehend NLP Solution
    """

    def __init__(self):
        super().__init__()

        # Create the main stack
        ComprehendNLPStack(
            self, "ComprehendNLPStack",
            description="Complete NLP solution using Amazon Comprehend with real-time and batch processing capabilities",
            env=cdk.Environment(
                account=os.environ.get('CDK_DEFAULT_ACCOUNT'),
                region=os.environ.get('CDK_DEFAULT_REGION', 'us-east-1')
            )
        )


# Create the CDK app
app = ComprehendNLPApp()

# Synthesize the CloudFormation template
app.synth()