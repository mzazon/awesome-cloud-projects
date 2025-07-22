#!/usr/bin/env python3
"""
Text-to-Speech Solutions with Amazon Polly CDK Application

This CDK application demonstrates a comprehensive text-to-speech solution using Amazon Polly,
including batch processing, voice customization, and SSML support.
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_s3 as s3,
    aws_lambda as lambda_,
    aws_iam as iam,
    aws_logs as logs,
    aws_cloudfront as cloudfront,
    aws_cloudfront_origins as origins,
    aws_apigateway as apigw,
    aws_events as events,
    aws_events_targets as targets,
)
from constructs import Construct
import os


class TextToSpeechPollyStack(Stack):
    """
    CDK Stack for Text-to-Speech Solutions with Amazon Polly
    
    This stack creates:
    - S3 bucket for audio storage with CloudFront distribution
    - Lambda function for batch text-to-speech processing
    - API Gateway for real-time synthesis requests
    - IAM roles with least privilege access
    - CloudWatch monitoring and logging
    """
    
    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)
        
        # Create S3 bucket for audio storage
        self.audio_bucket = self._create_audio_bucket()
        
        # Create IAM role for Lambda functions
        self.lambda_role = self._create_lambda_role()
        
        # Create Lambda function for batch processing
        self.batch_processor = self._create_batch_processor()
        
        # Create Lambda function for real-time API
        self.realtime_processor = self._create_realtime_processor()
        
        # Create CloudFront distribution for audio delivery
        self.cdn_distribution = self._create_cloudfront_distribution()
        
        # Create API Gateway for real-time requests
        self.api_gateway = self._create_api_gateway()
        
        # Create EventBridge rule for scheduled processing
        self._create_scheduled_processing()
        
        # Create outputs
        self._create_outputs()
    
    def _create_audio_bucket(self) -> s3.Bucket:
        """Create S3 bucket for storing generated audio files"""
        bucket = s3.Bucket(
            self, "AudioStorageBucket",
            bucket_name=f"polly-audio-storage-{self.account}-{self.region}",
            versioning=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteOldVersions",
                    enabled=True,
                    noncurrent_version_expiration=Duration.days(30),
                ),
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
                        ),
                    ]
                )
            ],
            cors=[
                s3.CorsRule(
                    allowed_methods=[s3.HttpMethods.GET, s3.HttpMethods.HEAD],
                    allowed_origins=["*"],
                    allowed_headers=["*"],
                    max_age=3000,
                )
            ],
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )
        
        return bucket
    
    def _create_lambda_role(self) -> iam.Role:
        """Create IAM role for Lambda functions with appropriate permissions"""
        role = iam.Role(
            self, "PollyLambdaRole",
            role_name=f"PollyLambdaRole-{self.stack_name}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
            inline_policies={
                "PollyAccess": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "polly:SynthesizeSpeech",
                                "polly:DescribeVoices",
                                "polly:GetLexicon",
                                "polly:ListLexicons",
                                "polly:PutLexicon",
                                "polly:DeleteLexicon",
                                "polly:StartSpeechSynthesisTask",
                                "polly:GetSpeechSynthesisTask",
                                "polly:ListSpeechSynthesisTasks",
                            ],
                            resources=["*"]
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:GetObject",
                                "s3:PutObject",
                                "s3:DeleteObject",
                                "s3:PutObjectAcl",
                            ],
                            resources=[
                                self.audio_bucket.bucket_arn,
                                f"{self.audio_bucket.bucket_arn}/*"
                            ]
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=["s3:ListBucket"],
                            resources=[self.audio_bucket.bucket_arn]
                        ),
                    ]
                )
            }
        )
        
        return role
    
    def _create_batch_processor(self) -> lambda_.Function:
        """Create Lambda function for batch text-to-speech processing"""
        function = lambda_.Function(
            self, "BatchProcessor",
            function_name=f"polly-batch-processor-{self.stack_name}",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="index.lambda_handler",
            role=self.lambda_role,
            timeout=Duration.minutes(15),
            memory_size=1024,
            environment={
                "BUCKET_NAME": self.audio_bucket.bucket_name,
                "DEFAULT_VOICE_ID": "Joanna",
                "DEFAULT_ENGINE": "neural",
                "LOG_LEVEL": "INFO",
            },
            log_retention=logs.RetentionDays.ONE_WEEK,
            dead_letter_queue_enabled=True,
            code=lambda_.Code.from_inline("""
