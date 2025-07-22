#!/usr/bin/env python3
"""
AWS CDK application for Audio Processing Pipelines with MediaConvert.

This application creates a complete serverless audio processing pipeline that:
- Accepts audio uploads to S3
- Automatically triggers MediaConvert jobs via Lambda
- Processes audio into multiple formats (MP3, AAC, FLAC)
- Provides monitoring and notifications
- Follows AWS security best practices

Author: AWS CDK Recipe Generator
Version: 1.0
"""

import os
from typing import Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    App,
    CfnOutput,
    Duration,
    RemovalPolicy,
    Stack,
    StackProps,
    Tags,
)
from aws_cdk import aws_cloudwatch as cloudwatch
from aws_cdk import aws_iam as iam
from aws_cdk import aws_lambda as lambda_
from aws_cdk import aws_logs as logs
from aws_cdk import aws_mediaconvert as mediaconvert
from aws_cdk import aws_s3 as s3
from aws_cdk import aws_s3_notifications as s3n
from aws_cdk import aws_sns as sns
from constructs import Construct


class AudioProcessingPipelineStack(Stack):
    """
    CDK Stack for AWS Elemental MediaConvert audio processing pipeline.
    
    Creates a complete serverless audio processing solution with:
    - S3 buckets for input/output
    - Lambda function for job orchestration
    - MediaConvert job templates and presets
    - CloudWatch monitoring dashboard
    - SNS notifications for job status
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        deployment_name: str = "audio-processing",
        supported_audio_formats: List[str] = None,
        enable_enhanced_audio: bool = True,
        **kwargs
    ) -> None:
        """
        Initialize the Audio Processing Pipeline Stack.
        
        Args:
            scope: CDK construct scope
            construct_id: Unique identifier for this stack
            deployment_name: Name prefix for all resources
            supported_audio_formats: List of supported audio file extensions
            enable_enhanced_audio: Whether to enable advanced audio processing
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)

        # Set default parameters
        self.deployment_name = deployment_name
        self.supported_audio_formats = supported_audio_formats or [
            ".mp3", ".wav", ".flac", ".m4a", ".aac"
        ]
        self.enable_enhanced_audio = enable_enhanced_audio

        # Create core infrastructure
        self._create_s3_buckets()
        self._create_sns_topic()
        self._create_iam_roles()
        self._create_lambda_function()
        self._create_mediaconvert_resources()
        self._create_monitoring_dashboard()
        self._create_outputs()

        # Add tags to all resources
        self._add_common_tags()

    def _create_s3_buckets(self) -> None:
        """Create S3 buckets for input and output audio files."""
        # Input bucket for raw audio files
        self.input_bucket = s3.Bucket(
            self,
            "AudioInputBucket",
            bucket_name=f"{self.deployment_name}-input-{self.account}-{self.region}",
            versioning=s3.BucketVersioning.ENABLED,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteIncompleteMultipartUploads",
                    abort_incomplete_multipart_upload_after=Duration.days(1),
                    enabled=True,
                )
            ],
        )

        # Output bucket for processed audio files
        self.output_bucket = s3.Bucket(
            self,
            "AudioOutputBucket",
            bucket_name=f"{self.deployment_name}-output-{self.account}-{self.region}",
            versioning=s3.BucketVersioning.ENABLED,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="TransitionToIA",
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
                    enabled=True,
                )
            ],
        )

    def _create_sns_topic(self) -> None:
        """Create SNS topic for job notifications."""
        self.notification_topic = sns.Topic(
            self,
            "AudioProcessingNotifications",
            topic_name=f"{self.deployment_name}-notifications",
            display_name="Audio Processing Pipeline Notifications",
        )

    def _create_iam_roles(self) -> None:
        """Create IAM roles for Lambda and MediaConvert services."""
        # Lambda execution role
        self.lambda_role = iam.Role(
            self,
            "AudioProcessingLambdaRole",
            role_name=f"{self.deployment_name}-lambda-role",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
        )

        # MediaConvert service role
        self.mediaconvert_role = iam.Role(
            self,
            "MediaConvertServiceRole",
            role_name=f"{self.deployment_name}-mediaconvert-role",
            assumed_by=iam.ServicePrincipal("mediaconvert.amazonaws.com"),
        )

        # Lambda permissions for MediaConvert
        self.lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "mediaconvert:CreateJob",
                    "mediaconvert:GetJob",
                    "mediaconvert:ListJobs",
                    "mediaconvert:DescribeEndpoints",
                ],
                resources=["*"],
            )
        )

        # Lambda permission to pass MediaConvert role
        self.lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["iam:PassRole"],
                resources=[self.mediaconvert_role.role_arn],
            )
        )

        # MediaConvert permissions for S3 and SNS
        self.mediaconvert_role.add_to_policy(
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

        self.mediaconvert_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["sns:Publish"],
                resources=[self.notification_topic.topic_arn],
            )
        )

    def _create_lambda_function(self) -> None:
        """Create Lambda function for MediaConvert job orchestration."""
        # Lambda function code
        lambda_code = '''
import json
import boto3
import os
from urllib.parse import unquote_plus
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Lambda handler for processing S3 audio upload events.
    
    Triggers MediaConvert jobs for supported audio formats.
    """
    try:
        # Initialize MediaConvert client
        mediaconvert = boto3.client('mediaconvert', 
            endpoint_url=os.environ['MEDIACONVERT_ENDPOINT'])
        
        # Process each S3 event record
        for record in event['Records']:
            bucket = record['s3']['bucket']['name']
            key = unquote_plus(record['s3']['object']['key'])
            
            logger.info(f"Processing file: {key} from bucket: {bucket}")
            
            # Validate audio file extension
            if not any(key.lower().endswith(ext) for ext in ['.mp3', '.wav', '.flac', '.m4a', '.aac']):
                logger.info(f"Skipping non-audio file: {key}")
                continue
            
            # Create MediaConvert job
            job_settings = {
                "JobTemplate": os.environ['JOB_TEMPLATE_ARN'],
                "Role": os.environ['MEDIACONVERT_ROLE_ARN'],
                "Settings": {
                    "Inputs": [
                        {
                            "FileInput": f"s3://{bucket}/{key}",
                            "AudioSelectors": {
                                "Audio Selector 1": {
                                    "Tracks": [1],
                                    "DefaultSelection": "DEFAULT"
                                }
                            }
                        }
                    ]
                },
                "StatusUpdateInterval": "SECONDS_60",
                "UserMetadata": {
                    "OriginalFile": key,
                    "SourceBucket": bucket
                }
            }
            
            # Submit MediaConvert job
            response = mediaconvert.create_job(**job_settings)
            job_id = response['Job']['Id']
            
            logger.info(f"Created MediaConvert job {job_id} for {key}")
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': f'Successfully started processing job {job_id}',
                    'jobId': job_id,
                    'sourceFile': key
                })
            }
            
    except Exception as e:
        logger.error(f"Error processing audio file: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }
'''

        # Create Lambda function
        self.processing_function = lambda_.Function(
            self,
            "AudioProcessingFunction",
            function_name=f"{self.deployment_name}-processor",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(lambda_code),
            role=self.lambda_role,
            timeout=Duration.minutes(5),
            memory_size=512,
            log_retention=logs.RetentionDays.ONE_WEEK,
            environment={
                "MEDIACONVERT_ENDPOINT": f"https://{mediaconvert.CfnJobTemplate.account_id}.mediaconvert.{self.region}.amazonaws.com",
                "MEDIACONVERT_ROLE_ARN": self.mediaconvert_role.role_arn,
                "OUTPUT_BUCKET": self.output_bucket.bucket_name,
            },
        )

        # Configure S3 event notifications
        for audio_format in self.supported_audio_formats:
            self.input_bucket.add_event_notification(
                s3.EventType.OBJECT_CREATED,
                s3n.LambdaDestination(self.processing_function),
                s3.NotificationKeyFilter(suffix=audio_format),
            )

    def _create_mediaconvert_resources(self) -> None:
        """Create MediaConvert job templates and presets."""
        # Job template for multi-format audio processing
        job_template_settings = {
            "OutputGroups": [
                {
                    "Name": "MP3_Output",
                    "OutputGroupSettings": {
                        "Type": "FILE_GROUP_SETTINGS",
                        "FileGroupSettings": {
                            "Destination": f"s3://{self.output_bucket.bucket_name}/mp3/"
                        },
                    },
                    "Outputs": [
                        {
                            "NameModifier": "_mp3",
                            "ContainerSettings": {"Container": "MP3"},
                            "AudioDescriptions": [
                                {
                                    "AudioTypeControl": "FOLLOW_INPUT",
                                    "CodecSettings": {
                                        "Codec": "MP3",
                                        "Mp3Settings": {
                                            "Bitrate": 128000,
                                            "Channels": 2,
                                            "RateControlMode": "CBR",
                                            "SampleRate": 44100,
                                        },
                                    },
                                }
                            ],
                        }
                    ],
                },
                {
                    "Name": "AAC_Output",
                    "OutputGroupSettings": {
                        "Type": "FILE_GROUP_SETTINGS",
                        "FileGroupSettings": {
                            "Destination": f"s3://{self.output_bucket.bucket_name}/aac/"
                        },
                    },
                    "Outputs": [
                        {
                            "NameModifier": "_aac",
                            "ContainerSettings": {"Container": "MP4"},
                            "AudioDescriptions": [
                                {
                                    "AudioTypeControl": "FOLLOW_INPUT",
                                    "CodecSettings": {
                                        "Codec": "AAC",
                                        "AacSettings": {
                                            "Bitrate": 128000,
                                            "CodingMode": "CODING_MODE_2_0",
                                            "SampleRate": 44100,
                                        },
                                    },
                                }
                            ],
                        }
                    ],
                },
                {
                    "Name": "FLAC_Output",
                    "OutputGroupSettings": {
                        "Type": "FILE_GROUP_SETTINGS",
                        "FileGroupSettings": {
                            "Destination": f"s3://{self.output_bucket.bucket_name}/flac/"
                        },
                    },
                    "Outputs": [
                        {
                            "NameModifier": "_flac",
                            "ContainerSettings": {"Container": "FLAC"},
                            "AudioDescriptions": [
                                {
                                    "AudioTypeControl": "FOLLOW_INPUT",
                                    "CodecSettings": {
                                        "Codec": "FLAC",
                                        "FlacSettings": {
                                            "Channels": 2,
                                            "SampleRate": 44100,
                                        },
                                    },
                                }
                            ],
                        }
                    ],
                },
            ],
            "Inputs": [
                {
                    "AudioSelectors": {
                        "Audio Selector 1": {
                            "Tracks": [1],
                            "DefaultSelection": "DEFAULT",
                        }
                    }
                }
            ],
        }

        # Create job template
        self.job_template = mediaconvert.CfnJobTemplate(
            self,
            "AudioProcessingJobTemplate",
            name=f"{self.deployment_name}-job-template",
            description="Job template for multi-format audio processing",
            settings_json=job_template_settings,
        )

        # Update Lambda environment with job template ARN
        self.processing_function.add_environment(
            "JOB_TEMPLATE_ARN", self.job_template.ref
        )

        # Enhanced audio preset (optional)
        if self.enable_enhanced_audio:
            enhanced_preset_settings = {
                "ContainerSettings": {"Container": "MP4"},
                "AudioDescriptions": [
                    {
                        "AudioTypeControl": "FOLLOW_INPUT",
                        "CodecSettings": {
                            "Codec": "AAC",
                            "AacSettings": {
                                "Bitrate": 192000,
                                "CodingMode": "CODING_MODE_2_0",
                                "SampleRate": 48000,
                                "Specification": "MPEG4",
                            },
                        },
                        "AudioNormalizationSettings": {
                            "Algorithm": "ITU_BS_1770_2",
                            "AlgorithmControl": "CORRECT_AUDIO",
                            "LoudnessLogging": "LOG",
                            "PeakCalculation": "TRUE_PEAK",
                            "TargetLkfs": -23.0,
                        },
                    }
                ],
            }

            self.enhanced_preset = mediaconvert.CfnPreset(
                self,
                "EnhancedAudioPreset",
                name=f"{self.deployment_name}-enhanced-preset",
                description="Enhanced audio preset with normalization",
                settings_json=enhanced_preset_settings,
            )

    def _create_monitoring_dashboard(self) -> None:
        """Create CloudWatch dashboard for monitoring."""
        # Create dashboard
        self.dashboard = cloudwatch.Dashboard(
            self,
            "AudioProcessingDashboard",
            dashboard_name=f"{self.deployment_name}-dashboard",
        )

        # MediaConvert metrics
        mediaconvert_jobs_completed = cloudwatch.Metric(
            namespace="AWS/MediaConvert",
            metric_name="JobsCompleted",
            statistic="Sum",
            period=Duration.minutes(5),
        )

        mediaconvert_jobs_errored = cloudwatch.Metric(
            namespace="AWS/MediaConvert",
            metric_name="JobsErrored",
            statistic="Sum",
            period=Duration.minutes(5),
        )

        mediaconvert_jobs_submitted = cloudwatch.Metric(
            namespace="AWS/MediaConvert",
            metric_name="JobsSubmitted",
            statistic="Sum",
            period=Duration.minutes(5),
        )

        # Lambda metrics
        lambda_invocations = self.processing_function.metric_invocations(
            period=Duration.minutes(5)
        )
        lambda_errors = self.processing_function.metric_errors(
            period=Duration.minutes(5)
        )
        lambda_duration = self.processing_function.metric_duration(
            period=Duration.minutes(5)
        )

        # Add widgets to dashboard
        self.dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="MediaConvert Jobs",
                left=[
                    mediaconvert_jobs_completed,
                    mediaconvert_jobs_errored,
                    mediaconvert_jobs_submitted,
                ],
                width=12,
                height=6,
            ),
            cloudwatch.GraphWidget(
                title="Lambda Function Metrics",
                left=[lambda_invocations, lambda_errors],
                right=[lambda_duration],
                width=12,
                height=6,
            ),
        )

        # Create alarms for monitoring
        self._create_alarms()

    def _create_alarms(self) -> None:
        """Create CloudWatch alarms for monitoring."""
        # Lambda error alarm
        lambda_error_alarm = cloudwatch.Alarm(
            self,
            "LambdaErrorAlarm",
            alarm_name=f"{self.deployment_name}-lambda-errors",
            metric=self.processing_function.metric_errors(
                period=Duration.minutes(5)
            ),
            threshold=1,
            evaluation_periods=2,
            alarm_description="Lambda function errors detected",
        )

        # Add SNS notification to alarm
        lambda_error_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.notification_topic)
        )

        # Lambda duration alarm
        lambda_duration_alarm = cloudwatch.Alarm(
            self,
            "LambdaDurationAlarm",
            alarm_name=f"{self.deployment_name}-lambda-duration",
            metric=self.processing_function.metric_duration(
                period=Duration.minutes(5)
            ),
            threshold=240000,  # 4 minutes in milliseconds
            evaluation_periods=2,
            alarm_description="Lambda function duration approaching timeout",
        )

        lambda_duration_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.notification_topic)
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs."""
        CfnOutput(
            self,
            "InputBucketName",
            value=self.input_bucket.bucket_name,
            description="S3 bucket for input audio files",
            export_name=f"{self.deployment_name}-input-bucket",
        )

        CfnOutput(
            self,
            "OutputBucketName",
            value=self.output_bucket.bucket_name,
            description="S3 bucket for processed audio files",
            export_name=f"{self.deployment_name}-output-bucket",
        )

        CfnOutput(
            self,
            "LambdaFunctionName",
            value=self.processing_function.function_name,
            description="Lambda function for audio processing",
            export_name=f"{self.deployment_name}-lambda-function",
        )

        CfnOutput(
            self,
            "MediaConvertRoleArn",
            value=self.mediaconvert_role.role_arn,
            description="IAM role for MediaConvert service",
            export_name=f"{self.deployment_name}-mediaconvert-role",
        )

        CfnOutput(
            self,
            "SNSTopicArn",
            value=self.notification_topic.topic_arn,
            description="SNS topic for notifications",
            export_name=f"{self.deployment_name}-notifications",
        )

        CfnOutput(
            self,
            "DashboardUrl",
            value=f"https://console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.dashboard.dashboard_name}",
            description="CloudWatch dashboard URL",
        )

    def _add_common_tags(self) -> None:
        """Add common tags to all resources in the stack."""
        Tags.of(self).add("Application", "AudioProcessingPipeline")
        Tags.of(self).add("Environment", "Production")
        Tags.of(self).add("ManagedBy", "AWS-CDK")
        Tags.of(self).add("CostCenter", "MediaProcessing")


# CDK App
app = App()

# Get deployment configuration from context or environment
deployment_name = app.node.try_get_context("deployment_name") or "audio-processing"
enable_enhanced_audio = app.node.try_get_context("enable_enhanced_audio") or True

# Create the stack
AudioProcessingPipelineStack(
    app,
    "AudioProcessingPipelineStack",
    deployment_name=deployment_name,
    enable_enhanced_audio=enable_enhanced_audio,
    description="Complete audio processing pipeline using AWS Elemental MediaConvert",
)

app.synth()