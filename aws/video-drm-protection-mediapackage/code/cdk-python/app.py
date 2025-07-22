#!/usr/bin/env python3
"""
AWS CDK Application for DRM-Protected Video Content with MediaPackage

This application creates a comprehensive DRM-protected video streaming solution using:
- AWS Elemental MediaLive for video ingestion and encoding
- AWS Elemental MediaPackage for content packaging and DRM integration
- AWS Lambda for SPEKE (Secure Packager and Encoder Key Exchange) API
- Amazon CloudFront for global content delivery with geographic restrictions
- AWS Secrets Manager and KMS for secure key management

Author: AWS CDK Generator
Version: 1.0
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Tags,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_iam as iam,
    aws_lambda as _lambda,
    aws_secretsmanager as secretsmanager,
    aws_kms as kms,
    aws_s3 as s3,
    aws_cloudfront as cloudfront,
    aws_cloudfront_origins as origins,
    aws_medialive as medialive,
    aws_mediapackage as mediapackage,
    aws_logs as logs,
)
from constructs import Construct


class DrmProtectedVideoStreamingStack(Stack):
    """
    CDK Stack for DRM-Protected Video Streaming Infrastructure
    
    Creates a complete video streaming solution with enterprise-grade DRM protection,
    multi-format support (HLS/DASH), and global content delivery.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Stack configuration
        self.stack_name = construct_id
        self.region = self.region
        self.account = self.account
        
        # Generate unique resource names
        self.unique_suffix = cdk.Fn.select(0, cdk.Fn.split('-', cdk.Fn.ref('AWS::StackId')))[:8]
        
        # Create KMS key for DRM encryption
        self.drm_kms_key = self._create_drm_kms_key()
        
        # Create Secrets Manager secret for DRM configuration
        self.drm_secret = self._create_drm_secret()
        
        # Create SPEKE Lambda function for key management
        self.speke_lambda = self._create_speke_lambda()
        
        # Create S3 bucket for test content
        self.content_bucket = self._create_content_bucket()
        
        # Create MediaLive resources
        self.medialive_security_group = self._create_medialive_security_group()
        self.medialive_input = self._create_medialive_input()
        self.medialive_role = self._create_medialive_role()
        
        # Create MediaPackage channel and endpoints
        self.mediapackage_channel = self._create_mediapackage_channel()
        self.hls_endpoint = self._create_hls_drm_endpoint()
        self.dash_endpoint = self._create_dash_drm_endpoint()
        
        # Create MediaLive channel
        self.medialive_channel = self._create_medialive_channel()
        
        # Create CloudFront distribution
        self.cloudfront_distribution = self._create_cloudfront_distribution()
        
        # Add stack outputs
        self._create_outputs()
        
        # Add tags to all resources
        self._add_stack_tags()

    def _create_drm_kms_key(self) -> kms.Key:
        """Create KMS key for DRM content encryption."""
        key = kms.Key(
            self, "DrmKmsKey",
            description="DRM content encryption key for video streaming",
            enable_key_rotation=True,
            removal_policy=RemovalPolicy.DESTROY,
            key_spec=kms.KeySpec.SYMMETRIC_DEFAULT,
            key_usage=kms.KeyUsage.ENCRYPT_DECRYPT,
        )
        
        # Add alias for easier reference
        kms.Alias(
            self, "DrmKmsKeyAlias",
            alias_name=f"alias/drm-content-{self.unique_suffix}",
            target_key=key
        )
        
        return key

    def _create_drm_secret(self) -> secretsmanager.Secret:
        """Create Secrets Manager secret for DRM configuration."""
        drm_config = {
            "widevine_provider": "speke-reference",
            "playready_provider": "speke-reference",
            "fairplay_provider": "speke-reference",
            "content_id_template": "urn:uuid:",
            "key_rotation_interval_seconds": 3600,
            "license_duration_seconds": 86400
        }
        
        secret = secretsmanager.Secret(
            self, "DrmSecret",
            description="DRM configuration and key management parameters",
            secret_name=f"drm-encryption-keys-{self.unique_suffix}",
            encryption_key=self.drm_kms_key,
            secret_object_value={
                key: cdk.SecretValue.unsafe_plain_text(str(value))
                for key, value in drm_config.items()
            },
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        return secret

    def _create_speke_lambda(self) -> _lambda.Function:
        """Create SPEKE API Lambda function for DRM key management."""
        
        # Create Lambda execution role
        lambda_role = iam.Role(
            self, "SpekeLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole")
            ],
            inline_policies={
                "SecretsManagerAccess": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "secretsmanager:GetSecretValue",
                                "secretsmanager:DescribeSecret"
                            ],
                            resources=[self.drm_secret.secret_arn]
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "kms:Decrypt",
                                "kms:GenerateDataKey"
                            ],
                            resources=[self.drm_kms_key.key_arn]
                        )
                    ]
                )
            }
        )
        
        # SPEKE Lambda function code
        speke_code = '''
import json
import boto3
import base64
import uuid
import os
from datetime import datetime, timedelta

def lambda_handler(event, context):
    """
    SPEKE API Lambda function for DRM key generation
    Supports Widevine, PlayReady, and FairPlay DRM systems
    """
    print(f"SPEKE request: {json.dumps(event, indent=2)}")
    
    try:
        # Parse SPEKE request
        if 'body' in event:
            body = json.loads(event['body']) if isinstance(event['body'], str) else event['body']
        else:
            body = event
        
        # Extract content ID and DRM systems
        content_id = body.get('content_id', str(uuid.uuid4()))
        drm_systems = body.get('drm_systems', [])
        
        # Initialize response
        response = {
            "content_id": content_id,
            "drm_systems": []
        }
        
        # Generate keys for each requested DRM system
        for drm_system in drm_systems:
            system_id = drm_system.get('system_id')
            
            if system_id == 'edef8ba9-79d6-4ace-a3c8-27dcd51d21ed':  # Widevine
                drm_response = generate_widevine_keys(content_id)
            elif system_id == '9a04f079-9840-4286-ab92-e65be0885f95':  # PlayReady  
                drm_response = generate_playready_keys(content_id)
            elif system_id == '94ce86fb-07ff-4f43-adb8-93d2fa968ca2':  # FairPlay
                drm_response = generate_fairplay_keys(content_id)
            else:
                continue
            
            response['drm_systems'].append(drm_response)
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps(response)
        }
        
    except Exception as e:
        print(f"Error processing SPEKE request: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': 'Internal server error'})
        }

def generate_widevine_keys(content_id):
    """Generate Widevine DRM keys and metadata"""
    # Generate 16-byte content key and key ID
    content_key = os.urandom(16)
    key_id = os.urandom(16)
    
    return {
        "system_id": "edef8ba9-79d6-4ace-a3c8-27dcd51d21ed",
        "key_id": base64.b64encode(key_id).decode('utf-8'),
        "content_key": base64.b64encode(content_key).decode('utf-8'),
        "url": "https://proxy.uat.widevine.com/proxy?provider=widevine_test",
        "pssh": generate_widevine_pssh(key_id)
    }

def generate_playready_keys(content_id):
    """Generate PlayReady DRM keys and metadata"""
    content_key = os.urandom(16)
    key_id = os.urandom(16)
    
    return {
        "system_id": "9a04f079-9840-4286-ab92-e65be0885f95", 
        "key_id": base64.b64encode(key_id).decode('utf-8'),
        "content_key": base64.b64encode(content_key).decode('utf-8'),
        "url": "https://playready-license.test.com/rightsmanager.asmx",
        "pssh": generate_playready_pssh(key_id, content_key)
    }

def generate_fairplay_keys(content_id):
    """Generate FairPlay DRM keys and metadata"""
    content_key = os.urandom(16) 
    key_id = os.urandom(16)
    iv = os.urandom(16)
    
    return {
        "system_id": "94ce86fb-07ff-4f43-adb8-93d2fa968ca2",
        "key_id": base64.b64encode(key_id).decode('utf-8'),
        "content_key": base64.b64encode(content_key).decode('utf-8'),
        "url": "skd://fairplay-license.test.com/license",
        "certificate_url": "https://fairplay-license.test.com/cert",
        "iv": base64.b64encode(iv).decode('utf-8')
    }

def generate_widevine_pssh(key_id):
    """Generate Widevine PSSH (Protection System Specific Header)"""
    pssh_data = {
        "key_ids": [base64.b64encode(key_id).decode('utf-8')],
        "provider": "widevine_test",
        "content_id": base64.b64encode(key_id).decode('utf-8')
    }
    return base64.b64encode(json.dumps(pssh_data).encode()).decode('utf-8')

def generate_playready_pssh(key_id, content_key):
    """Generate PlayReady PSSH (Protection System Specific Header)"""
    pssh_data = f"""
    <WRMHEADER xmlns="http://schemas.microsoft.com/DRM/2007/03/PlayReadyHeader" version="4.0.0.0">
        <DATA>
            <PROTECTINFO>
                <KEYLEN>16</KEYLEN>
                <ALGID>AESCTR</ALGID>
            </PROTECTINFO>
            <KID>{base64.b64encode(key_id).decode('utf-8')}</KID>
            <CHECKSUM></CHECKSUM>
        </DATA>
    </WRMHEADER>
    """
    return base64.b64encode(pssh_data.encode()).decode('utf-8')
'''
        
        # Create Lambda function
        lambda_function = _lambda.Function(
            self, "SpekeLambda",
            function_name=f"drm-speke-provider-{self.unique_suffix}",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline(speke_code),
            timeout=Duration.seconds(30),
            memory_size=256,
            role=lambda_role,
            environment={
                "DRM_SECRET_ARN": self.drm_secret.secret_arn,
                "KMS_KEY_ID": self.drm_kms_key.key_id
            },
            log_retention=logs.RetentionDays.ONE_WEEK,
            description="SPEKE API provider for DRM key management"
        )
        
        # Create function URL for SPEKE endpoint
        function_url = lambda_function.add_function_url(
            auth_type=_lambda.FunctionUrlAuthType.NONE,
            cors=_lambda.FunctionUrlCorsOptions(
                allow_credentials=False,
                allow_headers=["*"],
                allow_methods=[_lambda.HttpMethod.ALL],
                allow_origins=["*"]
            )
        )
        
        return lambda_function

    def _create_content_bucket(self) -> s3.Bucket:
        """Create S3 bucket for test content and player."""
        bucket = s3.Bucket(
            self, "ContentBucket",
            bucket_name=f"drm-test-content-{self.unique_suffix}",
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            encryption=s3.BucketEncryption.S3_MANAGED,
            versioned=False,
            website_index_document="index.html",
            website_error_document="error.html"
        )
        
        return bucket

    def _create_medialive_security_group(self) -> medialive.CfnInputSecurityGroup:
        """Create MediaLive input security group."""
        security_group = medialive.CfnInputSecurityGroup(
            self, "MediaLiveSecurityGroup",
            whitelist_rules=[
                medialive.CfnInputSecurityGroup.InputWhitelistRuleCidrProperty(
                    cidr="0.0.0.0/0"
                )
            ],
            tags={
                "Name": f"DRMSecurityGroup-{self.unique_suffix}",
                "Environment": "Production"
            }
        )
        
        return security_group

    def _create_medialive_input(self) -> medialive.CfnInput:
        """Create MediaLive RTMP input."""
        input_resource = medialive.CfnInput(
            self, "MediaLiveInput",
            name=f"drm-protected-input-{self.unique_suffix}",
            type="RTMP_PUSH",
            input_security_groups=[self.medialive_security_group.ref],
            tags={
                "Name": f"DRMInput-{self.unique_suffix}",
                "Type": "Live"
            }
        )
        
        return input_resource

    def _create_medialive_role(self) -> iam.Role:
        """Create IAM role for MediaLive with DRM permissions."""
        role = iam.Role(
            self, "MediaLiveRole",
            role_name=f"MediaLiveDRMRole-{self.unique_suffix}",
            assumed_by=iam.ServicePrincipal("medialive.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonElementalMediaLiveFullAccess")
            ],
            inline_policies={
                "MediaPackageAccess": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=["mediapackage:*"],
                            resources=["*"]
                        )
                    ]
                ),
                "DRMAccess": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "secretsmanager:GetSecretValue",
                                "secretsmanager:DescribeSecret"
                            ],
                            resources=[self.drm_secret.secret_arn]
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "kms:Decrypt",
                                "kms:GenerateDataKey"
                            ],
                            resources=[self.drm_kms_key.key_arn]
                        )
                    ]
                )
            }
        )
        
        return role

    def _create_mediapackage_channel(self) -> mediapackage.CfnChannel:
        """Create MediaPackage channel for DRM-protected content."""
        channel = mediapackage.CfnChannel(
            self, "MediaPackageChannel",
            id=f"drm-package-channel-{self.unique_suffix}",
            description="DRM-protected streaming channel",
            tags=[
                cdk.CfnTag(key="Name", value=f"DRMChannel-{self.unique_suffix}"),
                cdk.CfnTag(key="Environment", value="Production")
            ]
        )
        
        return channel

    def _create_hls_drm_endpoint(self) -> mediapackage.CfnOriginEndpoint:
        """Create HLS origin endpoint with multi-DRM protection."""
        endpoint = mediapackage.CfnOriginEndpoint(
            self, "HlsDrmEndpoint",
            channel_id=self.mediapackage_channel.id,
            id=f"{self.mediapackage_channel.id}-hls-drm",
            manifest_name="index.m3u8",
            hls_package=mediapackage.CfnOriginEndpoint.HlsPackageProperty(
                segment_duration_seconds=6,
                playlist_type="EVENT",
                playlist_window_seconds=300,
                program_date_time_interval_seconds=60,
                ad_markers="SCTE35_ENHANCED",
                include_iframe_only_stream=False,
                use_audio_rendition_group=True,
                encryption=mediapackage.CfnOriginEndpoint.HlsEncryptionProperty(
                    speke_key_provider=mediapackage.CfnOriginEndpoint.SpekeKeyProviderProperty(
                        url=self.speke_lambda.function_url.url,
                        resource_id=f"{self.mediapackage_channel.id}-hls",
                        system_ids=[
                            "edef8ba9-79d6-4ace-a3c8-27dcd51d21ed",  # Widevine
                            "9a04f079-9840-4286-ab92-e65be0885f95",  # PlayReady
                            "94ce86fb-07ff-4f43-adb8-93d2fa968ca2"   # FairPlay
                        ]
                    ),
                    key_rotation_interval_seconds=3600
                )
            ),
            tags=[
                cdk.CfnTag(key="Type", value="HLS"),
                cdk.CfnTag(key="DRM", value="MultiDRM"),
                cdk.CfnTag(key="Environment", value="Production")
            ]
        )
        
        return endpoint

    def _create_dash_drm_endpoint(self) -> mediapackage.CfnOriginEndpoint:
        """Create DASH origin endpoint with multi-DRM protection."""
        endpoint = mediapackage.CfnOriginEndpoint(
            self, "DashDrmEndpoint",
            channel_id=self.mediapackage_channel.id,
            id=f"{self.mediapackage_channel.id}-dash-drm",
            manifest_name="index.mpd",
            dash_package=mediapackage.CfnOriginEndpoint.DashPackageProperty(
                segment_duration_seconds=6,
                min_buffer_time_seconds=30,
                min_update_period_seconds=15,
                suggested_presentation_delay_seconds=30,
                profile="NONE",
                period_triggers=["ADS"],
                encryption=mediapackage.CfnOriginEndpoint.DashEncryptionProperty(
                    speke_key_provider=mediapackage.CfnOriginEndpoint.SpekeKeyProviderProperty(
                        url=self.speke_lambda.function_url.url,
                        resource_id=f"{self.mediapackage_channel.id}-dash",
                        system_ids=[
                            "edef8ba9-79d6-4ace-a3c8-27dcd51d21ed",  # Widevine
                            "9a04f079-9840-4286-ab92-e65be0885f95"   # PlayReady
                        ]
                    ),
                    key_rotation_interval_seconds=3600
                )
            ),
            tags=[
                cdk.CfnTag(key="Type", value="DASH"),
                cdk.CfnTag(key="DRM", value="MultiDRM"),
                cdk.CfnTag(key="Environment", value="Production")
            ]
        )
        
        return endpoint

    def _create_medialive_channel(self) -> medialive.CfnChannel:
        """Create MediaLive channel for DRM content encoding."""
        
        # Audio description configuration
        audio_description = medialive.CfnChannel.AudioDescriptionProperty(
            name="audio_aac",
            audio_selector_name="default",
            audio_type_control="FOLLOW_INPUT",
            language_code_control="FOLLOW_INPUT",
            codec_settings=medialive.CfnChannel.AudioCodecSettingsProperty(
                aac_settings=medialive.CfnChannel.AacSettingsProperty(
                    bitrate=128000,
                    coding_mode="CODING_MODE_2_0",
                    sample_rate=48000,
                    spec="MPEG4"
                )
            )
        )
        
        # Video descriptions for different quality levels
        video_descriptions = [
            # 1080p HD
            medialive.CfnChannel.VideoDescriptionProperty(
                name="video_1080p_drm",
                width=1920,
                height=1080,
                codec_settings=medialive.CfnChannel.VideoCodecSettingsProperty(
                    h264_settings=medialive.CfnChannel.H264SettingsProperty(
                        bitrate=5000000,
                        framerate_control="SPECIFIED",
                        framerate_numerator=30,
                        framerate_denominator=1,
                        gop_b_reference="ENABLED",
                        gop_closed_cadence=1,
                        gop_num_b_frames=3,
                        gop_size=90,
                        gop_size_units="FRAMES",
                        profile="HIGH",
                        level="H264_LEVEL_4_1",
                        rate_control_mode="CBR",
                        syntax="DEFAULT",
                        adaptive_quantization="HIGH",
                        color_metadata="INSERT",
                        entropy_encoding="CABAC",
                        flicker_aq="ENABLED",
                        force_field_pictures="DISABLED",
                        temporal_aq="ENABLED",
                        spatial_aq="ENABLED"
                    )
                ),
                respond_to_afd="RESPOND",
                scaling_behavior="DEFAULT",
                sharpness=50
            ),
            # 720p HD
            medialive.CfnChannel.VideoDescriptionProperty(
                name="video_720p_drm",
                width=1280,
                height=720,
                codec_settings=medialive.CfnChannel.VideoCodecSettingsProperty(
                    h264_settings=medialive.CfnChannel.H264SettingsProperty(
                        bitrate=3000000,
                        framerate_control="SPECIFIED",
                        framerate_numerator=30,
                        framerate_denominator=1,
                        gop_b_reference="ENABLED",
                        gop_closed_cadence=1,
                        gop_num_b_frames=3,
                        gop_size=90,
                        gop_size_units="FRAMES",
                        profile="HIGH",
                        level="H264_LEVEL_3_1",
                        rate_control_mode="CBR",
                        syntax="DEFAULT",
                        adaptive_quantization="HIGH",
                        temporal_aq="ENABLED",
                        spatial_aq="ENABLED"
                    )
                ),
                respond_to_afd="RESPOND",
                scaling_behavior="DEFAULT",
                sharpness=50
            ),
            # 480p SD
            medialive.CfnChannel.VideoDescriptionProperty(
                name="video_480p_drm",
                width=854,
                height=480,
                codec_settings=medialive.CfnChannel.VideoCodecSettingsProperty(
                    h264_settings=medialive.CfnChannel.H264SettingsProperty(
                        bitrate=1500000,
                        framerate_control="SPECIFIED",
                        framerate_numerator=30,
                        framerate_denominator=1,
                        gop_b_reference="DISABLED",
                        gop_closed_cadence=1,
                        gop_num_b_frames=2,
                        gop_size=90,
                        gop_size_units="FRAMES",
                        profile="MAIN",
                        level="H264_LEVEL_3_0",
                        rate_control_mode="CBR",
                        syntax="DEFAULT",
                        adaptive_quantization="MEDIUM"
                    )
                ),
                respond_to_afd="RESPOND",
                scaling_behavior="DEFAULT",
                sharpness=50
            )
        ]
        
        # Output group for MediaPackage
        output_group = medialive.CfnChannel.OutputGroupProperty(
            name="MediaPackage-DRM-ABR",
            output_group_settings=medialive.CfnChannel.OutputGroupSettingsProperty(
                media_package_group_settings=medialive.CfnChannel.MediaPackageGroupSettingsProperty(
                    destination=medialive.CfnChannel.OutputLocationRefProperty(
                        destination_ref_id="mediapackage-drm-destination"
                    )
                )
            ),
            outputs=[
                medialive.CfnChannel.OutputProperty(
                    output_name="1080p-protected",
                    video_description_name="video_1080p_drm",
                    audio_description_names=["audio_aac"],
                    output_settings=medialive.CfnChannel.OutputSettingsProperty(
                        media_package_output_settings=medialive.CfnChannel.MediaPackageOutputSettingsProperty()
                    )
                ),
                medialive.CfnChannel.OutputProperty(
                    output_name="720p-protected",
                    video_description_name="video_720p_drm",
                    audio_description_names=["audio_aac"],
                    output_settings=medialive.CfnChannel.OutputSettingsProperty(
                        media_package_output_settings=medialive.CfnChannel.MediaPackageOutputSettingsProperty()
                    )
                ),
                medialive.CfnChannel.OutputProperty(
                    output_name="480p-protected",
                    video_description_name="video_480p_drm",
                    audio_description_names=["audio_aac"],
                    output_settings=medialive.CfnChannel.OutputSettingsProperty(
                        media_package_output_settings=medialive.CfnChannel.MediaPackageOutputSettingsProperty()
                    )
                )
            ]
        )
        
        # Create MediaLive channel
        channel = medialive.CfnChannel(
            self, "MediaLiveChannel",
            name=f"drm-protected-channel-{self.unique_suffix}",
            role_arn=self.medialive_role.role_arn,
            input_specification=medialive.CfnChannel.InputSpecificationProperty(
                codec="AVC",
                resolution="HD",
                maximum_bitrate="MAX_20_MBPS"
            ),
            input_attachments=[
                medialive.CfnChannel.InputAttachmentProperty(
                    input_id=self.medialive_input.ref,
                    input_attachment_name="primary-input",
                    input_settings=medialive.CfnChannel.InputSettingsProperty(
                        source_end_behavior="CONTINUE",
                        input_filter="AUTO",
                        filter_strength=1,
                        deblock_filter="ENABLED",
                        denoise_filter="ENABLED"
                    )
                )
            ],
            destinations=[
                medialive.CfnChannel.OutputDestinationProperty(
                    id="mediapackage-drm-destination",
                    media_package_settings=[
                        medialive.CfnChannel.MediaPackageOutputDestinationProperty(
                            channel_id=self.mediapackage_channel.id
                        )
                    ]
                )
            ],
            encoder_settings=medialive.CfnChannel.EncoderSettingsProperty(
                audio_descriptions=[audio_description],
                video_descriptions=video_descriptions,
                output_groups=[output_group],
                timecode_config=medialive.CfnChannel.TimecodeConfigProperty(
                    source="EMBEDDED"
                )
            ),
            tags={
                "Environment": "Production",
                "Service": "DRM-Protected-Streaming",
                "Component": "MediaLive"
            }
        )
        
        return channel

    def _create_cloudfront_distribution(self) -> cloudfront.Distribution:
        """Create CloudFront distribution for DRM content delivery."""
        
        # Create custom cache policy for DRM content
        cache_policy = cloudfront.CachePolicy(
            self, "DrmCachePolicy",
            cache_policy_name=f"DRM-Cache-Policy-{self.unique_suffix}",
            comment="Cache policy optimized for DRM-protected content",
            default_ttl=Duration.seconds(5),
            min_ttl=Duration.seconds(0),
            max_ttl=Duration.days(1),
            cookie_behavior=cloudfront.CacheCookieBehavior.none(),
            header_behavior=cloudfront.CacheHeaderBehavior.allow_list(
                "Authorization",
                "CloudFront-Viewer-Country"
            ),
            query_string_behavior=cloudfront.CacheQueryStringBehavior.all(),
            enable_accept_encoding_gzip=False,
            enable_accept_encoding_brotli=False
        )
        
        # Create origin request policy
        origin_request_policy = cloudfront.OriginRequestPolicy(
            self, "DrmOriginRequestPolicy",
            origin_request_policy_name=f"DRM-Origin-Policy-{self.unique_suffix}",
            comment="Origin request policy for DRM endpoints",
            cookie_behavior=cloudfront.OriginRequestCookieBehavior.none(),
            header_behavior=cloudfront.OriginRequestHeaderBehavior.allow_list(
                "Access-Control-Request-Headers",
                "Access-Control-Request-Method",
                "Origin",
                "CloudFront-Viewer-Country"
            ),
            query_string_behavior=cloudfront.OriginRequestQueryStringBehavior.all()
        )
        
        # HLS origin
        hls_origin = origins.HttpOrigin(
            cdk.Fn.select(2, cdk.Fn.split("/", self.hls_endpoint.attr_url)),
            origin_path=f"/{cdk.Fn.select(3, cdk.Fn.split('/', self.hls_endpoint.attr_url)).split('/')[0]}",
            protocol_policy=cloudfront.OriginProtocolPolicy.HTTPS_ONLY,
            custom_headers={
                "X-MediaPackage-CDNIdentifier": f"drm-protected-{self.unique_suffix}"
            }
        )
        
        # DASH origin
        dash_origin = origins.HttpOrigin(
            cdk.Fn.select(2, cdk.Fn.split("/", self.dash_endpoint.attr_url)),
            origin_path=f"/{cdk.Fn.select(3, cdk.Fn.split('/', self.dash_endpoint.attr_url)).split('/')[0]}",
            protocol_policy=cloudfront.OriginProtocolPolicy.HTTPS_ONLY,
            custom_headers={
                "X-MediaPackage-CDNIdentifier": f"drm-protected-{self.unique_suffix}"
            }
        )
        
        # Create CloudFront distribution
        distribution = cloudfront.Distribution(
            self, "DrmDistribution",
            comment="DRM-protected content distribution with geo-restrictions",
            default_behavior=cloudfront.BehaviorOptions(
                origin=hls_origin,
                viewer_protocol_policy=cloudfront.ViewerProtocolPolicy.HTTPS_ONLY,
                cache_policy=cache_policy,
                origin_request_policy=origin_request_policy,
                allowed_methods=cloudfront.AllowedMethods.ALLOW_ALL,
                cached_methods=cloudfront.CachedMethods.CACHE_GET_HEAD,
                compress=False
            ),
            additional_behaviors={
                "*.mpd": cloudfront.BehaviorOptions(
                    origin=dash_origin,
                    viewer_protocol_policy=cloudfront.ViewerProtocolPolicy.HTTPS_ONLY,
                    cache_policy=cloudfront.CachePolicy(
                        self, "DashManifestCachePolicy",
                        cache_policy_name=f"DASH-Manifest-Policy-{self.unique_suffix}",
                        default_ttl=Duration.seconds(5),
                        min_ttl=Duration.seconds(0),
                        max_ttl=Duration.seconds(60),
                        cookie_behavior=cloudfront.CacheCookieBehavior.none(),
                        header_behavior=cloudfront.CacheHeaderBehavior.none(),
                        query_string_behavior=cloudfront.CacheQueryStringBehavior.all()
                    ),
                    origin_request_policy=origin_request_policy,
                    allowed_methods=cloudfront.AllowedMethods.ALLOW_GET_HEAD,
                    cached_methods=cloudfront.CachedMethods.CACHE_GET_HEAD,
                    compress=False
                ),
                "*/license/*": cloudfront.BehaviorOptions(
                    origin=hls_origin,
                    viewer_protocol_policy=cloudfront.ViewerProtocolPolicy.HTTPS_ONLY,
                    cache_policy=cloudfront.CachePolicy.CACHING_DISABLED,
                    origin_request_policy=origin_request_policy,
                    allowed_methods=cloudfront.AllowedMethods.ALLOW_ALL,
                    cached_methods=cloudfront.CachedMethods.CACHE_GET_HEAD,
                    compress=False
                )
            },
            geo_restriction=cloudfront.GeoRestriction.blacklist("CN", "RU"),
            price_class=cloudfront.PriceClass.PRICE_CLASS_ALL,
            minimum_protocol_version=cloudfront.SecurityPolicyProtocol.TLS_V1_2_2021,
            http_version=cloudfront.HttpVersion.HTTP2,
            enable_ipv6=True,
            enable_logging=True,
            log_bucket=s3.Bucket(
                self, "CloudFrontLogBucket",
                removal_policy=RemovalPolicy.DESTROY,
                auto_delete_objects=True
            ),
            log_file_prefix="drm-access-logs/"
        )
        
        return distribution

    def _create_outputs(self) -> None:
        """Create CloudFormation stack outputs."""
        
        # MediaLive input endpoints
        CfnOutput(
            self, "MediaLiveInputId",
            description="MediaLive input ID for RTMP streaming",
            value=self.medialive_input.ref
        )
        
        # SPEKE endpoint
        CfnOutput(
            self, "SpekeEndpointUrl",
            description="SPEKE API endpoint URL for key management",
            value=self.speke_lambda.function_url.url
        )
        
        # MediaPackage endpoints
        CfnOutput(
            self, "HlsDrmEndpoint",
            description="HLS DRM-protected streaming endpoint",
            value=self.hls_endpoint.attr_url
        )
        
        CfnOutput(
            self, "DashDrmEndpoint",
            description="DASH DRM-protected streaming endpoint",
            value=self.dash_endpoint.attr_url
        )
        
        # CloudFront distribution
        CfnOutput(
            self, "CloudFrontDomain",
            description="CloudFront distribution domain for global content delivery",
            value=self.cloudfront_distribution.distribution_domain_name
        )
        
        CfnOutput(
            self, "CloudFrontDistributionId",
            description="CloudFront distribution ID",
            value=self.cloudfront_distribution.distribution_id
        )
        
        # Protected streaming URLs
        CfnOutput(
            self, "ProtectedHlsUrl",
            description="Protected HLS streaming URL via CloudFront",
            value=f"https://{self.cloudfront_distribution.distribution_domain_name}/out/v1/index.m3u8"
        )
        
        CfnOutput(
            self, "ProtectedDashUrl",
            description="Protected DASH streaming URL via CloudFront",
            value=f"https://{self.cloudfront_distribution.distribution_domain_name}/out/v1/index.mpd"
        )
        
        # DRM infrastructure
        CfnOutput(
            self, "DrmKmsKeyId",
            description="KMS key ID for DRM content encryption",
            value=self.drm_kms_key.key_id
        )
        
        CfnOutput(
            self, "DrmSecretArn",
            description="Secrets Manager ARN for DRM configuration",
            value=self.drm_secret.secret_arn
        )
        
        # MediaLive channel
        CfnOutput(
            self, "MediaLiveChannelId",
            description="MediaLive channel ID for DRM-protected streaming",
            value=self.medialive_channel.ref
        )
        
        # Test content bucket
        CfnOutput(
            self, "TestContentBucket",
            description="S3 bucket for test content and player",
            value=self.content_bucket.bucket_name
        )

    def _add_stack_tags(self) -> None:
        """Add tags to all resources in the stack."""
        Tags.of(self).add("Project", "DRM-Protected-Video-Streaming")
        Tags.of(self).add("Environment", "Production")
        Tags.of(self).add("Service", "MediaLive-MediaPackage-DRM")
        Tags.of(self).add("Owner", "AWS-CDK")
        Tags.of(self).add("CostCenter", "Media-Services")
        Tags.of(self).add("Compliance", "DRM-Protected")


# CDK Application
app = cdk.App()

# Create the DRM-protected video streaming stack
drm_stack = DrmProtectedVideoStreamingStack(
    app, 
    "DrmProtectedVideoStreamingStack",
    description="Complete DRM-protected video streaming solution with MediaLive, MediaPackage, and CloudFront",
    env=cdk.Environment(
        account=app.node.try_get_context("account"),
        region=app.node.try_get_context("region")
    )
)

app.synth()