import boto3
import json
import os
import logging
from typing import Dict, Any, Optional
from urllib.parse import unquote_plus
import uuid
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

# Initialize AWS clients
polly_client = boto3.client('polly')
s3_client = boto3.client('s3')

def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    \"\"\"
    Lambda handler for batch text-to-speech processing
    
    Supports multiple input methods:
    - Direct invocation with text content
    - S3 event trigger for file processing
    - API Gateway requests
    \"\"\"
    try:
        bucket_name = os.environ['BUCKET_NAME']
        
        # Determine input source and extract text
        text_content, voice_id, engine, output_format = extract_request_parameters(event)
        
        logger.info(f"Processing text with voice: {voice_id}, engine: {engine}")
        
        # Validate text content
        if not text_content or len(text_content.strip()) == 0:
            raise ValueError("Text content cannot be empty")
        
        if len(text_content) > 200000:  # Polly limit for synchronous synthesis
            return process_long_form_content(text_content, voice_id, engine, bucket_name, context)
        
        # Synthesize speech
        response = polly_client.synthesize_speech(
            Text=text_content,
            OutputFormat=output_format,
            VoiceId=voice_id,
            Engine=engine,
            TextType='ssml' if text_content.strip().startswith('<speak>') else 'text'
        )
        
        # Generate unique output key
        request_id = getattr(context, 'aws_request_id', str(uuid.uuid4()))
        timestamp = datetime.now().strftime('%Y/%m/%d')
        output_key = f"audio/{timestamp}/{request_id}.{output_format}"
        
        # Save audio to S3
        audio_data = response['AudioStream'].read()
        s3_client.put_object(
            Bucket=bucket_name,
            Key=output_key,
            Body=audio_data,
            ContentType=f'audio/{output_format}',
            Metadata={
                'voice-id': voice_id,
                'engine': engine,
                'character-count': str(len(text_content)),
                'processing-time': str(response['ResponseMetadata'].get('HTTPHeaders', {}).get('x-amzn-RequestId', ''))
            }
        )
        
        # Create response
        result = {
            'statusCode': 200,
            'body': {
                'message': 'Speech synthesis completed successfully',
                'audio_url': f"s3://{bucket_name}/{output_key}",
                'audio_key': output_key,
                'voice_id': voice_id,
                'engine': engine,
                'character_count': len(text_content),
                'output_format': output_format,
                'request_id': request_id
            }
        }
        
        # Handle API Gateway response format
        if 'httpMethod' in event:
            result['body'] = json.dumps(result['body'])
            result['headers'] = {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'POST, OPTIONS',
                'Access-Control-Allow-Headers': 'Content-Type, Authorization'
            }
        
        logger.info(f"Successfully processed {len(text_content)} characters")
        return result
        
    except Exception as e:
        logger.error(f"Error processing request: {str(e)}")
        error_response = {
            'statusCode': 500,
            'body': {
                'error': str(e),
                'message': 'Failed to process text-to-speech request'
            }
        }
        
        if 'httpMethod' in event:
            error_response['body'] = json.dumps(error_response['body'])
            error_response['headers'] = {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            }
        
        return error_response

def extract_request_parameters(event: Dict[str, Any]) -> tuple:
    \"\"\"Extract and validate request parameters from various event sources\"\"\"
    default_voice = os.environ.get('DEFAULT_VOICE_ID', 'Joanna')
    default_engine = os.environ.get('DEFAULT_ENGINE', 'neural')
    default_format = 'mp3'
    
    # Handle S3 event trigger
    if 'Records' in event and event['Records'][0].get('eventSource') == 'aws:s3':
        record = event['Records'][0]
        bucket = record['s3']['bucket']['name']
        key = unquote_plus(record['s3']['object']['key'])
        
        # Read text content from S3
        response = s3_client.get_object(Bucket=bucket, Key=key)
        text_content = response['Body'].read().decode('utf-8')
        
        # Extract parameters from object metadata or use defaults
        metadata = response.get('Metadata', {})
        voice_id = metadata.get('voice-id', default_voice)
        engine = metadata.get('engine', default_engine)
        output_format = metadata.get('output-format', default_format)
        
        return text_content, voice_id, engine, output_format
    
    # Handle API Gateway request
    elif 'httpMethod' in event:
        if event['httpMethod'] == 'OPTIONS':
            return '', default_voice, default_engine, default_format
        
        body = json.loads(event.get('body', '{}'))
        text_content = body.get('text', '')
        voice_id = body.get('voice_id', default_voice)
        engine = body.get('engine', default_engine)
        output_format = body.get('output_format', default_format)
        
        return text_content, voice_id, engine, output_format
    
    # Handle direct invocation
    else:
        text_content = event.get('text', '')
        voice_id = event.get('voice_id', default_voice)
        engine = event.get('engine', default_engine)
        output_format = event.get('output_format', default_format)
        
        return text_content, voice_id, engine, output_format

