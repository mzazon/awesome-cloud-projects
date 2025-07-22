#!/usr/bin/env python3

"""
AWS CDK Python Application for Multi-Language Voice Processing Pipeline

This application deploys a comprehensive voice processing solution that:
- Detects languages in audio files using Amazon Transcribe
- Transcribes speech to text with custom vocabularies
- Translates text content using Amazon Translate
- Synthesizes speech in multiple languages using Amazon Polly
- Orchestrates the entire pipeline using AWS Step Functions

The architecture includes:
- S3 buckets for input/output storage
- Lambda functions for each processing stage
- Step Functions workflow for orchestration
- DynamoDB table for job tracking
- IAM roles with least privilege permissions
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    aws_s3 as s3,
    aws_dynamodb as dynamodb,
    aws_lambda as _lambda,
    aws_stepfunctions as sfn,
    aws_stepfunctions_tasks as sfn_tasks,
    aws_iam as iam,
    aws_logs as logs,
    aws_s3_notifications as s3n,
    aws_cloudwatch as cloudwatch,
    aws_sns as sns,
    CfnOutput,
)
from constructs import Construct
from typing import Dict, List


class MultiLanguageVoiceProcessingStack(Stack):
    """
    CDK Stack for Multi-Language Voice Processing Pipeline
    
    This stack creates a complete voice processing solution using AWS AI services:
    - Amazon Transcribe for speech-to-text conversion
    - Amazon Translate for language translation
    - Amazon Polly for text-to-speech synthesis
    - AWS Step Functions for workflow orchestration
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Stack parameters
        self.project_name = "voice-pipeline"
        self.supported_languages = ["en", "es", "fr", "de", "it", "pt", "ja", "ko", "zh", "ar", "hi", "ru", "nl", "sv"]
        
        # Create storage infrastructure
        self._create_storage_resources()
        
        # Create processing table
        self._create_dynamodb_table()
        
        # Create IAM roles
        self._create_iam_roles()
        
        # Create Lambda functions
        self._create_lambda_functions()
        
        # Create Step Functions workflow
        self._create_step_functions_workflow()
        
        # Create monitoring and notifications
        self._create_monitoring_resources()
        
        # Create outputs
        self._create_outputs()

    def _create_storage_resources(self) -> None:
        """Create S3 buckets for input and output storage"""
        
        # Input bucket for audio files
        self.input_bucket = s3.Bucket(
            self, "InputBucket",
            bucket_name=f"{self.project_name}-input-{self.account}",
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            versioning=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteOldVersions",
                    enabled=True,
                    noncurrent_version_expiration=Duration.days(30)
                )
            ],
            cors=[
                s3.CorsRule(
                    allowed_methods=[s3.HttpMethods.GET, s3.HttpMethods.POST, s3.HttpMethods.PUT],
                    allowed_origins=["*"],
                    allowed_headers=["*"],
                    max_age=3000
                )
            ]
        )
        
        # Output bucket for processed files
        self.output_bucket = s3.Bucket(
            self, "OutputBucket",
            bucket_name=f"{self.project_name}-output-{self.account}",
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="ArchiveOldObjects",
                    enabled=True,
                    expiration=Duration.days(90),
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30)
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(60)
                        )
                    ]
                )
            ]
        )

    def _create_dynamodb_table(self) -> None:
        """Create DynamoDB table for job tracking"""
        
        self.jobs_table = dynamodb.Table(
            self, "JobsTable",
            table_name=f"{self.project_name}-jobs",
            partition_key=dynamodb.Attribute(
                name="JobId",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            removal_policy=RemovalPolicy.DESTROY,
            encryption=dynamodb.TableEncryption.AWS_MANAGED,
            point_in_time_recovery=True,
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES
        )
        
        # Add GSI for status queries
        self.jobs_table.add_global_secondary_index(
            index_name="StatusIndex",
            partition_key=dynamodb.Attribute(
                name="Status",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="Timestamp",
                type=dynamodb.AttributeType.NUMBER
            ),
            projection_type=dynamodb.ProjectionType.ALL
        )

    def _create_iam_roles(self) -> None:
        """Create IAM roles with least privilege permissions"""
        
        # Role for Lambda functions
        self.lambda_role = iam.Role(
            self, "LambdaExecutionRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole")
            ]
        )
        
        # Add permissions for AWS services
        self.lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "transcribe:StartTranscriptionJob",
                    "transcribe:GetTranscriptionJob",
                    "transcribe:ListTranscriptionJobs",
                    "transcribe:GetVocabulary",
                    "transcribe:CreateVocabulary"
                ],
                resources=["*"]
            )
        )
        
        self.lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "translate:TranslateText",
                    "translate:GetTerminology",
                    "translate:CreateTerminology"
                ],
                resources=["*"]
            )
        )
        
        self.lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "polly:SynthesizeSpeech",
                    "polly:DescribeVoices",
                    "polly:GetSpeechSynthesisTask",
                    "polly:StartSpeechSynthesisTask"
                ],
                resources=["*"]
            )
        )
        
        # Add S3 permissions
        self.lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:PutObject",
                    "s3:DeleteObject"
                ],
                resources=[
                    self.input_bucket.bucket_arn,
                    f"{self.input_bucket.bucket_arn}/*",
                    self.output_bucket.bucket_arn,
                    f"{self.output_bucket.bucket_arn}/*"
                ]
            )
        )
        
        # Add DynamoDB permissions
        self.lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "dynamodb:GetItem",
                    "dynamodb:PutItem",
                    "dynamodb:UpdateItem",
                    "dynamodb:Query",
                    "dynamodb:Scan"
                ],
                resources=[
                    self.jobs_table.table_arn,
                    f"{self.jobs_table.table_arn}/index/*"
                ]
            )
        )
        
        # Role for Step Functions
        self.step_functions_role = iam.Role(
            self, "StepFunctionsRole",
            assumed_by=iam.ServicePrincipal("states.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSStepFunctionsBasicExecutionRole")
            ]
        )
        
        # Add Lambda invoke permissions
        self.step_functions_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["lambda:InvokeFunction"],
                resources=[f"arn:aws:lambda:{self.region}:{self.account}:function:{self.project_name}-*"]
            )
        )

    def _create_lambda_functions(self) -> None:
        """Create Lambda functions for each processing stage"""
        
        # Common Lambda configuration
        lambda_config = {
            "runtime": _lambda.Runtime.PYTHON_3_9,
            "role": self.lambda_role,
            "timeout": Duration.minutes(5),
            "memory_size": 512,
            "environment": {
                "JOBS_TABLE": self.jobs_table.table_name,
                "INPUT_BUCKET": self.input_bucket.bucket_name,
                "OUTPUT_BUCKET": self.output_bucket.bucket_name
            },
            "log_retention": logs.RetentionDays.ONE_WEEK
        }
        
        # Language Detection Lambda
        self.language_detector = _lambda.Function(
            self, "LanguageDetector",
            function_name=f"{self.project_name}-language-detector",
            handler="language_detector.lambda_handler",
            code=_lambda.Code.from_inline(self._get_language_detector_code()),
            **lambda_config
        )
        
        # Transcription Processor Lambda
        self.transcription_processor = _lambda.Function(
            self, "TranscriptionProcessor",
            function_name=f"{self.project_name}-transcription-processor",
            handler="transcription_processor.lambda_handler",
            code=_lambda.Code.from_inline(self._get_transcription_processor_code()),
            **lambda_config
        )
        
        # Translation Processor Lambda
        self.translation_processor = _lambda.Function(
            self, "TranslationProcessor",
            function_name=f"{self.project_name}-translation-processor",
            handler="translation_processor.lambda_handler",
            code=_lambda.Code.from_inline(self._get_translation_processor_code()),
            timeout=Duration.minutes(10),
            **{k: v for k, v in lambda_config.items() if k != "timeout"}
        )
        
        # Speech Synthesizer Lambda
        self.speech_synthesizer = _lambda.Function(
            self, "SpeechSynthesizer",
            function_name=f"{self.project_name}-speech-synthesizer",
            handler="speech_synthesizer.lambda_handler",
            code=_lambda.Code.from_inline(self._get_speech_synthesizer_code()),
            timeout=Duration.minutes(10),
            **{k: v for k, v in lambda_config.items() if k != "timeout"}
        )
        
        # Job Status Checker Lambda
        self.job_status_checker = _lambda.Function(
            self, "JobStatusChecker",
            function_name=f"{self.project_name}-job-status-checker",
            handler="job_status_checker.lambda_handler",
            code=_lambda.Code.from_inline(self._get_job_status_checker_code()),
            timeout=Duration.seconds(30),
            **{k: v for k, v in lambda_config.items() if k != "timeout"}
        )

    def _create_step_functions_workflow(self) -> None:
        """Create Step Functions workflow for orchestrating the pipeline"""
        
        # Define Step Functions tasks
        initialize_job = sfn.Pass(
            self, "InitializeJob",
            comment="Initialize job parameters",
            parameters={
                "bucket.$": "$.bucket",
                "key.$": "$.key",
                "job_id.$": "$.job_id",
                "jobs_table": self.jobs_table.table_name,
                "target_languages.$": "$.target_languages"
            }
        )
        
        # Language Detection Task
        detect_language = sfn_tasks.LambdaInvoke(
            self, "DetectLanguage",
            lambda_function=self.language_detector,
            result_path="$.language_detection_result"
        )
        
        # Wait for Language Detection
        wait_for_language_detection = sfn.Wait(
            self, "WaitForLanguageDetection",
            time=sfn.WaitTime.duration(Duration.seconds(30))
        )
        
        # Check Language Detection Status
        check_language_detection_status = sfn_tasks.LambdaInvoke(
            self, "CheckLanguageDetectionStatus",
            lambda_function=self.job_status_checker,
            payload=sfn.TaskInput.from_object({
                "transcribe_job_name.$": "$.language_detection_result.Payload.transcribe_job_name",
                "job_type": "language_detection"
            }),
            result_path="$.language_status"
        )
        
        # Language Detection Complete Choice
        is_language_detection_complete = sfn.Choice(
            self, "IsLanguageDetectionComplete"
        )
        
        # Transcription Task
        process_transcription = sfn_tasks.LambdaInvoke(
            self, "ProcessTranscription",
            lambda_function=self.transcription_processor,
            payload=sfn.TaskInput.from_object({
                "job_id.$": "$.job_id",
                "bucket.$": "$.bucket",
                "key.$": "$.key",
                "detected_language.$": "$.language_status.Payload.detected_language",
                "jobs_table": self.jobs_table.table_name
            }),
            result_path="$.transcription_result"
        )
        
        # Wait for Transcription
        wait_for_transcription = sfn.Wait(
            self, "WaitForTranscription",
            time=sfn.WaitTime.duration(Duration.seconds(60))
        )
        
        # Check Transcription Status
        check_transcription_status = sfn_tasks.LambdaInvoke(
            self, "CheckTranscriptionStatus",
            lambda_function=self.job_status_checker,
            payload=sfn.TaskInput.from_object({
                "transcribe_job_name.$": "$.transcription_result.Payload.transcribe_job_name",
                "job_type": "transcription"
            }),
            result_path="$.transcription_status"
        )
        
        # Transcription Complete Choice
        is_transcription_complete = sfn.Choice(
            self, "IsTranscriptionComplete"
        )
        
        # Translation Task
        process_translation = sfn_tasks.LambdaInvoke(
            self, "ProcessTranslation",
            lambda_function=self.translation_processor,
            payload=sfn.TaskInput.from_object({
                "job_id.$": "$.job_id",
                "bucket.$": "$.bucket",
                "source_language.$": "$.transcription_status.Payload.source_language",
                "target_languages.$": "$.target_languages",
                "transcription_uri.$": "$.transcription_status.Payload.transcript_uri",
                "jobs_table": self.jobs_table.table_name
            }),
            result_path="$.translation_result"
        )
        
        # Speech Synthesis Task
        synthesize_speech = sfn_tasks.LambdaInvoke(
            self, "SynthesizeSpeech",
            lambda_function=self.speech_synthesizer,
            payload=sfn.TaskInput.from_object({
                "job_id.$": "$.job_id",
                "bucket.$": "$.bucket",
                "translations.$": "$.translation_result.Payload.translations",
                "jobs_table": self.jobs_table.table_name
            }),
            result_path="$.synthesis_result"
        )
        
        # Define workflow
        definition = (
            initialize_job
            .next(detect_language)
            .next(wait_for_language_detection)
            .next(check_language_detection_status)
            .next(is_language_detection_complete
                  .when(sfn.Condition.boolean_equals("$.language_status.Payload.is_complete", True),
                        process_transcription)
                  .otherwise(wait_for_language_detection))
            .next(wait_for_transcription)
            .next(check_transcription_status)
            .next(is_transcription_complete
                  .when(sfn.Condition.boolean_equals("$.transcription_status.Payload.is_complete", True),
                        process_translation)
                  .otherwise(wait_for_transcription))
            .next(synthesize_speech)
        )
        
        # Create State Machine
        self.state_machine = sfn.StateMachine(
            self, "VoiceProcessingStateMachine",
            state_machine_name=f"{self.project_name}-voice-processing",
            definition=definition,
            role=self.step_functions_role,
            timeout=Duration.hours(2),
            logs=sfn.LogOptions(
                destination=logs.LogGroup(
                    self, "StateMachineLogGroup",
                    log_group_name=f"/aws/stepfunctions/{self.project_name}-voice-processing",
                    retention=logs.RetentionDays.ONE_WEEK
                ),
                level=sfn.LogLevel.ALL
            )
        )

    def _create_monitoring_resources(self) -> None:
        """Create CloudWatch monitoring and SNS notifications"""
        
        # SNS Topic for notifications
        self.notification_topic = sns.Topic(
            self, "NotificationTopic",
            topic_name=f"{self.project_name}-notifications",
            display_name="Voice Processing Pipeline Notifications"
        )
        
        # CloudWatch Alarms
        self.state_machine.metric_failed().create_alarm(
            self, "StateMachineFailedAlarm",
            alarm_name=f"{self.project_name}-workflow-failures",
            alarm_description="Alarm when Step Functions workflow fails",
            threshold=1,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD
        )
        
        # Lambda error alarms
        for lambda_function in [self.language_detector, self.transcription_processor, 
                               self.translation_processor, self.speech_synthesizer]:
            lambda_function.metric_errors().create_alarm(
                self, f"{lambda_function.function_name}ErrorAlarm",
                alarm_name=f"{lambda_function.function_name}-errors",
                alarm_description=f"Alarm when {lambda_function.function_name} has errors",
                threshold=5,
                evaluation_periods=2,
                comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD
            )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs"""
        
        CfnOutput(
            self, "InputBucketName",
            value=self.input_bucket.bucket_name,
            description="S3 bucket for input audio files"
        )
        
        CfnOutput(
            self, "OutputBucketName",
            value=self.output_bucket.bucket_name,
            description="S3 bucket for processed audio files"
        )
        
        CfnOutput(
            self, "JobsTableName",
            value=self.jobs_table.table_name,
            description="DynamoDB table for job tracking"
        )
        
        CfnOutput(
            self, "StateMachineArn",
            value=self.state_machine.state_machine_arn,
            description="Step Functions state machine ARN"
        )
        
        CfnOutput(
            self, "NotificationTopicArn",
            value=self.notification_topic.topic_arn,
            description="SNS topic for notifications"
        )

    def _get_language_detector_code(self) -> str:
        """Return the Lambda function code for language detection"""
        return '''
import json
import boto3
import uuid
from datetime import datetime

transcribe = boto3.client('transcribe')
dynamodb = boto3.resource('dynamodb')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    bucket = event['bucket']
    key = event['key']
    job_id = event.get('job_id', str(uuid.uuid4()))
    
    table = dynamodb.Table(event['jobs_table'])
    
    try:
        # Update job status
        table.put_item(
            Item={
                'JobId': job_id,
                'Status': 'LANGUAGE_DETECTION',
                'InputFile': f"s3://{bucket}/{key}",
                'Timestamp': int(datetime.now().timestamp()),
                'Stage': 'language_detection'
            }
        )
        
        # Start language identification job
        job_name = f"lang-detect-{job_id}"
        
        transcribe.start_transcription_job(
            TranscriptionJobName=job_name,
            Media={'MediaFileUri': f"s3://{bucket}/{key}"},
            IdentifyLanguage=True,
            OutputBucketName=bucket,
            OutputKey=f"language-detection/{job_id}/"
        )
        
        return {
            'statusCode': 200,
            'job_id': job_id,
            'transcribe_job_name': job_name,
            'bucket': bucket,
            'key': key,
            'stage': 'language_detection'
        }
        
    except Exception as e:
        table.put_item(
            Item={
                'JobId': job_id,
                'Status': 'FAILED',
                'Error': str(e),
                'Timestamp': int(datetime.now().timestamp()),
                'Stage': 'language_detection'
            }
        )
        
        return {
            'statusCode': 500,
            'error': str(e),
            'job_id': job_id
        }
'''

    def _get_transcription_processor_code(self) -> str:
        """Return the Lambda function code for transcription processing"""
        return '''
import json
import boto3
import uuid
from datetime import datetime

transcribe = boto3.client('transcribe')
dynamodb = boto3.resource('dynamodb')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    job_id = event['job_id']
    bucket = event['bucket']
    key = event['key']
    detected_language = event.get('detected_language', 'en-US')
    
    table = dynamodb.Table(event['jobs_table'])
    
    try:
        # Update job status
        table.update_item(
            Key={'JobId': job_id},
            UpdateExpression='SET #status = :status, #stage = :stage, DetectedLanguage = :lang',
            ExpressionAttributeNames={'#status': 'Status', '#stage': 'Stage'},
            ExpressionAttributeValues={
                ':status': 'TRANSCRIBING',
                ':stage': 'transcription',
                ':lang': detected_language
            }
        )
        
        # Configure transcription based on language
        transcribe_config = {
            'TranscriptionJobName': f"transcribe-{job_id}",
            'Media': {'MediaFileUri': f"s3://{bucket}/{key}"},
            'OutputBucketName': bucket,
            'OutputKey': f"transcriptions/{job_id}/",
            'LanguageCode': detected_language
        }
        
        # Add language-specific settings
        if detected_language.startswith('en'):
            transcribe_config['Settings'] = {
                'ShowSpeakerLabels': True,
                'MaxSpeakerLabels': 10,
                'ShowAlternatives': True,
                'MaxAlternatives': 3
            }
        
        # Start transcription job
        transcribe.start_transcription_job(**transcribe_config)
        
        return {
            'statusCode': 200,
            'job_id': job_id,
            'transcribe_job_name': f"transcribe-{job_id}",
            'detected_language': detected_language,
            'bucket': bucket,
            'stage': 'transcription'
        }
        
    except Exception as e:
        table.update_item(
            Key={'JobId': job_id},
            UpdateExpression='SET #status = :status, #error = :error',
            ExpressionAttributeNames={'#status': 'Status'},
            ExpressionAttributeValues={
                ':status': 'FAILED',
                ':error': str(e)
            }
        )
        
        return {
            'statusCode': 500,
            'error': str(e),
            'job_id': job_id
        }
'''

    def _get_translation_processor_code(self) -> str:
        """Return the Lambda function code for translation processing"""
        return '''
import json
import boto3
from datetime import datetime

translate = boto3.client('translate')
dynamodb = boto3.resource('dynamodb')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    job_id = event['job_id']
    bucket = event['bucket']
    source_language = event['source_language']
    target_languages = event.get('target_languages', ['es', 'fr', 'de', 'pt'])
    transcription_uri = event['transcription_uri']
    
    table = dynamodb.Table(event['jobs_table'])
    
    try:
        # Update job status
        table.update_item(
            Key={'JobId': job_id},
            UpdateExpression='SET #status = :status, #stage = :stage',
            ExpressionAttributeNames={'#status': 'Status', '#stage': 'Stage'},
            ExpressionAttributeValues={
                ':status': 'TRANSLATING',
                ':stage': 'translation'
            }
        )
        
        # Parse S3 URI to get bucket and key
        transcription_key = transcription_uri.split('/', 3)[3]
        
        # Download transcription results
        transcription_obj = s3.get_object(Bucket=bucket, Key=transcription_key)
        transcription_data = json.loads(transcription_obj['Body'].read().decode('utf-8'))
        
        # Extract transcript text
        transcript = transcription_data['results']['transcripts'][0]['transcript']
        
        # Map language codes
        source_lang_code = map_transcribe_to_translate_language(source_language)
        
        translations = {}
        
        # Translate to each target language
        for target_lang in target_languages:
            if target_lang != source_lang_code:
                try:
                    translate_params = {
                        'Text': transcript,
                        'SourceLanguageCode': source_lang_code,
                        'TargetLanguageCode': target_lang
                    }
                    
                    result = translate.translate_text(**translate_params)
                    
                    translations[target_lang] = {
                        'translated_text': result['TranslatedText'],
                        'source_language': source_lang_code,
                        'target_language': target_lang
                    }
                    
                except Exception as e:
                    print(f"Translation failed for {target_lang}: {str(e)}")
                    translations[target_lang] = {
                        'error': str(e),
                        'source_language': source_lang_code,
                        'target_language': target_lang
                    }
        
        # Store translation results
        translations_key = f"translations/{job_id}/translations.json"
        s3.put_object(
            Bucket=bucket,
            Key=translations_key,
            Body=json.dumps({
                'original_text': transcript,
                'source_language': source_lang_code,
                'translations': translations,
                'timestamp': datetime.now().isoformat()
            }),
            ContentType='application/json'
        )
        
        return {
            'statusCode': 200,
            'job_id': job_id,
            'source_language': source_lang_code,
            'translations': translations,
            'translations_uri': translations_key,
            'stage': 'translation'
        }
        
    except Exception as e:
        table.update_item(
            Key={'JobId': job_id},
            UpdateExpression='SET #status = :status, #error = :error',
            ExpressionAttributeNames={'#status': 'Status'},
            ExpressionAttributeValues={
                ':status': 'FAILED',
                ':error': str(e)
            }
        )
        
        return {
            'statusCode': 500,
            'error': str(e),
            'job_id': job_id
        }

def map_transcribe_to_translate_language(transcribe_lang):
    # Map Transcribe language codes to Translate language codes
    mapping = {
        'en-US': 'en', 'en-GB': 'en', 'en-AU': 'en',
        'es-US': 'es', 'es-ES': 'es',
        'fr-FR': 'fr', 'fr-CA': 'fr',
        'de-DE': 'de', 'it-IT': 'it',
        'pt-BR': 'pt', 'pt-PT': 'pt',
        'ja-JP': 'ja', 'ko-KR': 'ko',
        'zh-CN': 'zh', 'zh-TW': 'zh-TW',
        'ar-AE': 'ar', 'ar-SA': 'ar',
        'hi-IN': 'hi', 'ru-RU': 'ru',
        'nl-NL': 'nl', 'sv-SE': 'sv'
    }
    return mapping.get(transcribe_lang, transcribe_lang.split('-')[0])
'''

    def _get_speech_synthesizer_code(self) -> str:
        """Return the Lambda function code for speech synthesis"""
        return '''
import json
import boto3
from datetime import datetime
import re

polly = boto3.client('polly')
dynamodb = boto3.resource('dynamodb')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    job_id = event['job_id']
    bucket = event['bucket']
    translations = event['translations']
    
    table = dynamodb.Table(event['jobs_table'])
    
    try:
        # Update job status
        table.update_item(
            Key={'JobId': job_id},
            UpdateExpression='SET #status = :status, #stage = :stage',
            ExpressionAttributeNames={'#status': 'Status', '#stage': 'Stage'},
            ExpressionAttributeValues={
                ':status': 'SYNTHESIZING',
                ':stage': 'speech_synthesis'
            }
        )
        
        audio_outputs = {}
        
        # Process each translation
        for target_lang, translation_data in translations.items():
            if 'translated_text' in translation_data:
                try:
                    # Select appropriate voice for language
                    voice_id = select_voice_for_language(target_lang)
                    
                    # Prepare text for synthesis
                    text_to_synthesize = prepare_text_for_synthesis(
                        translation_data['translated_text']
                    )
                    
                    # Synthesize speech
                    synthesis_response = polly.synthesize_speech(
                        Text=text_to_synthesize,
                        VoiceId=voice_id,
                        OutputFormat='mp3',
                        Engine='neural' if supports_neural_voice(voice_id) else 'standard',
                        TextType='ssml' if text_to_synthesize.startswith('<speak>') else 'text'
                    )
                    
                    # Save audio to S3
                    audio_key = f"audio-output/{job_id}/{target_lang}.mp3"
                    s3.put_object(
                        Bucket=bucket,
                        Key=audio_key,
                        Body=synthesis_response['AudioStream'].read(),
                        ContentType='audio/mpeg'
                    )
                    
                    audio_outputs[target_lang] = {
                        'audio_uri': f"s3://{bucket}/{audio_key}",
                        'voice_id': voice_id,
                        'text_length': len(translation_data['translated_text']),
                        'audio_format': 'mp3'
                    }
                    
                except Exception as e:
                    print(f"Speech synthesis failed for {target_lang}: {str(e)}")
                    audio_outputs[target_lang] = {
                        'error': str(e)
                    }
        
        # Update job with final results
        table.update_item(
            Key={'JobId': job_id},
            UpdateExpression='SET #status = :status, #stage = :stage, AudioOutputs = :outputs',
            ExpressionAttributeNames={'#status': 'Status', '#stage': 'Stage'},
            ExpressionAttributeValues={
                ':status': 'COMPLETED',
                ':stage': 'completed',
                ':outputs': audio_outputs
            }
        )
        
        return {
            'statusCode': 200,
            'job_id': job_id,
            'audio_outputs': audio_outputs,
            'stage': 'completed'
        }
        
    except Exception as e:
        table.update_item(
            Key={'JobId': job_id},
            UpdateExpression='SET #status = :status, #error = :error',
            ExpressionAttributeNames={'#status': 'Status'},
            ExpressionAttributeValues={
                ':status': 'FAILED',
                ':error': str(e)
            }
        )
        
        return {
            'statusCode': 500,
            'error': str(e),
            'job_id': job_id
        }

def select_voice_for_language(language_code):
    # Map language codes to appropriate Polly voices
    voice_mapping = {
        'en': 'Joanna',  # English - Neural voice
        'es': 'Lupe',    # Spanish - Neural voice
        'fr': 'Lea',     # French - Neural voice
        'de': 'Vicki',   # German - Neural voice
        'it': 'Bianca',  # Italian - Neural voice
        'pt': 'Camila',  # Portuguese - Neural voice
        'ja': 'Takumi',  # Japanese - Neural voice
        'ko': 'Seoyeon', # Korean - Standard voice
        'zh': 'Zhiyu',   # Chinese - Neural voice
        'ar': 'Zeina',   # Arabic - Standard voice
        'hi': 'Aditi',   # Hindi - Standard voice
        'ru': 'Tatyana', # Russian - Standard voice
        'nl': 'Lotte',   # Dutch - Standard voice
        'sv': 'Astrid'   # Swedish - Standard voice
    }
    return voice_mapping.get(language_code, 'Joanna')

def supports_neural_voice(voice_id):
    # Neural voices available in Polly
    neural_voices = [
        'Joanna', 'Matthew', 'Ivy', 'Justin', 'Kendra', 'Kimberly', 'Salli',
        'Joey', 'Lupe', 'Lucia', 'Lea', 'Vicki', 'Bianca', 'Camila',
        'Takumi', 'Zhiyu', 'Ruth', 'Stephen'
    ]
    return voice_id in neural_voices

def prepare_text_for_synthesis(text):
    # Add basic SSML for better speech quality
    if len(text) > 1000:
        # For longer texts, add pauses at sentence boundaries
        text = re.sub(r'\.(\s+)', r'.<break time="500ms"/>\1', text)
        text = re.sub(r'!(\s+)', r'!<break time="500ms"/>\1', text)
        text = re.sub(r'\?(\s+)', r'?<break time="500ms"/>\1', text)
        text = f'<speak>{text}</speak>'
    
    return text
'''

    def _get_job_status_checker_code(self) -> str:
        """Return the Lambda function code for job status checking"""
        return '''
import json
import boto3

transcribe = boto3.client('transcribe')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    job_name = event['transcribe_job_name']
    job_type = event.get('job_type', 'transcription')
    
    try:
        response = transcribe.get_transcription_job(
            TranscriptionJobName=job_name
        )
        
        job_status = response['TranscriptionJob']['TranscriptionJobStatus']
        
        result = {
            'statusCode': 200,
            'job_name': job_name,
            'job_status': job_status,
            'is_complete': job_status in ['COMPLETED', 'FAILED']
        }
        
        if job_status == 'COMPLETED':
            if job_type == 'language_detection':
                # Extract detected language
                language_code = response['TranscriptionJob'].get('LanguageCode')
                identified_languages = response['TranscriptionJob'].get('IdentifiedLanguageScore')
                
                result['detected_language'] = language_code
                result['language_confidence'] = identified_languages
            else:
                # Extract transcription results location
                transcript_uri = response['TranscriptionJob']['Transcript']['TranscriptFileUri']
                result['transcript_uri'] = transcript_uri
                
                # Extract detected language for transcription jobs
                language_code = response['TranscriptionJob'].get('LanguageCode')
                result['source_language'] = language_code
        
        elif job_status == 'FAILED':
            result['failure_reason'] = response['TranscriptionJob'].get('FailureReason', 'Unknown error')
        
        return result
        
    except Exception as e:
        return {
            'statusCode': 500,
            'error': str(e),
            'job_name': job_name
        }
'''


app = cdk.App()

# Create the stack
MultiLanguageVoiceProcessingStack(
    app, 
    "MultiLanguageVoiceProcessingStack",
    description="Multi-Language Voice Processing Pipeline with Transcribe, Translate, and Polly",
    env=cdk.Environment(
        account=app.node.try_get_context("account"),
        region=app.node.try_get_context("region")
    )
)

app.synth()