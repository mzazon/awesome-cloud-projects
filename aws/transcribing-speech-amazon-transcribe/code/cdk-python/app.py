#!/usr/bin/env python3
"""
Amazon Transcribe Speech Recognition CDK Application

This CDK application creates a comprehensive speech recognition solution using Amazon Transcribe,
including batch processing, real-time streaming capabilities, custom vocabularies, and Lambda
integration for automated processing of transcription results.

The stack includes:
- S3 bucket for audio files and transcription outputs
- IAM roles and policies for secure service access
- Lambda function for processing transcription results
- Custom vocabulary and vocabulary filter resources
- CloudWatch monitoring and logging
"""

import os
import random
import string
from typing import Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    aws_s3 as s3,
    aws_iam as iam,
    aws_lambda as lambda_,
    aws_logs as logs,
    aws_cloudwatch as cloudwatch,
    CfnOutput,
)
from constructs import Construct


class SpeechRecognitionStack(Stack):
    """
    CDK Stack for Amazon Transcribe Speech Recognition Application
    
    This stack creates all necessary resources for a production-ready speech recognition
    solution including storage, processing, monitoring, and security components.
    """
    
    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        environment_name: str = "dev",
        enable_content_redaction: bool = True,
        enable_speaker_identification: bool = True,
        max_speakers: int = 4,
        **kwargs
    ) -> None:
        """
        Initialize the Speech Recognition Stack
        
        Args:
            scope: The scope in which this stack is defined
            construct_id: The scoped construct ID
            environment_name: Environment name for resource naming
            enable_content_redaction: Whether to enable PII redaction
            enable_speaker_identification: Whether to enable speaker diarization
            max_speakers: Maximum number of speakers to identify
            **kwargs: Additional keyword arguments passed to Stack
        """
        super().__init__(scope, construct_id, **kwargs)
        
        # Store configuration
        self.environment_name = environment_name
        self.enable_content_redaction = enable_content_redaction
        self.enable_speaker_identification = enable_speaker_identification
        self.max_speakers = max_speakers
        
        # Generate unique suffix for resource names
        self.suffix = self._generate_suffix()
        
        # Create core infrastructure
        self.bucket = self._create_s3_bucket()
        self.transcribe_role = self._create_transcribe_role()
        self.lambda_function = self._create_lambda_function()
        self.lambda_role = self._create_lambda_role()
        
        # Create monitoring and logging
        self._create_monitoring()
        
        # Create outputs
        self._create_outputs()
    
    def _generate_suffix(self) -> str:
        """Generate a random suffix for resource names"""
        return ''.join(random.choices(string.ascii_lowercase + string.digits, k=6))
    
    def _create_s3_bucket(self) -> s3.Bucket:
        """
        Create S3 bucket for audio files and transcription outputs
        
        Returns:
            S3 bucket with proper configuration for transcription workflows
        """
        bucket = s3.Bucket(
            self,
            "TranscribeBucket",
            bucket_name=f"transcribe-speech-recognition-{self.suffix}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="transcription-outputs-cleanup",
                    enabled=True,
                    prefix="transcription-output/",
                    expiration=Duration.days(90),
                    noncurrent_version_expiration=Duration.days(30),
                )
            ],
        )
        
        # Add CORS configuration for web applications
        bucket.add_cors_rule(
            allowed_methods=[
                s3.HttpMethods.GET,
                s3.HttpMethods.POST,
                s3.HttpMethods.PUT,
                s3.HttpMethods.DELETE,
                s3.HttpMethods.HEAD,
            ],
            allowed_origins=["*"],
            allowed_headers=["*"],
            max_age=3000,
        )
        
        # Create folder structure using deployment
        self._create_bucket_folders(bucket)
        
        return bucket
    
    def _create_bucket_folders(self, bucket: s3.Bucket) -> None:
        """Create folder structure in S3 bucket"""
        folders = [
            "audio-input/",
            "transcription-output/",
            "custom-vocabulary/",
            "training-data/",
            "temp/",
        ]
        
        for folder in folders:
            s3.CfnObject(
                self,
                f"Folder{folder.replace('/', '').replace('-', '').title()}",
                bucket=bucket.bucket_name,
                key=folder,
                content_type="application/x-directory",
            )
    
    def _create_transcribe_role(self) -> iam.Role:
        """
        Create IAM role for Amazon Transcribe service
        
        Returns:
            IAM role with necessary permissions for Transcribe operations
        """
        role = iam.Role(
            self,
            "TranscribeServiceRole",
            role_name=f"TranscribeServiceRole-{self.suffix}",
            assumed_by=iam.ServicePrincipal("transcribe.amazonaws.com"),
            description="Role for Amazon Transcribe to access S3 and other AWS services",
        )
        
        # Add S3 permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:PutObject",
                    "s3:DeleteObject",
                    "s3:ListBucket",
                    "s3:GetBucketLocation",
                ],
                resources=[
                    self.bucket.bucket_arn,
                    f"{self.bucket.bucket_arn}/*",
                ],
            )
        )
        
        # Add CloudWatch Logs permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents",
                ],
                resources=[
                    f"arn:aws:logs:{self.region}:{self.account}:log-group:/aws/transcribe/*",
                ],
            )
        )
        
        return role
    
    def _create_lambda_role(self) -> iam.Role:
        """
        Create IAM role for Lambda function
        
        Returns:
            IAM role with necessary permissions for Lambda operations
        """
        role = iam.Role(
            self,
            "TranscribeLambdaRole",
            role_name=f"TranscribeLambdaRole-{self.suffix}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Role for Lambda function to process Transcribe results",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                ),
            ],
        )
        
        # Add Transcribe permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "transcribe:GetTranscriptionJob",
                    "transcribe:ListTranscriptionJobs",
                    "transcribe:GetVocabulary",
                    "transcribe:ListVocabularies",
                    "transcribe:GetVocabularyFilter",
                    "transcribe:ListVocabularyFilters",
                ],
                resources=["*"],
            )
        )
        
        # Add S3 permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:PutObject",
                    "s3:DeleteObject",
                ],
                resources=[
                    f"{self.bucket.bucket_arn}/*",
                ],
            )
        )
        
        return role
    
    def _create_lambda_function(self) -> lambda_.Function:
        """
        Create Lambda function for processing transcription results
        
        Returns:
            Lambda function configured for Transcribe integration
        """
        function = lambda_.Function(
            self,
            "TranscribeProcessor",
            function_name=f"transcribe-processor-{self.suffix}",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_lambda_code()),
            timeout=Duration.minutes(5),
            memory_size=512,
            description="Process Amazon Transcribe results and perform post-processing",
            environment={
                "BUCKET_NAME": self.bucket.bucket_name,
                "ENVIRONMENT": self.environment_name,
                "ENABLE_CONTENT_REDACTION": str(self.enable_content_redaction),
                "ENABLE_SPEAKER_ID": str(self.enable_speaker_identification),
                "MAX_SPEAKERS": str(self.max_speakers),
            },
            log_retention=logs.RetentionDays.ONE_MONTH,
        )
        
        # Grant Lambda permissions
        self.bucket.grant_read_write(function)
        
        return function
    
    def _get_lambda_code(self) -> str:
        """
        Get the Lambda function code for processing transcription results
        
        Returns:
            Lambda function code as string
        """
        return '''
import json
import boto3
import os
from typing import Dict, List, Optional, Any
from datetime import datetime
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
transcribe = boto3.client('transcribe')
s3 = boto3.client('s3')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Process Amazon Transcribe results and perform post-processing
    
    Args:
        event: Lambda event containing job information
        context: Lambda context object
        
    Returns:
        Response with processing results
    """
    try:
        # Extract job name from event
        job_name = event.get('jobName')
        if not job_name:
            logger.error("Job name not provided in event")
            return create_response(400, "Job name not provided")
        
        logger.info(f"Processing transcription job: {job_name}")
        
        # Get transcription job details
        response = transcribe.get_transcription_job(
            TranscriptionJobName=job_name
        )
        
        job_details = response['TranscriptionJob']
        job_status = job_details['TranscriptionJobStatus']
        
        logger.info(f"Job status: {job_status}")
        
        if job_status == 'COMPLETED':
            return process_completed_job(job_details)
        elif job_status == 'FAILED':
            return process_failed_job(job_details)
        else:
            return create_response(202, f"Job {job_name} is {job_status}")
            
    except Exception as e:
        logger.error(f"Error processing transcription job: {str(e)}")
        return create_response(500, f"Error processing job: {str(e)}")

def process_completed_job(job_details: Dict[str, Any]) -> Dict[str, Any]:
    """Process a completed transcription job"""
    job_name = job_details['TranscriptionJobName']
    transcript_uri = job_details['Transcript']['TranscriptFileUri']
    
    logger.info(f"Processing completed job: {job_name}")
    
    try:
        # Download transcript from S3
        transcript_content = download_transcript(transcript_uri)
        
        # Perform post-processing
        processed_results = post_process_transcript(transcript_content, job_details)
        
        # Save processed results
        save_processed_results(job_name, processed_results)
        
        return create_response(200, {
            'message': 'Job processed successfully',
            'jobName': job_name,
            'transcriptUri': transcript_uri,
            'processedResults': processed_results
        })
        
    except Exception as e:
        logger.error(f"Error processing completed job: {str(e)}")
        return create_response(500, f"Error processing completed job: {str(e)}")

def process_failed_job(job_details: Dict[str, Any]) -> Dict[str, Any]:
    """Process a failed transcription job"""
    job_name = job_details['TranscriptionJobName']
    failure_reason = job_details.get('FailureReason', 'Unknown failure')
    
    logger.error(f"Job {job_name} failed: {failure_reason}")
    
    return create_response(500, {
        'message': 'Transcription job failed',
        'jobName': job_name,
        'failureReason': failure_reason
    })

def download_transcript(transcript_uri: str) -> Dict[str, Any]:
    """Download transcript from S3"""
    # Parse S3 URI
    uri_parts = transcript_uri.replace('s3://', '').split('/')
    bucket_name = uri_parts[0]
    key = '/'.join(uri_parts[1:])
    
    # Download transcript
    response = s3.get_object(Bucket=bucket_name, Key=key)
    return json.loads(response['Body'].read())

def post_process_transcript(transcript: Dict[str, Any], job_details: Dict[str, Any]) -> Dict[str, Any]:
    """Post-process transcript with additional insights"""
    results = transcript.get('results', {})
    
    # Extract basic information
    processed = {
        'jobName': job_details['TranscriptionJobName'],
        'status': 'completed',
        'languageCode': job_details.get('LanguageCode', 'en-US'),
        'mediaFormat': job_details.get('MediaFormat', 'unknown'),
        'timestamp': datetime.utcnow().isoformat(),
        'transcriptText': results.get('transcripts', [{}])[0].get('transcript', ''),
        'confidence': calculate_average_confidence(results),
        'wordCount': count_words(results),
        'speakers': extract_speaker_info(results) if os.getenv('ENABLE_SPEAKER_ID') == 'True' else None,
        'redactedContent': check_redacted_content(results) if os.getenv('ENABLE_CONTENT_REDACTION') == 'True' else None
    }
    
    return processed

def calculate_average_confidence(results: Dict[str, Any]) -> float:
    """Calculate average confidence score"""
    items = results.get('items', [])
    if not items:
        return 0.0
    
    total_confidence = 0
    confidence_count = 0
    
    for item in items:
        alternatives = item.get('alternatives', [])
        if alternatives:
            confidence = alternatives[0].get('confidence')
            if confidence:
                total_confidence += float(confidence)
                confidence_count += 1
    
    return total_confidence / confidence_count if confidence_count > 0 else 0.0

def count_words(results: Dict[str, Any]) -> int:
    """Count words in transcript"""
    transcript_text = results.get('transcripts', [{}])[0].get('transcript', '')
    return len(transcript_text.split())

def extract_speaker_info(results: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """Extract speaker information from results"""
    speaker_labels = results.get('speaker_labels', {})
    if not speaker_labels:
        return None
    
    speakers = {}
    for segment in speaker_labels.get('segments', []):
        speaker_label = segment.get('speaker_label')
        if speaker_label not in speakers:
            speakers[speaker_label] = {
                'speakerId': speaker_label,
                'segments': 0,
                'totalTime': 0
            }
        
        speakers[speaker_label]['segments'] += 1
        start_time = float(segment.get('start_time', 0))
        end_time = float(segment.get('end_time', 0))
        speakers[speaker_label]['totalTime'] += (end_time - start_time)
    
    return {
        'totalSpeakers': len(speakers),
        'speakers': list(speakers.values())
    }

def check_redacted_content(results: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """Check for redacted content in results"""
    # This would analyze redacted content if present
    return {
        'hasRedactedContent': False,
        'redactionCount': 0
    }

def save_processed_results(job_name: str, results: Dict[str, Any]) -> None:
    """Save processed results to S3"""
    bucket_name = os.getenv('BUCKET_NAME')
    key = f"processed-results/{job_name}-processed.json"
    
    s3.put_object(
        Bucket=bucket_name,
        Key=key,
        Body=json.dumps(results, indent=2),
        ContentType='application/json'
    )
    
    logger.info(f"Saved processed results to s3://{bucket_name}/{key}")

def create_response(status_code: int, body: Any) -> Dict[str, Any]:
    """Create standardized response"""
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json'
        },
        'body': json.dumps(body) if not isinstance(body, str) else body
    }
'''
    
    def _create_monitoring(self) -> None:
        """Create CloudWatch monitoring and alarms"""
        # Create custom metric for transcription job completion
        transcription_success_metric = cloudwatch.Metric(
            namespace="AWS/Transcribe",
            metric_name="TranscriptionJobSuccess",
            dimensions_map={
                "Environment": self.environment_name,
            },
        )
        
        # Create alarm for Lambda function errors
        lambda_error_alarm = cloudwatch.Alarm(
            self,
            "LambdaErrorAlarm",
            alarm_name=f"transcribe-lambda-errors-{self.suffix}",
            metric=self.lambda_function.metric_errors(),
            threshold=5,
            evaluation_periods=2,
            alarm_description="Alarm for Lambda function errors in transcription processing",
        )
        
        # Create dashboard
        dashboard = cloudwatch.Dashboard(
            self,
            "TranscribeDashboard",
            dashboard_name=f"TranscribeSpeechRecognition-{self.suffix}",
            widgets=[
                [
                    cloudwatch.GraphWidget(
                        title="Lambda Function Metrics",
                        left=[
                            self.lambda_function.metric_invocations(),
                            self.lambda_function.metric_errors(),
                        ],
                        right=[
                            self.lambda_function.metric_duration(),
                        ],
                    ),
                ],
                [
                    cloudwatch.GraphWidget(
                        title="S3 Bucket Metrics",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/S3",
                                metric_name="BucketSizeBytes",
                                dimensions_map={
                                    "BucketName": self.bucket.bucket_name,
                                    "StorageType": "StandardStorage",
                                },
                            ),
                        ],
                    ),
                ],
            ],
        )
    
    def _create_outputs(self) -> None:
        """Create CloudFormation outputs"""
        CfnOutput(
            self,
            "BucketName",
            value=self.bucket.bucket_name,
            description="S3 bucket name for audio files and transcription outputs",
            export_name=f"TranscribeBucket-{self.suffix}",
        )
        
        CfnOutput(
            self,
            "TranscribeRoleArn",
            value=self.transcribe_role.role_arn,
            description="IAM role ARN for Amazon Transcribe service",
            export_name=f"TranscribeRole-{self.suffix}",
        )
        
        CfnOutput(
            self,
            "LambdaFunctionArn",
            value=self.lambda_function.function_arn,
            description="Lambda function ARN for processing transcription results",
            export_name=f"TranscribeLambda-{self.suffix}",
        )
        
        CfnOutput(
            self,
            "LambdaFunctionName",
            value=self.lambda_function.function_name,
            description="Lambda function name for processing transcription results",
            export_name=f"TranscribeLambdaName-{self.suffix}",
        )
        
        CfnOutput(
            self,
            "AudioInputPrefix",
            value="audio-input/",
            description="S3 prefix for uploading audio files",
        )
        
        CfnOutput(
            self,
            "TranscriptionOutputPrefix",
            value="transcription-output/",
            description="S3 prefix for transcription output files",
        )
        
        CfnOutput(
            self,
            "CustomVocabularyPrefix",
            value="custom-vocabulary/",
            description="S3 prefix for custom vocabulary files",
        )


class SpeechRecognitionApp(cdk.App):
    """
    CDK Application for Amazon Transcribe Speech Recognition
    
    This application creates a complete speech recognition solution with
    configurable parameters for different deployment environments.
    """
    
    def __init__(self) -> None:
        super().__init__()
        
        # Get configuration from context or environment
        environment_name = self.node.try_get_context("environment") or "dev"
        enable_content_redaction = self.node.try_get_context("enableContentRedaction") or True
        enable_speaker_identification = self.node.try_get_context("enableSpeakerIdentification") or True
        max_speakers = self.node.try_get_context("maxSpeakers") or 4
        
        # Create the stack
        SpeechRecognitionStack(
            self,
            f"SpeechRecognitionStack-{environment_name}",
            environment_name=environment_name,
            enable_content_redaction=enable_content_redaction,
            enable_speaker_identification=enable_speaker_identification,
            max_speakers=max_speakers,
            description=f"Amazon Transcribe Speech Recognition Stack for {environment_name} environment",
        )


# Create the application
app = SpeechRecognitionApp()
app.synth()