def process_long_form_content(text: str, voice_id: str, engine: str, bucket_name: str, context) -> Dict[str, Any]:
    \"\"\"Process long-form content using asynchronous synthesis\"\"\"
    try:
        # Use long-form engine for better results with long content
        if engine == 'neural' and len(text) > 3000:
            engine = 'long-form' if voice_id in ['Joanna', 'Matthew', 'Ruth', 'Stephen'] else 'neural'
        
        # Start asynchronous synthesis task
        request_id = getattr(context, 'aws_request_id', str(uuid.uuid4()))
        timestamp = datetime.now().strftime('%Y/%m/%d')
        output_key = f"audio/long-form/{timestamp}/{request_id}.mp3"
        
        response = polly_client.start_speech_synthesis_task(
            Text=text,
            OutputFormat='mp3',
            OutputS3BucketName=bucket_name,
            OutputS3KeyPrefix=f"audio/long-form/{timestamp}/",
            VoiceId=voice_id,
            Engine=engine,
            TextType='ssml' if text.strip().startswith('<speak>') else 'text'
        )
        
        return {
            'statusCode': 202,
            'body': {
                'message': 'Long-form synthesis task started',
                'task_id': response['SynthesisTask']['TaskId'],
                'status': response['SynthesisTask']['TaskStatus'],
                'output_uri': response['SynthesisTask'].get('OutputUri', ''),
                'character_count': len(text),
                'voice_id': voice_id,
                'engine': engine
            }
        }
        
    except Exception as e:
        logger.error(f"Error starting long-form synthesis: {str(e)}")
        raise
""")
        )
        
        return function
    
    def _create_realtime_processor(self) -> lambda_.Function:
        """Create Lambda function for real-time text-to-speech API requests"""
        function = lambda_.Function(
            self, "RealtimeProcessor",
            function_name=f"polly-realtime-processor-{self.stack_name}",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="index.lambda_handler",
            role=self.lambda_role,
            timeout=Duration.seconds(30),
            memory_size=512,
            environment={
                "BUCKET_NAME": self.audio_bucket.bucket_name,
                "DEFAULT_VOICE_ID": "Joanna",
                "DEFAULT_ENGINE": "neural",
                "LOG_LEVEL": "INFO",
            },
            log_retention=logs.RetentionDays.ONE_WEEK,
            code=lambda_.Code.from_inline("""
import boto3
import json
import os
import logging
from typing import Dict, Any
import base64

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

# Initialize AWS clients
polly_client = boto3.client('polly')

