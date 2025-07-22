#!/usr/bin/env python3
"""
CDK Python application for video processing workflows with S3, Lambda, and MediaConvert.

This application creates an event-driven video processing pipeline that automatically
transcodes uploaded videos into multiple formats using AWS Elemental MediaConvert.
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    aws_s3 as s3,
    aws_lambda as lambda_,
    aws_iam as iam,
    aws_s3_notifications as s3n,
    aws_events as events,
    aws_events_targets as targets,
    aws_cloudfront as cloudfront,
    aws_cloudfront_origins as origins,
    aws_logs as logs,
    CfnOutput,
    Tags,
)
from constructs import Construct


class VideoProcessingStack(Stack):
    """
    CDK Stack for video processing workflows using S3, Lambda, and MediaConvert.
    
    This stack creates:
    - S3 buckets for source and processed videos
    - Lambda functions for video processing orchestration
    - IAM roles with least privilege access
    - EventBridge rules for job completion handling
    - CloudFront distribution for content delivery
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        **kwargs: Any
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Create S3 buckets for video storage
        self._create_s3_buckets()
        
        # Create IAM roles with appropriate permissions
        self._create_iam_roles()
        
        # Create Lambda functions for video processing
        self._create_lambda_functions()
        
        # Configure S3 event notifications
        self._configure_s3_notifications()
        
        # Create EventBridge rules for job completion
        self._create_eventbridge_rules()
        
        # Create CloudFront distribution for content delivery
        self._create_cloudfront_distribution()
        
        # Create CloudWatch log groups
        self._create_log_groups()
        
        # Add stack outputs
        self._create_outputs()

    def _create_s3_buckets(self) -> None:
        """Create S3 buckets for source and processed videos."""
        # Source bucket for video uploads
        self.source_bucket = s3.Bucket(
            self,
            "VideoSourceBucket",
            bucket_name=f"video-source-{self.account}-{self.region}",
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            versioned=False,
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            encryption=s3.BucketEncryption.S3_MANAGED,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteIncompleteMultipartUploads",
                    abort_incomplete_multipart_upload_after=Duration.days(1),
                    enabled=True,
                )
            ],
        )

        # Output bucket for processed videos
        self.output_bucket = s3.Bucket(
            self,
            "VideoOutputBucket",
            bucket_name=f"video-output-{self.account}-{self.region}",
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            versioned=False,
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            encryption=s3.BucketEncryption.S3_MANAGED,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="TransitionToIA",
                    enabled=True,
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
                )
            ],
        )

        # Add tags to buckets
        Tags.of(self.source_bucket).add("Purpose", "VideoProcessing")
        Tags.of(self.source_bucket).add("Type", "Source")
        Tags.of(self.output_bucket).add("Purpose", "VideoProcessing")
        Tags.of(self.output_bucket).add("Type", "Output")

    def _create_iam_roles(self) -> None:
        """Create IAM roles for MediaConvert and Lambda functions."""
        # MediaConvert service role
        self.mediaconvert_role = iam.Role(
            self,
            "MediaConvertRole",
            role_name=f"MediaConvertRole-{self.stack_name}",
            assumed_by=iam.ServicePrincipal("mediaconvert.amazonaws.com"),
            description="Role for MediaConvert to access S3 buckets",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonS3ReadOnlyAccess")
            ],
        )

        # Add S3 write permissions to MediaConvert role
        self.mediaconvert_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:PutObject",
                    "s3:PutObjectAcl",
                    "s3:GetObject",
                    "s3:GetObjectAcl",
                    "s3:ListBucket",
                ],
                resources=[
                    self.source_bucket.bucket_arn,
                    f"{self.source_bucket.bucket_arn}/*",
                    self.output_bucket.bucket_arn,
                    f"{self.output_bucket.bucket_arn}/*",
                ],
            )
        )

        # Lambda execution role for video processor
        self.lambda_role = iam.Role(
            self,
            "VideoProcessorLambdaRole",
            role_name=f"VideoProcessorLambdaRole-{self.stack_name}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Role for Lambda function to process videos",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
        )

        # Add MediaConvert permissions to Lambda role
        self.lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "mediaconvert:*",
                ],
                resources=["*"],
            )
        )

        # Add S3 permissions to Lambda role
        self.lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:GetObjectVersion",
                    "s3:PutObject",
                ],
                resources=[
                    f"{self.source_bucket.bucket_arn}/*",
                    f"{self.output_bucket.bucket_arn}/*",
                ],
            )
        )

        # Add IAM PassRole permission for MediaConvert
        self.lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["iam:PassRole"],
                resources=[self.mediaconvert_role.role_arn],
            )
        )

    def _create_lambda_functions(self) -> None:
        """Create Lambda functions for video processing orchestration."""
        # Video processor Lambda function
        self.video_processor_function = lambda_.Function(
            self,
            "VideoProcessorFunction",
            function_name=f"video-processor-{self.stack_name}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_video_processor_code()),
            timeout=Duration.seconds(60),
            memory_size=256,
            role=self.lambda_role,
            environment={
                "MEDIACONVERT_ROLE_ARN": self.mediaconvert_role.role_arn,
                "S3_OUTPUT_BUCKET": self.output_bucket.bucket_name,
                "AWS_REGION": self.region,
            },
            description="Processes video uploads and creates MediaConvert jobs",
        )

        # Job completion handler Lambda function
        self.completion_handler_function = lambda_.Function(
            self,
            "CompletionHandlerFunction",
            function_name=f"completion-handler-{self.stack_name}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_completion_handler_code()),
            timeout=Duration.seconds(30),
            memory_size=128,
            role=self.lambda_role,
            environment={
                "AWS_REGION": self.region,
            },
            description="Handles MediaConvert job completion notifications",
        )

    def _create_log_groups(self) -> None:
        """Create CloudWatch log groups for Lambda functions."""
        # Log group for video processor function
        logs.LogGroup(
            self,
            "VideoProcessorLogGroup",
            log_group_name=f"/aws/lambda/{self.video_processor_function.function_name}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )

        # Log group for completion handler function
        logs.LogGroup(
            self,
            "CompletionHandlerLogGroup",
            log_group_name=f"/aws/lambda/{self.completion_handler_function.function_name}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )

    def _configure_s3_notifications(self) -> None:
        """Configure S3 event notifications to trigger Lambda functions."""
        # Add S3 event notification for video uploads
        self.source_bucket.add_event_notification(
            s3.EventType.OBJECT_CREATED,
            s3n.LambdaDestination(self.video_processor_function),
            s3.NotificationKeyFilter(suffix=".mp4"),
        )

        # Also trigger for other common video formats
        for suffix in [".mov", ".avi", ".mkv", ".m4v"]:
            self.source_bucket.add_event_notification(
                s3.EventType.OBJECT_CREATED,
                s3n.LambdaDestination(self.video_processor_function),
                s3.NotificationKeyFilter(suffix=suffix),
            )

    def _create_eventbridge_rules(self) -> None:
        """Create EventBridge rules for MediaConvert job completion."""
        # EventBridge rule for MediaConvert job completion
        self.job_completion_rule = events.Rule(
            self,
            "MediaConvertJobCompletionRule",
            rule_name=f"MediaConvert-JobComplete-{self.stack_name}",
            description="Triggers when MediaConvert jobs complete",
            event_pattern=events.EventPattern(
                source=["aws.mediaconvert"],
                detail_type=["MediaConvert Job State Change"],
                detail={
                    "status": ["COMPLETE", "ERROR", "CANCELED"],
                },
            ),
        )

        # Add Lambda target to EventBridge rule
        self.job_completion_rule.add_target(
            targets.LambdaFunction(
                self.completion_handler_function,
                retry_attempts=3,
            )
        )

    def _create_cloudfront_distribution(self) -> None:
        """Create CloudFront distribution for content delivery."""
        # Origin Access Identity for S3 access
        origin_access_identity = cloudfront.OriginAccessIdentity(
            self,
            "VideoOriginAccessIdentity",
            comment=f"OAI for video output bucket {self.output_bucket.bucket_name}",
        )

        # Grant CloudFront access to the output bucket
        self.output_bucket.grant_read(origin_access_identity)

        # CloudFront distribution for video delivery
        self.cloudfront_distribution = cloudfront.Distribution(
            self,
            "VideoDistribution",
            comment="Video streaming distribution",
            default_behavior=cloudfront.BehaviorOptions(
                origin=origins.S3Origin(
                    self.output_bucket,
                    origin_access_identity=origin_access_identity,
                ),
                viewer_protocol_policy=cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
                allowed_methods=cloudfront.AllowedMethods.ALLOW_GET_HEAD,
                cached_methods=cloudfront.CachedMethods.CACHE_GET_HEAD,
                cache_policy=cloudfront.CachePolicy.CACHING_OPTIMIZED,
                compress=True,
            ),
            price_class=cloudfront.PriceClass.PRICE_CLASS_100,
            enabled=True,
            http_version=cloudfront.HttpVersion.HTTP2,
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        CfnOutput(
            self,
            "SourceBucketName",
            value=self.source_bucket.bucket_name,
            description="Name of the S3 bucket for video uploads",
        )

        CfnOutput(
            self,
            "OutputBucketName",
            value=self.output_bucket.bucket_name,
            description="Name of the S3 bucket for processed videos",
        )

        CfnOutput(
            self,
            "VideoProcessorFunctionName",
            value=self.video_processor_function.function_name,
            description="Name of the video processor Lambda function",
        )

        CfnOutput(
            self,
            "CompletionHandlerFunctionName",
            value=self.completion_handler_function.function_name,
            description="Name of the completion handler Lambda function",
        )

        CfnOutput(
            self,
            "MediaConvertRoleArn",
            value=self.mediaconvert_role.role_arn,
            description="ARN of the MediaConvert service role",
        )

        CfnOutput(
            self,
            "CloudFrontDistributionId",
            value=self.cloudfront_distribution.distribution_id,
            description="ID of the CloudFront distribution",
        )

        CfnOutput(
            self,
            "CloudFrontDomainName",
            value=self.cloudfront_distribution.distribution_domain_name,
            description="Domain name of the CloudFront distribution",
        )

        CfnOutput(
            self,
            "EventBridgeRuleName",
            value=self.job_completion_rule.rule_name,
            description="Name of the EventBridge rule for job completion",
        )

    def _get_video_processor_code(self) -> str:
        """Return the Lambda function code for video processing."""
        return '''
import json
import boto3
import urllib.parse
import os
from typing import Dict, Any

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda handler for processing video uploads and creating MediaConvert jobs.
    
    Args:
        event: S3 event notification
        context: Lambda context
        
    Returns:
        Response dictionary with status and message
    """
    print(f"Received event: {json.dumps(event)}")
    
    # Get MediaConvert endpoint
    mediaconvert_client = boto3.client('mediaconvert')
    endpoints = mediaconvert_client.describe_endpoints()
    mediaconvert_endpoint = endpoints['Endpoints'][0]['Url']
    
    # Initialize MediaConvert client with endpoint
    mediaconvert = boto3.client('mediaconvert', endpoint_url=mediaconvert_endpoint)
    
    # Process each S3 record
    for record in event['Records']:
        bucket = record['s3']['bucket']['name']
        key = urllib.parse.unquote_plus(record['s3']['object']['key'])
        
        print(f"Processing video: s3://{bucket}/{key}")
        
        # Skip if not a video file
        if not key.lower().endswith(('.mp4', '.mov', '.avi', '.mkv', '.m4v')):
            print(f"Skipping non-video file: {key}")
            continue
        
        # Extract filename without extension
        filename = key.split('/')[-1].split('.')[0]
        
        # Create MediaConvert job settings
        job_settings = {
            "Role": os.environ['MEDIACONVERT_ROLE_ARN'],
            "Settings": {
                "Inputs": [{
                    "AudioSelectors": {
                        "Audio Selector 1": {
                            "Offset": 0,
                            "DefaultSelection": "DEFAULT",
                            "ProgramSelection": 1
                        }
                    },
                    "VideoSelector": {
                        "ColorSpace": "FOLLOW"
                    },
                    "FilterEnable": "AUTO",
                    "PsiControl": "USE_PSI",
                    "FilterStrength": 0,
                    "DeblockFilter": "DISABLED",
                    "DenoiseFilter": "DISABLED",
                    "TimecodeSource": "EMBEDDED",
                    "FileInput": f"s3://{bucket}/{key}"
                }],
                "OutputGroups": [
                    {
                        "Name": "Apple HLS",
                        "OutputGroupSettings": {
                            "Type": "HLS_GROUP_SETTINGS",
                            "HlsGroupSettings": {
                                "ManifestDurationFormat": "INTEGER",
                                "Destination": f"s3://{os.environ['S3_OUTPUT_BUCKET']}/hls/{filename}/",
                                "TimedMetadataId3Frame": "PRIV",
                                "CodecSpecification": "RFC_4281",
                                "OutputSelection": "MANIFESTS_AND_SEGMENTS",
                                "ProgramDateTimePeriod": 600,
                                "MinSegmentLength": 0,
                                "DirectoryStructure": "SINGLE_DIRECTORY",
                                "ProgramDateTime": "EXCLUDE",
                                "SegmentLength": 10,
                                "ManifestCompression": "NONE",
                                "ClientCache": "ENABLED",
                                "AudioOnlyHeader": "INCLUDE"
                            }
                        },
                        "Outputs": [
                            {
                                "VideoDescription": {
                                    "ScalingBehavior": "DEFAULT",
                                    "TimecodeInsertion": "DISABLED",
                                    "AntiAlias": "ENABLED",
                                    "Sharpness": 50,
                                    "CodecSettings": {
                                        "Codec": "H_264",
                                        "H264Settings": {
                                            "InterlaceMode": "PROGRESSIVE",
                                            "NumberReferenceFrames": 3,
                                            "Syntax": "DEFAULT",
                                            "Softness": 0,
                                            "GopClosedCadence": 1,
                                            "GopSize": 90,
                                            "Slices": 1,
                                            "GopBReference": "DISABLED",
                                            "SlowPal": "DISABLED",
                                            "SpatialAdaptiveQuantization": "ENABLED",
                                            "TemporalAdaptiveQuantization": "ENABLED",
                                            "FlickerAdaptiveQuantization": "DISABLED",
                                            "EntropyEncoding": "CABAC",
                                            "Bitrate": 2000000,
                                            "FramerateControl": "SPECIFIED",
                                            "RateControlMode": "CBR",
                                            "CodecProfile": "MAIN",
                                            "Telecine": "NONE",
                                            "MinIInterval": 0,
                                            "AdaptiveQuantization": "HIGH",
                                            "CodecLevel": "AUTO",
                                            "FieldEncoding": "PAFF",
                                            "SceneChangeDetect": "ENABLED",
                                            "QualityTuningLevel": "SINGLE_PASS",
                                            "FramerateConversionAlgorithm": "DUPLICATE_DROP",
                                            "UnregisteredSeiTimecode": "DISABLED",
                                            "GopSizeUnits": "FRAMES",
                                            "ParControl": "SPECIFIED",
                                            "NumberBFramesBetweenReferenceFrames": 2,
                                            "RepeatPps": "DISABLED",
                                            "FramerateNumerator": 30,
                                            "FramerateDenominator": 1,
                                            "ParNumerator": 1,
                                            "ParDenominator": 1
                                        }
                                    },
                                    "AfdSignaling": "NONE",
                                    "DropFrameTimecode": "ENABLED",
                                    "RespondToAfd": "NONE",
                                    "ColorMetadata": "INSERT",
                                    "Width": 1280,
                                    "Height": 720
                                },
                                "AudioDescriptions": [
                                    {
                                        "AudioTypeControl": "FOLLOW_INPUT",
                                        "CodecSettings": {
                                            "Codec": "AAC",
                                            "AacSettings": {
                                                "AudioDescriptionBroadcasterMix": "NORMAL",
                                                "Bitrate": 96000,
                                                "RateControlMode": "CBR",
                                                "CodecProfile": "LC",
                                                "CodingMode": "CODING_MODE_2_0",
                                                "RawFormat": "NONE",
                                                "SampleRate": 48000,
                                                "Specification": "MPEG4"
                                            }
                                        },
                                        "AudioSourceName": "Audio Selector 1",
                                        "LanguageCodeControl": "FOLLOW_INPUT"
                                    }
                                ],
                                "OutputSettings": {
                                    "HlsSettings": {
                                        "AudioGroupId": "program_audio",
                                        "AudioTrackType": "ALTERNATE_AUDIO_AUTO_SELECT_DEFAULT",
                                        "IFrameOnlyManifest": "EXCLUDE"
                                    }
                                },
                                "NameModifier": "_720p"
                            }
                        ]
                    },
                    {
                        "Name": "File Group",
                        "OutputGroupSettings": {
                            "Type": "FILE_GROUP_SETTINGS",
                            "FileGroupSettings": {
                                "Destination": f"s3://{os.environ['S3_OUTPUT_BUCKET']}/mp4/"
                            }
                        },
                        "Outputs": [
                            {
                                "VideoDescription": {
                                    "Width": 1280,
                                    "Height": 720,
                                    "CodecSettings": {
                                        "Codec": "H_264",
                                        "H264Settings": {
                                            "Bitrate": 2000000,
                                            "RateControlMode": "CBR",
                                            "CodecProfile": "MAIN",
                                            "GopSize": 90,
                                            "FramerateControl": "SPECIFIED",
                                            "FramerateNumerator": 30,
                                            "FramerateDenominator": 1
                                        }
                                    }
                                },
                                "AudioDescriptions": [
                                    {
                                        "CodecSettings": {
                                            "Codec": "AAC",
                                            "AacSettings": {
                                                "Bitrate": 96000,
                                                "SampleRate": 48000
                                            }
                                        },
                                        "AudioSourceName": "Audio Selector 1"
                                    }
                                ],
                                "ContainerSettings": {
                                    "Container": "MP4",
                                    "Mp4Settings": {
                                        "CslgAtom": "INCLUDE",
                                        "FreeSpaceBox": "EXCLUDE",
                                        "MoovPlacement": "PROGRESSIVE_DOWNLOAD"
                                    }
                                },
                                "NameModifier": "_720p"
                            }
                        ]
                    }
                ]
            }
        }
        
        # Create MediaConvert job
        try:
            response = mediaconvert.create_job(**job_settings)
            job_id = response['Job']['Id']
            print(f"Created MediaConvert job: {job_id} for {key}")
            
        except Exception as e:
            print(f"Error creating MediaConvert job: {str(e)}")
            raise
    
    return {
        'statusCode': 200,
        'body': json.dumps('Video processing initiated successfully')
    }
'''

    def _get_completion_handler_code(self) -> str:
        """Return the Lambda function code for job completion handling."""
        return '''
import json
import boto3
from typing import Dict, Any

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda handler for MediaConvert job completion notifications.
    
    Args:
        event: EventBridge event from MediaConvert
        context: Lambda context
        
    Returns:
        Response dictionary with status and message
    """
    print(f"MediaConvert job completion event: {json.dumps(event)}")
    
    # Extract job details
    job_id = event['detail']['jobId']
    status = event['detail']['status']
    
    print(f"Job {job_id} completed with status: {status}")
    
    # Handle different completion statuses
    if status == 'COMPLETE':
        print(f"Job {job_id} completed successfully")
        # Add custom logic for successful completion
        # Examples:
        # - Send SNS notification
        # - Update database records
        # - Trigger additional workflows
        
    elif status == 'ERROR':
        print(f"Job {job_id} failed with error")
        # Add custom logic for error handling
        # Examples:
        # - Send error notifications
        # - Log error details
        # - Trigger retry logic
        
    elif status == 'CANCELED':
        print(f"Job {job_id} was canceled")
        # Add custom logic for canceled jobs
        
    return {
        'statusCode': 200,
        'body': json.dumps('Job completion handled successfully')
    }
'''


class VideoProcessingApp(cdk.App):
    """CDK Application for video processing workflows."""

    def __init__(self) -> None:
        super().__init__()

        # Create the video processing stack
        VideoProcessingStack(
            self,
            "VideoProcessingStack",
            description="Video processing workflows with S3, Lambda, and MediaConvert",
            env=cdk.Environment(
                account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
                region=os.environ.get("CDK_DEFAULT_REGION"),
            ),
        )


# Create and run the CDK application
app = VideoProcessingApp()
app.synth()