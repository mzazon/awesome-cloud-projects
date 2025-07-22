#!/usr/bin/env python3

"""
AWS CDK Application for Adaptive Bitrate Streaming with MediaConvert and CloudFront

This CDK application creates a complete adaptive bitrate streaming solution including:
- S3 buckets for source and output video storage
- Lambda function for video processing automation
- MediaConvert job template for ABR transcoding
- CloudFront distribution for global content delivery
- IAM roles and policies with least privilege access

Author: AWS CDK Generator
Version: 1.0.0
CDK Version: 2.x
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    Tags,
    RemovalPolicy,
    Duration,
    aws_s3 as s3,
    aws_s3_notifications as s3n,
    aws_lambda as lambda_,
    aws_iam as iam,
    aws_cloudfront as cloudfront,
    aws_cloudfront_origins as origins,
    aws_mediaconvert as mediaconvert,
    aws_logs as logs,
    CfnOutput
)
from constructs import Construct
import json
from typing import Dict, Any, List


class AdaptiveBitrateStreamingStack(Stack):
    """
    CDK Stack for Adaptive Bitrate Streaming Infrastructure
    
    This stack deploys a complete video streaming solution with:
    - Automated video processing pipeline
    - Multi-bitrate transcoding with MediaConvert
    - Global content delivery with CloudFront
    - Secure IAM role configuration
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Stack configuration
        self.random_suffix = cdk.Fn.select(2, cdk.Fn.split('-', cdk.Fn.select(0, cdk.Fn.split('/', cdk.Aws.STACK_ID))))

        # Create S3 buckets for video storage
        self._create_storage_buckets()
        
        # Create IAM roles for MediaConvert and Lambda
        self._create_iam_roles()
        
        # Create MediaConvert job template
        self._create_mediaconvert_template()
        
        # Create Lambda function for video processing
        self._create_lambda_function()
        
        # Configure S3 event notifications
        self._configure_s3_events()
        
        # Create CloudFront distribution
        self._create_cloudfront_distribution()
        
        # Create outputs for reference
        self._create_outputs()

    def _create_storage_buckets(self) -> None:
        """Create S3 buckets for source videos and processed outputs"""
        
        # Source bucket for video uploads
        self.source_bucket = s3.Bucket(
            self, "VideoSourceBucket",
            bucket_name=f"video-source-{self.random_suffix}",
            versioned=False,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            encryption=s3.BucketEncryption.S3_MANAGED,
            event_bridge_enabled=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteIncompleteMultipartUploads",
                    abort_incomplete_multipart_upload_after=Duration.days(1),
                    enabled=True
                )
            ]
        )

        # Output bucket for processed ABR streams
        self.output_bucket = s3.Bucket(
            self, "VideoOutputBucket",
            bucket_name=f"video-abr-output-{self.random_suffix}",
            versioned=False,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            encryption=s3.BucketEncryption.S3_MANAGED,
            cors=[
                s3.CorsRule(
                    allowed_origins=["*"],
                    allowed_headers=["*"],
                    allowed_methods=[s3.HttpMethods.GET, s3.HttpMethods.HEAD],
                    max_age=3000
                )
            ],
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="TransitionToIA",
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30)
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(90)
                        )
                    ],
                    enabled=True
                )
            ]
        )

        # Add tags for cost tracking
        Tags.of(self.source_bucket).add("Purpose", "VideoSource")
        Tags.of(self.source_bucket).add("Environment", "Production")
        Tags.of(self.output_bucket).add("Purpose", "VideoOutput")
        Tags.of(self.output_bucket).add("Environment", "Production")

    def _create_iam_roles(self) -> None:
        """Create IAM roles for MediaConvert and Lambda services"""
        
        # MediaConvert service role
        self.mediaconvert_role = iam.Role(
            self, "MediaConvertServiceRole",
            role_name=f"MediaConvertABRRole-{self.random_suffix}",
            assumed_by=iam.ServicePrincipal("mediaconvert.amazonaws.com"),
            description="Role for MediaConvert to access S3 buckets for ABR transcoding",
            inline_policies={
                "S3AccessPolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:GetObject",
                                "s3:PutObject",
                                "s3:DeleteObject",
                                "s3:ListBucket",
                                "s3:GetBucketLocation"
                            ],
                            resources=[
                                self.source_bucket.bucket_arn,
                                f"{self.source_bucket.bucket_arn}/*",
                                self.output_bucket.bucket_arn,
                                f"{self.output_bucket.bucket_arn}/*"
                            ]
                        )
                    ]
                )
            }
        )

        # Lambda execution role
        self.lambda_role = iam.Role(
            self, "LambdaExecutionRole",
            role_name=f"VideoABRProcessorRole-{self.random_suffix}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Role for Lambda function to trigger MediaConvert jobs",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole")
            ],
            inline_policies={
                "MediaConvertAccessPolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "mediaconvert:CreateJob",
                                "mediaconvert:GetJob",
                                "mediaconvert:ListJobs",
                                "mediaconvert:GetJobTemplate"
                            ],
                            resources=["*"]
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=["iam:PassRole"],
                            resources=[self.mediaconvert_role.role_arn]
                        )
                    ]
                )
            }
        )

    def _create_mediaconvert_template(self) -> None:
        """Create MediaConvert job template for ABR transcoding"""
        
        # Job template configuration for adaptive bitrate streaming
        job_template_settings = {
            "OutputGroups": [
                {
                    "Name": "HLS_ABR_Package",
                    "OutputGroupSettings": {
                        "Type": "HLS_GROUP_SETTINGS",
                        "HlsGroupSettings": {
                            "Destination": f"s3://{self.output_bucket.bucket_name}/hls/",
                            "HlsCdnSettings": {
                                "HlsBasicPutSettings": {
                                    "ConnectionRetryInterval": 1,
                                    "FilecacheDuration": 300,
                                    "NumRetries": 10
                                }
                            },
                            "ManifestDurationFormat": "FLOATING_POINT",
                            "OutputSelection": "MANIFESTS_AND_SEGMENTS",
                            "SegmentControl": "SEGMENTED_FILES",
                            "SegmentLength": 6,
                            "TimedMetadataId3Frame": "PRIV",
                            "TimedMetadataId3Period": 10,
                            "MinSegmentLength": 0,
                            "DirectoryStructure": "SINGLE_DIRECTORY"
                        }
                    },
                    "Outputs": self._get_hls_outputs()
                },
                {
                    "Name": "DASH_ABR_Package",
                    "OutputGroupSettings": {
                        "Type": "DASH_ISO_GROUP_SETTINGS",
                        "DashIsoGroupSettings": {
                            "Destination": f"s3://{self.output_bucket.bucket_name}/dash/",
                            "FragmentLength": 2,
                            "SegmentControl": "SEGMENTED_FILES",
                            "SegmentLength": 30,
                            "MpdProfile": "ON_DEMAND_PROFILE",
                            "HbbtvCompliance": "NONE"
                        }
                    },
                    "Outputs": self._get_dash_outputs()
                },
                {
                    "Name": "Thumbnail_Output",
                    "OutputGroupSettings": {
                        "Type": "FILE_GROUP_SETTINGS",
                        "FileGroupSettings": {
                            "Destination": f"s3://{self.output_bucket.bucket_name}/thumbnails/"
                        }
                    },
                    "Outputs": self._get_thumbnail_outputs()
                }
            ],
            "Inputs": [
                {
                    "AudioSelectors": {
                        "Audio Selector 1": {
                            "Tracks": [1],
                            "DefaultSelection": "DEFAULT"
                        }
                    },
                    "VideoSelector": {
                        "ColorSpace": "FOLLOW"
                    },
                    "TimecodeSource": "EMBEDDED"
                }
            ]
        }

        # Create MediaConvert job template
        self.job_template = mediaconvert.CfnJobTemplate(
            self, "ABRJobTemplate",
            name=f"ABRStreamingTemplate-{self.random_suffix}",
            description="Adaptive bitrate streaming template with HLS and DASH outputs",
            settings_json=job_template_settings
        )

    def _get_hls_outputs(self) -> List[Dict[str, Any]]:
        """Generate HLS output configurations for different quality levels"""
        return [
            {
                "NameModifier": "_1080p",
                "ContainerSettings": {
                    "Container": "M3U8",
                    "M3u8Settings": {
                        "PcrControl": "PCR_EVERY_PES_PACKET",
                        "PmtPid": 480,
                        "PrivateMetadataPid": 503,
                        "ProgramNumber": 1,
                        "PatInterval": 0,
                        "PmtInterval": 0,
                        "VideoPid": 481,
                        "AudioPids": [482, 483, 484, 485, 486, 487, 488, 489, 490, 491, 492]
                    }
                },
                "VideoDescription": {
                    "Width": 1920,
                    "Height": 1080,
                    "CodecSettings": {
                        "Codec": "H_264",
                        "H264Settings": {
                            "RateControlMode": "QVBR",
                            "QvbrSettings": {"QvbrQualityLevel": 8},
                            "MaxBitrate": 5000000,
                            "FramerateControl": "INITIALIZE_FROM_SOURCE",
                            "GopClosedCadence": 1,
                            "GopSize": 90,
                            "GopSizeUnits": "FRAMES",
                            "ParControl": "INITIALIZE_FROM_SOURCE",
                            "QualityTuningLevel": "SINGLE_PASS",
                            "SceneChangeDetect": "ENABLED"
                        }
                    }
                },
                "AudioDescriptions": [
                    {
                        "AudioTypeControl": "FOLLOW_INPUT",
                        "CodecSettings": {
                            "Codec": "AAC",
                            "AacSettings": {
                                "Bitrate": 128000,
                                "CodingMode": "CODING_MODE_2_0",
                                "SampleRate": 48000
                            }
                        }
                    }
                ]
            },
            {
                "NameModifier": "_720p",
                "ContainerSettings": {
                    "Container": "M3U8",
                    "M3u8Settings": {
                        "PcrControl": "PCR_EVERY_PES_PACKET",
                        "PmtPid": 480,
                        "PrivateMetadataPid": 503,
                        "ProgramNumber": 1,
                        "PatInterval": 0,
                        "PmtInterval": 0,
                        "VideoPid": 481,
                        "AudioPids": [482, 483, 484, 485, 486, 487, 488, 489, 490, 491, 492]
                    }
                },
                "VideoDescription": {
                    "Width": 1280,
                    "Height": 720,
                    "CodecSettings": {
                        "Codec": "H_264",
                        "H264Settings": {
                            "RateControlMode": "QVBR",
                            "QvbrSettings": {"QvbrQualityLevel": 7},
                            "MaxBitrate": 3000000,
                            "FramerateControl": "INITIALIZE_FROM_SOURCE",
                            "GopClosedCadence": 1,
                            "GopSize": 90,
                            "GopSizeUnits": "FRAMES",
                            "ParControl": "INITIALIZE_FROM_SOURCE",
                            "QualityTuningLevel": "SINGLE_PASS",
                            "SceneChangeDetect": "ENABLED"
                        }
                    }
                },
                "AudioDescriptions": [
                    {
                        "AudioTypeControl": "FOLLOW_INPUT",
                        "CodecSettings": {
                            "Codec": "AAC",
                            "AacSettings": {
                                "Bitrate": 128000,
                                "CodingMode": "CODING_MODE_2_0",
                                "SampleRate": 48000
                            }
                        }
                    }
                ]
            },
            {
                "NameModifier": "_480p",
                "ContainerSettings": {
                    "Container": "M3U8",
                    "M3u8Settings": {
                        "PcrControl": "PCR_EVERY_PES_PACKET",
                        "PmtPid": 480,
                        "PrivateMetadataPid": 503,
                        "ProgramNumber": 1,
                        "PatInterval": 0,
                        "PmtInterval": 0,
                        "VideoPid": 481,
                        "AudioPids": [482, 483, 484, 485, 486, 487, 488, 489, 490, 491, 492]
                    }
                },
                "VideoDescription": {
                    "Width": 854,
                    "Height": 480,
                    "CodecSettings": {
                        "Codec": "H_264",
                        "H264Settings": {
                            "RateControlMode": "QVBR",
                            "QvbrSettings": {"QvbrQualityLevel": 6},
                            "MaxBitrate": 1500000,
                            "FramerateControl": "INITIALIZE_FROM_SOURCE",
                            "GopClosedCadence": 1,
                            "GopSize": 90,
                            "GopSizeUnits": "FRAMES",
                            "ParControl": "INITIALIZE_FROM_SOURCE",
                            "QualityTuningLevel": "SINGLE_PASS",
                            "SceneChangeDetect": "ENABLED"
                        }
                    }
                },
                "AudioDescriptions": [
                    {
                        "AudioTypeControl": "FOLLOW_INPUT",
                        "CodecSettings": {
                            "Codec": "AAC",
                            "AacSettings": {
                                "Bitrate": 96000,
                                "CodingMode": "CODING_MODE_2_0",
                                "SampleRate": 48000
                            }
                        }
                    }
                ]
            },
            {
                "NameModifier": "_360p",
                "ContainerSettings": {
                    "Container": "M3U8",
                    "M3u8Settings": {
                        "PcrControl": "PCR_EVERY_PES_PACKET",
                        "PmtPid": 480,
                        "PrivateMetadataPid": 503,
                        "ProgramNumber": 1,
                        "PatInterval": 0,
                        "PmtInterval": 0,
                        "VideoPid": 481,
                        "AudioPids": [482, 483, 484, 485, 486, 487, 488, 489, 490, 491, 492]
                    }
                },
                "VideoDescription": {
                    "Width": 640,
                    "Height": 360,
                    "CodecSettings": {
                        "Codec": "H_264",
                        "H264Settings": {
                            "RateControlMode": "QVBR",
                            "QvbrSettings": {"QvbrQualityLevel": 5},
                            "MaxBitrate": 800000,
                            "FramerateControl": "INITIALIZE_FROM_SOURCE",
                            "GopClosedCadence": 1,
                            "GopSize": 90,
                            "GopSizeUnits": "FRAMES",
                            "ParControl": "INITIALIZE_FROM_SOURCE",
                            "QualityTuningLevel": "SINGLE_PASS",
                            "SceneChangeDetect": "ENABLED"
                        }
                    }
                },
                "AudioDescriptions": [
                    {
                        "AudioTypeControl": "FOLLOW_INPUT",
                        "CodecSettings": {
                            "Codec": "AAC",
                            "AacSettings": {
                                "Bitrate": 64000,
                                "CodingMode": "CODING_MODE_2_0",
                                "SampleRate": 48000
                            }
                        }
                    }
                ]
            }
        ]

    def _get_dash_outputs(self) -> List[Dict[str, Any]]:
        """Generate DASH output configurations for different quality levels"""
        return [
            {
                "NameModifier": "_dash_1080p",
                "ContainerSettings": {
                    "Container": "MP4",
                    "Mp4Settings": {
                        "CslgAtom": "INCLUDE",
                        "FreeSpaceBox": "EXCLUDE",
                        "MoovPlacement": "PROGRESSIVE_DOWNLOAD"
                    }
                },
                "VideoDescription": {
                    "Width": 1920,
                    "Height": 1080,
                    "CodecSettings": {
                        "Codec": "H_264",
                        "H264Settings": {
                            "RateControlMode": "QVBR",
                            "QvbrSettings": {"QvbrQualityLevel": 8},
                            "MaxBitrate": 5000000,
                            "FramerateControl": "INITIALIZE_FROM_SOURCE",
                            "GopClosedCadence": 1,
                            "GopSize": 90,
                            "GopSizeUnits": "FRAMES",
                            "ParControl": "INITIALIZE_FROM_SOURCE",
                            "QualityTuningLevel": "SINGLE_PASS",
                            "SceneChangeDetect": "ENABLED"
                        }
                    }
                },
                "AudioDescriptions": [
                    {
                        "AudioTypeControl": "FOLLOW_INPUT",
                        "CodecSettings": {
                            "Codec": "AAC",
                            "AacSettings": {
                                "Bitrate": 128000,
                                "CodingMode": "CODING_MODE_2_0",
                                "SampleRate": 48000
                            }
                        }
                    }
                ]
            },
            {
                "NameModifier": "_dash_720p",
                "ContainerSettings": {
                    "Container": "MP4",
                    "Mp4Settings": {
                        "CslgAtom": "INCLUDE",
                        "FreeSpaceBox": "EXCLUDE",
                        "MoovPlacement": "PROGRESSIVE_DOWNLOAD"
                    }
                },
                "VideoDescription": {
                    "Width": 1280,
                    "Height": 720,
                    "CodecSettings": {
                        "Codec": "H_264",
                        "H264Settings": {
                            "RateControlMode": "QVBR",
                            "QvbrSettings": {"QvbrQualityLevel": 7},
                            "MaxBitrate": 3000000,
                            "FramerateControl": "INITIALIZE_FROM_SOURCE",
                            "GopClosedCadence": 1,
                            "GopSize": 90,
                            "GopSizeUnits": "FRAMES",
                            "ParControl": "INITIALIZE_FROM_SOURCE",
                            "QualityTuningLevel": "SINGLE_PASS",
                            "SceneChangeDetect": "ENABLED"
                        }
                    }
                },
                "AudioDescriptions": [
                    {
                        "AudioTypeControl": "FOLLOW_INPUT",
                        "CodecSettings": {
                            "Codec": "AAC",
                            "AacSettings": {
                                "Bitrate": 128000,
                                "CodingMode": "CODING_MODE_2_0",
                                "SampleRate": 48000
                            }
                        }
                    }
                ]
            }
        ]

    def _get_thumbnail_outputs(self) -> List[Dict[str, Any]]:
        """Generate thumbnail output configuration"""
        return [
            {
                "NameModifier": "_thumb_%04d",
                "ContainerSettings": {
                    "Container": "RAW"
                },
                "VideoDescription": {
                    "Width": 1280,
                    "Height": 720,
                    "CodecSettings": {
                        "Codec": "FRAME_CAPTURE",
                        "FrameCaptureSettings": {
                            "FramerateNumerator": 1,
                            "FramerateDenominator": 10,
                            "MaxCaptures": 10,
                            "Quality": 80
                        }
                    }
                }
            }
        ]

    def _create_lambda_function(self) -> None:
        """Create Lambda function for processing video uploads"""
        
        # Lambda function code for ABR processing
        lambda_code = '''
import json
import boto3
import os
from urllib.parse import unquote_plus

def lambda_handler(event, context):
    """Process S3 video upload events and trigger MediaConvert jobs"""
    
    # Initialize MediaConvert client with customer endpoint
    mediaconvert = boto3.client('mediaconvert')
    
    # Get MediaConvert endpoint for this account/region
    endpoints = mediaconvert.describe_endpoints()
    customer_endpoint = endpoints['Endpoints'][0]['Url']
    
    # Create MediaConvert client with customer endpoint
    mediaconvert = boto3.client('mediaconvert', endpoint_url=customer_endpoint)
    
    # Process S3 event records
    for record in event['Records']:
        bucket = record['s3']['bucket']['name']
        key = unquote_plus(record['s3']['object']['key'])
        
        # Only process video files
        video_extensions = ('.mp4', '.mov', '.avi', '.mkv', '.mxf', '.mts', '.m2ts')
        if not key.lower().endswith(video_extensions):
            print(f"Skipping non-video file: {key}")
            continue
        
        # Extract filename without extension for output naming
        file_name = key.split('/')[-1].split('.')[0]
        
        # Create MediaConvert job settings
        job_settings = {
            "JobTemplate": os.environ['JOB_TEMPLATE'],
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
                        },
                        "VideoSelector": {
                            "ColorSpace": "FOLLOW"
                        },
                        "TimecodeSource": "EMBEDDED"
                    }
                ],
                "OutputGroups": [
                    {
                        "OutputGroupSettings": {
                            "Type": "HLS_GROUP_SETTINGS",
                            "HlsGroupSettings": {
                                "Destination": f"s3://{os.environ['OUTPUT_BUCKET']}/hls/{file_name}/"
                            }
                        }
                    },
                    {
                        "OutputGroupSettings": {
                            "Type": "DASH_ISO_GROUP_SETTINGS", 
                            "DashIsoGroupSettings": {
                                "Destination": f"s3://{os.environ['OUTPUT_BUCKET']}/dash/{file_name}/"
                            }
                        }
                    },
                    {
                        "OutputGroupSettings": {
                            "Type": "FILE_GROUP_SETTINGS",
                            "FileGroupSettings": {
                                "Destination": f"s3://{os.environ['OUTPUT_BUCKET']}/thumbnails/{file_name}/"
                            }
                        }
                    }
                ]
            },
            "StatusUpdateInterval": "SECONDS_60",
            "UserMetadata": {
                "SourceFile": key,
                "ProcessingType": "ABR_Streaming"
            }
        }
        
        try:
            # Create MediaConvert job
            response = mediaconvert.create_job(**job_settings)
            job_id = response['Job']['Id']
            
            print(f"Created ABR processing job {job_id} for {key}")
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': f'Successfully started ABR processing job {job_id}',
                    'jobId': job_id,
                    'sourceFile': key,
                    'hlsOutput': f"s3://{os.environ['OUTPUT_BUCKET']}/hls/{file_name}/",
                    'dashOutput': f"s3://{os.environ['OUTPUT_BUCKET']}/dash/{file_name}/"
                })
            }
            
        except Exception as e:
            print(f"Error creating MediaConvert job: {str(e)}")
            return {
                'statusCode': 500,
                'body': json.dumps({
                    'error': str(e),
                    'sourceFile': key
                })
            }
'''

        # Create Lambda function
        self.lambda_function = lambda_.Function(
            self, "VideoABRProcessor",
            function_name=f"video-abr-processor-{self.random_suffix}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(lambda_code),
            role=self.lambda_role,
            timeout=Duration.minutes(5),
            memory_size=256,
            description="Lambda function to trigger MediaConvert ABR jobs for uploaded videos",
            environment={
                "JOB_TEMPLATE": self.job_template.name,
                "MEDIACONVERT_ROLE_ARN": self.mediaconvert_role.role_arn,
                "OUTPUT_BUCKET": self.output_bucket.bucket_name
            },
            log_retention=logs.RetentionDays.TWO_WEEKS,
            retry_attempts=0
        )

        # Add resource-based policy for S3 to invoke Lambda
        self.lambda_function.add_permission(
            "S3InvokePermission",
            principal=iam.ServicePrincipal("s3.amazonaws.com"),
            source_arn=self.source_bucket.bucket_arn
        )

    def _configure_s3_events(self) -> None:
        """Configure S3 event notifications to trigger Lambda function"""
        
        # Add S3 event notification for video file uploads
        self.source_bucket.add_event_notification(
            s3.EventType.OBJECT_CREATED,
            s3n.LambdaDestination(self.lambda_function),
            s3.NotificationKeyFilter(suffix=".mp4")
        )
        
        self.source_bucket.add_event_notification(
            s3.EventType.OBJECT_CREATED,
            s3n.LambdaDestination(self.lambda_function),
            s3.NotificationKeyFilter(suffix=".mov")
        )
        
        self.source_bucket.add_event_notification(
            s3.EventType.OBJECT_CREATED,
            s3n.LambdaDestination(self.lambda_function),
            s3.NotificationKeyFilter(suffix=".avi")
        )
        
        self.source_bucket.add_event_notification(
            s3.EventType.OBJECT_CREATED,
            s3n.LambdaDestination(self.lambda_function),
            s3.NotificationKeyFilter(suffix=".mkv")
        )

    def _create_cloudfront_distribution(self) -> None:
        """Create CloudFront distribution for global content delivery"""
        
        # Origin access identity for S3
        origin_access_identity = cloudfront.OriginAccessIdentity(
            self, "ABRStreamingOAI",
            comment=f"OAI for ABR streaming output bucket {self.output_bucket.bucket_name}"
        )

        # Grant read access to CloudFront OAI
        self.output_bucket.grant_read(origin_access_identity)

        # Cache behaviors for different content types
        manifest_cache_behavior = cloudfront.BehaviorOptions(
            origin=origins.S3Origin(
                bucket=self.output_bucket,
                origin_access_identity=origin_access_identity
            ),
            viewer_protocol_policy=cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
            cache_policy=cloudfront.CachePolicy.CACHING_OPTIMIZED,
            allowed_methods=cloudfront.AllowedMethods.ALLOW_GET_HEAD,
            compress=False,
            ttl=Duration.seconds(5)  # Short TTL for manifests
        )

        segment_cache_behavior = cloudfront.BehaviorOptions(
            origin=origins.S3Origin(
                bucket=self.output_bucket,
                origin_access_identity=origin_access_identity
            ),
            viewer_protocol_policy=cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
            cache_policy=cloudfront.CachePolicy.CACHING_OPTIMIZED,
            allowed_methods=cloudfront.AllowedMethods.ALLOW_GET_HEAD,
            compress=False,
            ttl=Duration.hours(24)  # Long TTL for video segments
        )

        # Create CloudFront distribution
        self.distribution = cloudfront.Distribution(
            self, "ABRStreamingDistribution",
            comment="Adaptive Bitrate Streaming Distribution",
            default_behavior=cloudfront.BehaviorOptions(
                origin=origins.S3Origin(
                    bucket=self.output_bucket,
                    origin_access_identity=origin_access_identity
                ),
                viewer_protocol_policy=cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
                cache_policy=cloudfront.CachePolicy.CACHING_OPTIMIZED,
                allowed_methods=cloudfront.AllowedMethods.ALLOW_GET_HEAD,
                compress=False
            ),
            additional_behaviors={
                "*.m3u8": manifest_cache_behavior,  # HLS manifests
                "*.mpd": manifest_cache_behavior,   # DASH manifests
                "*.ts": segment_cache_behavior,     # HLS segments
                "*.mp4": segment_cache_behavior,    # DASH segments
                "*.jpg": segment_cache_behavior,    # Thumbnails
                "*.png": segment_cache_behavior     # Thumbnails
            },
            price_class=cloudfront.PriceClass.PRICE_CLASS_ALL,
            http_version=cloudfront.HttpVersion.HTTP2,
            enable_ipv6=True,
            minimum_protocol_version=cloudfront.SecurityPolicyProtocol.TLS_V1_2_2021
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information"""
        
        CfnOutput(
            self, "SourceBucketName",
            value=self.source_bucket.bucket_name,
            description="S3 bucket for source video uploads",
            export_name=f"{self.stack_name}-SourceBucket"
        )

        CfnOutput(
            self, "OutputBucketName",
            value=self.output_bucket.bucket_name,
            description="S3 bucket for processed ABR video outputs",
            export_name=f"{self.stack_name}-OutputBucket"
        )

        CfnOutput(
            self, "CloudFrontDistributionId",
            value=self.distribution.distribution_id,
            description="CloudFront distribution ID for content delivery",
            export_name=f"{self.stack_name}-DistributionId"
        )

        CfnOutput(
            self, "CloudFrontDomainName",
            value=self.distribution.domain_name,
            description="CloudFront distribution domain name",
            export_name=f"{self.stack_name}-DistributionDomain"
        )

        CfnOutput(
            self, "LambdaFunctionName",
            value=self.lambda_function.function_name,
            description="Lambda function for video processing automation",
            export_name=f"{self.stack_name}-LambdaFunction"
        )

        CfnOutput(
            self, "MediaConvertJobTemplate",
            value=self.job_template.name,
            description="MediaConvert job template for ABR transcoding",
            export_name=f"{self.stack_name}-JobTemplate"
        )

        CfnOutput(
            self, "MediaConvertRoleArn",
            value=self.mediaconvert_role.role_arn,
            description="IAM role ARN for MediaConvert service access",
            export_name=f"{self.stack_name}-MediaConvertRole"
        )

        CfnOutput(
            self, "HLSStreamingUrl",
            value=f"https://{self.distribution.domain_name}/hls/[video-name]/index.m3u8",
            description="Template URL for HLS streaming (replace [video-name] with actual video name)",
            export_name=f"{self.stack_name}-HLSTemplate"
        )

        CfnOutput(
            self, "DASHStreamingUrl",
            value=f"https://{self.distribution.domain_name}/dash/[video-name]/index.mpd",
            description="Template URL for DASH streaming (replace [video-name] with actual video name)",
            export_name=f"{self.stack_name}-DASHTemplate"
        )


# CDK App instantiation
app = cdk.App()

# Stack configuration from context or environment variables
stack_name = app.node.try_get_context("stackName") or "AdaptiveBitrateStreamingStack"
env_name = app.node.try_get_context("environment") or "dev"

# Create stack with environment configuration
AdaptiveBitrateStreamingStack(
    app, 
    f"{stack_name}-{env_name}",
    env=Environment(
        account=os.environ.get('CDK_DEFAULT_ACCOUNT'),
        region=os.environ.get('CDK_DEFAULT_REGION', 'us-east-1')
    ),
    description="AWS CDK stack for adaptive bitrate video streaming with MediaConvert and CloudFront"
)

# Add tags to all resources in the app
Tags.of(app).add("Project", "AdaptiveBitrateStreaming")
Tags.of(app).add("Environment", env_name)
Tags.of(app).add("ManagedBy", "CDK")
Tags.of(app).add("CostCenter", "MediaServices")

app.synth()