def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    \"\"\"
    Lambda handler for real-time text-to-speech processing
    
    Optimized for low-latency responses with audio streaming
    \"\"\"
    try:
        # Handle CORS preflight
        if event.get('httpMethod') == 'OPTIONS':
            return {
                'statusCode': 200,
                'headers': {
                    'Access-Control-Allow-Origin': '*',
                    'Access-Control-Allow-Methods': 'POST, OPTIONS',
                    'Access-Control-Allow-Headers': 'Content-Type, Authorization'
                },
                'body': ''
            }
        
        # Parse request body
        body = json.loads(event.get('body', '{}'))
        text_content = body.get('text', '')
        voice_id = body.get('voice_id', os.environ.get('DEFAULT_VOICE_ID', 'Joanna'))
        engine = body.get('engine', os.environ.get('DEFAULT_ENGINE', 'neural'))
        output_format = body.get('output_format', 'mp3')
        return_audio = body.get('return_audio', False)  # Return base64 encoded audio
        
        # Validate input
        if not text_content or len(text_content.strip()) == 0:
            return create_error_response('Text content cannot be empty', 400)
        
        if len(text_content) > 3000:  # Limit for real-time processing
            return create_error_response('Text too long for real-time processing. Use batch endpoint.', 400)
        
        logger.info(f"Processing real-time request: {len(text_content)} characters")
        
        # Synthesize speech
        response = polly_client.synthesize_speech(
            Text=text_content,
            OutputFormat=output_format,
            VoiceId=voice_id,
            Engine=engine,
            TextType='ssml' if text_content.strip().startswith('<speak>') else 'text'
        )
        
        # Read audio data
        audio_data = response['AudioStream'].read()
        
        # Prepare response
        result = {
            'message': 'Speech synthesis completed',
            'voice_id': voice_id,
            'engine': engine,
            'character_count': len(text_content),
            'output_format': output_format,
            'audio_size_bytes': len(audio_data)
        }
        
        # Include base64 encoded audio if requested
        if return_audio:
            result['audio_data'] = base64.b64encode(audio_data).decode('utf-8')
            result['audio_encoding'] = 'base64'
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'POST, OPTIONS',
                'Access-Control-Allow-Headers': 'Content-Type, Authorization'
            },
            'body': json.dumps(result)
        }
        
    except Exception as e:
        logger.error(f"Error in real-time processing: {str(e)}")
        return create_error_response(str(e), 500)

def create_error_response(message: str, status_code: int) -> Dict[str, Any]:
    \"\"\"Create standardized error response\"\"\"
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps({
            'error': message,
            'status_code': status_code
        })
    }
""")
        )
        
        return function
    
    def _create_cloudfront_distribution(self) -> cloudfront.Distribution:
        """Create CloudFront distribution for audio content delivery"""
        distribution = cloudfront.Distribution(
            self, "AudioCDN",
            default_behavior=cloudfront.BehaviorOptions(
                origin=origins.S3Origin(self.audio_bucket),
                viewer_protocol_policy=cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
                allowed_methods=cloudfront.AllowedMethods.ALLOW_GET_HEAD,
                cached_methods=cloudfront.CachedMethods.CACHE_GET_HEAD,
                cache_policy=cloudfront.CachePolicy.CACHING_OPTIMIZED,
                compress=True,
            ),
            additional_behaviors={
                "/audio/*": cloudfront.BehaviorOptions(
                    origin=origins.S3Origin(self.audio_bucket),
                    viewer_protocol_policy=cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
                    cache_policy=cloudfront.CachePolicy.CACHING_OPTIMIZED_FOR_UNCOMPRESSED_OBJECTS,
                    allowed_methods=cloudfront.AllowedMethods.ALLOW_GET_HEAD,
                    cached_methods=cloudfront.CachedMethods.CACHE_GET_HEAD,
                )
            },
            price_class=cloudfront.PriceClass.PRICE_CLASS_100,
            geo_restriction=cloudfront.GeoRestriction.allowlist("US", "CA", "GB", "DE", "FR"),
            comment=f"Audio delivery for {self.stack_name}",
            enabled=True,
        )
        
        return distribution
    
    def _create_api_gateway(self) -> apigw.RestApi:
        """Create API Gateway for text-to-speech endpoints"""
        api = apigw.RestApi(
            self, "PollyAPI",
            rest_api_name=f"polly-tts-api-{self.stack_name}",
            description="Text-to-Speech API using Amazon Polly",
            default_cors_preflight_options=apigw.CorsOptions(
                allow_origins=apigw.Cors.ALL_ORIGINS,
                allow_methods=apigw.Cors.ALL_METHODS,
                allow_headers=["Content-Type", "Authorization"],
            ),
            endpoint_types=[apigw.EndpointType.REGIONAL],
        )
        
        # Create /batch endpoint for long-form processing
        batch_resource = api.root.add_resource("batch")
        batch_resource.add_method(
            "POST",
            apigw.LambdaIntegration(
                self.batch_processor,
                proxy=True,
                integration_responses=[
                    apigw.IntegrationResponse(
                        status_code="200",
                        response_headers={
                            "Access-Control-Allow-Origin": "'*'",
                            "Access-Control-Allow-Methods": "'POST,OPTIONS'",
                        }
                    )
                ]
            ),
            method_responses=[
                apigw.MethodResponse(
                    status_code="200",
                    response_headers={
                        "Access-Control-Allow-Origin": True,
                        "Access-Control-Allow-Methods": True,
                    }
                )
            ]
        )
        
        # Create /realtime endpoint for quick synthesis
        realtime_resource = api.root.add_resource("realtime")
        realtime_resource.add_method(
            "POST",
            apigw.LambdaIntegration(
                self.realtime_processor,
                proxy=True,
                integration_responses=[
                    apigw.IntegrationResponse(
                        status_code="200",
                        response_headers={
                            "Access-Control-Allow-Origin": "'*'",
                            "Access-Control-Allow-Methods": "'POST,OPTIONS'",
                        }
                    )
                ]
            ),
            method_responses=[
                apigw.MethodResponse(
                    status_code="200",
                    response_headers={
                        "Access-Control-Allow-Origin": True,
                        "Access-Control-Allow-Methods": True,
                    }
                )
            ]
        )
        
        # Create /voices endpoint for voice discovery
        voices_resource = api.root.add_resource("voices")
        voices_resource.add_method(
            "GET",
            apigw.AwsIntegration(
                service="polly",
                action="DescribeVoices",
                options=apigw.IntegrationOptions(
                    credentials_role=self.lambda_role,
                    integration_responses=[
                        apigw.IntegrationResponse(
                            status_code="200",
                            response_headers={
                                "Access-Control-Allow-Origin": "'*'",
                            }
                        )
                    ]
                )
            ),
            method_responses=[
                apigw.MethodResponse(
                    status_code="200",
                    response_headers={
                        "Access-Control-Allow-Origin": True,
                    }
                )
            ]
        )
        
        return api
    
    def _create_scheduled_processing(self) -> None:
        """Create EventBridge rule for scheduled batch processing"""
        # Create rule for daily cleanup of old audio files
        cleanup_rule = events.Rule(
            self, "DailyCleanupRule",
            schedule=events.Schedule.cron(hour="2", minute="0"),  # 2 AM UTC daily
            description="Daily cleanup of old audio files",
        )
        
        # Add Lambda target with custom payload
        cleanup_rule.add_target(
            targets.LambdaFunction(
                self.batch_processor,
                event=events.RuleTargetInput.from_object({
                    "action": "cleanup",
                    "retention_days": 7,
                    "bucket_name": self.audio_bucket.bucket_name
                })
            )
        )
    
    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources"""
        CfnOutput(
            self, "AudioBucketName",
            value=self.audio_bucket.bucket_name,
            description="S3 bucket for audio storage",
            export_name=f"{self.stack_name}-AudioBucketName"
        )
        
        CfnOutput(
            self, "CloudFrontURL",
            value=f"https://{self.cdn_distribution.distribution_domain_name}",
            description="CloudFront URL for audio delivery",
            export_name=f"{self.stack_name}-CloudFrontURL"
        )
        
        CfnOutput(
            self, "APIGatewayURL",
            value=self.api_gateway.url,
            description="API Gateway URL for text-to-speech endpoints",
            export_name=f"{self.stack_name}-APIGatewayURL"
        )
        
        CfnOutput(
            self, "BatchProcessorFunction",
            value=self.batch_processor.function_name,
            description="Lambda function for batch processing",
            export_name=f"{self.stack_name}-BatchProcessorFunction"
        )
        
        CfnOutput(
            self, "RealtimeProcessorFunction",
            value=self.realtime_processor.function_name,
            description="Lambda function for real-time processing",
            export_name=f"{self.stack_name}-RealtimeProcessorFunction"
        )


# CDK App
app = cdk.App()

# Get stack name from context or use default
stack_name = app.node.try_get_context("stack_name") or "TextToSpeechPollyStack"

# Create the stack
TextToSpeechPollyStack(
    app, 
    stack_name,
    description="Text-to-Speech Solutions with Amazon Polly - CDK Python Implementation",
    env=cdk.Environment(
        account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
        region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
    ),
    tags={
        "Project": "TextToSpeechSolutions",
        "Stack": "PollyTTS",
        "Environment": app.node.try_get_context("environment") or "dev",
        "Owner": "CDK",
        "CostCenter": app.node.try_get_context("cost_center") or "engineering"
    }
)

app.synth()