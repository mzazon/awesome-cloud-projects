#!/usr/bin/env python3
"""
AWS CDK Python application for Live Streaming Solutions with AWS Elemental MediaLive.

This application creates a complete live streaming infrastructure including:
- MediaLive input and channel for video encoding
- MediaPackage for content packaging and delivery
- CloudFront for global content distribution
- S3 bucket for archive storage
- IAM roles and CloudWatch monitoring
"""

import os
from typing import Dict, Any, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    aws_s3 as s3,
    aws_iam as iam,
    aws_medialive as medialive,
    aws_mediapackage as mediapackage,
    aws_cloudfront as cloudfront,
    aws_cloudfront_origins as origins,
    aws_cloudwatch as cloudwatch,
    aws_sns as sns,
    aws_logs as logs,
    CfnOutput,
    Tags,
)
from constructs import Construct


class LiveStreamingStack(Stack):
    """
    CDK Stack for Live Streaming Solutions with AWS Elemental MediaLive.
    
    This stack creates a complete live streaming infrastructure that can handle
    high-quality video streaming with adaptive bitrate encoding, global distribution,
    and comprehensive monitoring.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        stream_name: str = "live-stream",
        channel_name: str = "live-channel",
        **kwargs: Any,
    ) -> None:
        """
        Initialize the Live Streaming Stack.
        
        Args:
            scope: The parent construct
            construct_id: The construct identifier
            stream_name: Name for the streaming resources
            channel_name: Name for the MediaLive channel
            **kwargs: Additional keyword arguments
        """
        super().__init__(scope, construct_id, **kwargs)

        # Store configuration
        self.stream_name = stream_name
        self.channel_name = channel_name
        self.package_channel_name = f"package-{channel_name}"

        # Create core infrastructure
        self._create_s3_bucket()
        self._create_iam_roles()
        self._create_medialive_resources()
        self._create_mediapackage_resources()
        self._create_cloudfront_distribution()
        self._create_monitoring_resources()
        self._create_outputs()

        # Add tags to all resources
        self._add_tags()

    def _create_s3_bucket(self) -> None:
        """Create S3 bucket for archive storage and test player hosting."""
        self.archive_bucket = s3.Bucket(
            self,
            "ArchiveBucket",
            bucket_name=f"{self.stream_name}-archive-{self.account}",
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            website_index_document="test-player.html",
            public_read_access=True,
            block_public_access=s3.BlockPublicAccess(
                block_public_acls=False,
                block_public_policy=False,
                ignore_public_acls=False,
                restrict_public_buckets=False,
            ),
            cors=[
                s3.CorsRule(
                    allowed_headers=["*"],
                    allowed_methods=[s3.HttpMethods.GET, s3.HttpMethods.HEAD],
                    allowed_origins=["*"],
                    max_age=3600,
                )
            ],
            versioned=False,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteOldObjects",
                    enabled=True,
                    expiration=Duration.days(30),
                    abort_incomplete_multipart_upload_after=Duration.days(7),
                )
            ],
        )

    def _create_iam_roles(self) -> None:
        """Create IAM roles for MediaLive service."""
        # MediaLive service role
        self.medialive_role = iam.Role(
            self,
            "MediaLiveRole",
            role_name=f"MediaLiveAccessRole-{self.stream_name}",
            assumed_by=iam.ServicePrincipal("medialive.amazonaws.com"),
            description="IAM role for MediaLive to access other AWS services",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("MediaLiveFullAccess"),
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonS3ReadOnlyAccess"),
            ],
        )

        # Add inline policy for MediaPackage and CloudWatch access
        self.medialive_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "mediapackage:*",
                    "cloudwatch:PutMetricData",
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents",
                    "logs:DescribeLogStreams",
                    "logs:DescribeLogGroups",
                ],
                resources=["*"],
            )
        )

        # Add S3 write permissions for archive
        self.medialive_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["s3:PutObject", "s3:PutObjectAcl"],
                resources=[f"{self.archive_bucket.bucket_arn}/*"],
            )
        )

    def _create_medialive_resources(self) -> None:
        """Create MediaLive input security group, input, and channel."""
        # Create input security group
        self.input_security_group = medialive.CfnInputSecurityGroup(
            self,
            "InputSecurityGroup",
            whitelist_rules=[
                medialive.CfnInputSecurityGroup.InputWhitelistRuleCidrProperty(
                    cidr="0.0.0.0/0"
                )
            ],
            tags={"Name": f"{self.stream_name}-input-sg"},
        )

        # Create MediaLive input
        self.medialive_input = medialive.CfnInput(
            self,
            "MediaLiveInput",
            name=f"{self.stream_name}-input",
            type="RTMP_PUSH",
            input_security_groups=[self.input_security_group.ref],
            tags={"Name": f"{self.stream_name}-input"},
        )

        # Create MediaLive channel
        self.medialive_channel = medialive.CfnChannel(
            self,
            "MediaLiveChannel",
            name=self.channel_name,
            role_arn=self.medialive_role.role_arn,
            input_specification=medialive.CfnChannel.InputSpecificationProperty(
                codec="AVC",
                resolution="HD",
                maximum_bitrate="MAX_10_MBPS",
            ),
            input_attachments=[
                medialive.CfnChannel.InputAttachmentProperty(
                    input_id=self.medialive_input.ref,
                    input_attachment_name="primary-input",
                    input_settings=medialive.CfnChannel.InputSettingsProperty(
                        source_end_behavior="CONTINUE"
                    ),
                )
            ],
            destinations=[
                medialive.CfnChannel.OutputDestinationProperty(
                    id="destination1",
                    media_package_settings=[
                        medialive.CfnChannel.MediaPackageOutputDestinationSettingsProperty(
                            channel_id=self.package_channel_name
                        )
                    ],
                )
            ],
            encoder_settings=self._create_encoder_settings(),
            tags={"Name": self.channel_name},
        )

        # Add dependency
        self.medialive_channel.add_depends_on(self.medialive_input)

    def _create_encoder_settings(self) -> medialive.CfnChannel.EncoderSettingsProperty:
        """Create encoder settings for adaptive bitrate streaming."""
        return medialive.CfnChannel.EncoderSettingsProperty(
            audio_descriptions=[
                medialive.CfnChannel.AudioDescriptionProperty(
                    name="audio_1",
                    audio_selector_name="default",
                    codec_settings=medialive.CfnChannel.AudioCodecSettingsProperty(
                        aac_settings=medialive.CfnChannel.AacSettingsProperty(
                            bitrate=96000,
                            coding_mode="CODING_MODE_2_0",
                            sample_rate=48000,
                        )
                    ),
                )
            ],
            video_descriptions=[
                # 1080p video description
                medialive.CfnChannel.VideoDescriptionProperty(
                    name="video_1080p",
                    codec_settings=medialive.CfnChannel.VideoCodecSettingsProperty(
                        h264_settings=medialive.CfnChannel.H264SettingsProperty(
                            bitrate=6000000,
                            framerate_control="SPECIFIED",
                            framerate_numerator=30,
                            framerate_denominator=1,
                            gop_b_reference="DISABLED",
                            gop_closed_cadence=1,
                            gop_num_b_frames=2,
                            gop_size=90,
                            gop_size_units="FRAMES",
                            profile="MAIN",
                            rate_control_mode="CBR",
                            syntax="DEFAULT",
                        )
                    ),
                    width=1920,
                    height=1080,
                    respond_to_afd="NONE",
                    sharpness=50,
                    scaling_behavior="DEFAULT",
                ),
                # 720p video description
                medialive.CfnChannel.VideoDescriptionProperty(
                    name="video_720p",
                    codec_settings=medialive.CfnChannel.VideoCodecSettingsProperty(
                        h264_settings=medialive.CfnChannel.H264SettingsProperty(
                            bitrate=3000000,
                            framerate_control="SPECIFIED",
                            framerate_numerator=30,
                            framerate_denominator=1,
                            gop_b_reference="DISABLED",
                            gop_closed_cadence=1,
                            gop_num_b_frames=2,
                            gop_size=90,
                            gop_size_units="FRAMES",
                            profile="MAIN",
                            rate_control_mode="CBR",
                            syntax="DEFAULT",
                        )
                    ),
                    width=1280,
                    height=720,
                    respond_to_afd="NONE",
                    sharpness=50,
                    scaling_behavior="DEFAULT",
                ),
                # 480p video description
                medialive.CfnChannel.VideoDescriptionProperty(
                    name="video_480p",
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
                            rate_control_mode="CBR",
                            syntax="DEFAULT",
                        )
                    ),
                    width=854,
                    height=480,
                    respond_to_afd="NONE",
                    sharpness=50,
                    scaling_behavior="DEFAULT",
                ),
            ],
            output_groups=[
                medialive.CfnChannel.OutputGroupProperty(
                    name="MediaPackage",
                    output_group_settings=medialive.CfnChannel.OutputGroupSettingsProperty(
                        media_package_group_settings=medialive.CfnChannel.MediaPackageGroupSettingsProperty(
                            destination=medialive.CfnChannel.OutputLocationRefProperty(
                                destination_ref_id="destination1"
                            )
                        )
                    ),
                    outputs=[
                        medialive.CfnChannel.OutputProperty(
                            output_name="1080p",
                            video_description_name="video_1080p",
                            audio_description_names=["audio_1"],
                            output_settings=medialive.CfnChannel.OutputSettingsProperty(
                                media_package_output_settings=medialive.CfnChannel.MediaPackageOutputSettingsProperty()
                            ),
                        ),
                        medialive.CfnChannel.OutputProperty(
                            output_name="720p",
                            video_description_name="video_720p",
                            audio_description_names=["audio_1"],
                            output_settings=medialive.CfnChannel.OutputSettingsProperty(
                                media_package_output_settings=medialive.CfnChannel.MediaPackageOutputSettingsProperty()
                            ),
                        ),
                        medialive.CfnChannel.OutputProperty(
                            output_name="480p",
                            video_description_name="video_480p",
                            audio_description_names=["audio_1"],
                            output_settings=medialive.CfnChannel.OutputSettingsProperty(
                                media_package_output_settings=medialive.CfnChannel.MediaPackageOutputSettingsProperty()
                            ),
                        ),
                    ],
                )
            ],
            timecode_config=medialive.CfnChannel.TimecodeConfigProperty(source="EMBEDDED"),
        )

    def _create_mediapackage_resources(self) -> None:
        """Create MediaPackage channel and origin endpoints."""
        # Create MediaPackage channel
        self.mediapackage_channel = mediapackage.CfnChannel(
            self,
            "MediaPackageChannel",
            id=self.package_channel_name,
            description="Live streaming package channel",
            tags=[
                cdk.CfnTag(key="Name", value=self.package_channel_name),
                cdk.CfnTag(key="Purpose", value="LiveStreaming"),
            ],
        )

        # Create HLS origin endpoint
        self.hls_endpoint = mediapackage.CfnOriginEndpoint(
            self,
            "HLSOriginEndpoint",
            channel_id=self.mediapackage_channel.id,
            id=f"{self.package_channel_name}-hls",
            manifest_name="index.m3u8",
            hls_package=mediapackage.CfnOriginEndpoint.HlsPackageProperty(
                segment_duration_seconds=6,
                playlist_window_seconds=60,
                playlist_type="EVENT",
                ad_markers="NONE",
                include_iframe_only_stream=False,
                program_date_time_interval_seconds=0,
                use_audio_rendition_group=False,
            ),
            description="HLS streaming endpoint",
            tags=[
                cdk.CfnTag(key="Name", value=f"{self.package_channel_name}-hls"),
                cdk.CfnTag(key="Protocol", value="HLS"),
            ],
        )

        # Create DASH origin endpoint
        self.dash_endpoint = mediapackage.CfnOriginEndpoint(
            self,
            "DASHOriginEndpoint",
            channel_id=self.mediapackage_channel.id,
            id=f"{self.package_channel_name}-dash",
            manifest_name="index.mpd",
            dash_package=mediapackage.CfnOriginEndpoint.DashPackageProperty(
                segment_duration_seconds=6,
                min_buffer_time_seconds=30,
                min_update_period_seconds=15,
                suggested_presentation_delay_seconds=25,
                profile="NONE",
                ad_triggers=["SPLICE_INSERT"],
                ads_on_delivery_restrictions="NONE",
            ),
            description="DASH streaming endpoint",
            tags=[
                cdk.CfnTag(key="Name", value=f"{self.package_channel_name}-dash"),
                cdk.CfnTag(key="Protocol", value="DASH"),
            ],
        )

        # Add dependencies
        self.hls_endpoint.add_depends_on(self.mediapackage_channel)
        self.dash_endpoint.add_depends_on(self.mediapackage_channel)

    def _create_cloudfront_distribution(self) -> None:
        """Create CloudFront distribution for global content delivery."""
        # Create CloudFront distribution
        self.cloudfront_distribution = cloudfront.Distribution(
            self,
            "CloudFrontDistribution",
            comment="Live streaming distribution",
            default_behavior=cloudfront.BehaviorOptions(
                origin=origins.HttpOrigin(
                    domain_name=cdk.Fn.select(
                        2, cdk.Fn.split("/", self.hls_endpoint.attr_url)
                    ),
                    origin_path=f"/{cdk.Fn.select(3, cdk.Fn.split('/', self.hls_endpoint.attr_url))}",
                    protocol_policy=cloudfront.OriginProtocolPolicy.HTTPS_ONLY,
                ),
                viewer_protocol_policy=cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
                cache_policy=cloudfront.CachePolicy.CACHING_OPTIMIZED_FOR_UNCOMPRESSED_OBJECTS,
                origin_request_policy=cloudfront.OriginRequestPolicy.CORS_S3_ORIGIN,
                compress=False,
                allowed_methods=cloudfront.AllowedMethods.ALLOW_GET_HEAD,
                cached_methods=cloudfront.CachedMethods.CACHE_GET_HEAD,
            ),
            additional_behaviors={
                "*.mpd": cloudfront.BehaviorOptions(
                    origin=origins.HttpOrigin(
                        domain_name=cdk.Fn.select(
                            2, cdk.Fn.split("/", self.dash_endpoint.attr_url)
                        ),
                        origin_path=f"/{cdk.Fn.select(3, cdk.Fn.split('/', self.dash_endpoint.attr_url))}",
                        protocol_policy=cloudfront.OriginProtocolPolicy.HTTPS_ONLY,
                    ),
                    viewer_protocol_policy=cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
                    cache_policy=cloudfront.CachePolicy.CACHING_OPTIMIZED_FOR_UNCOMPRESSED_OBJECTS,
                    origin_request_policy=cloudfront.OriginRequestPolicy.CORS_S3_ORIGIN,
                    compress=False,
                    allowed_methods=cloudfront.AllowedMethods.ALLOW_GET_HEAD,
                    cached_methods=cloudfront.CachedMethods.CACHE_GET_HEAD,
                )
            },
            price_class=cloudfront.PriceClass.PRICE_CLASS_ALL,
            enabled=True,
            http_version=cloudfront.HttpVersion.HTTP2,
            minimum_protocol_version=cloudfront.SecurityPolicyProtocol.TLS_V1_2_2021,
        )

    def _create_monitoring_resources(self) -> None:
        """Create CloudWatch monitoring and SNS notifications."""
        # Create SNS topic for alerts
        self.alert_topic = sns.Topic(
            self,
            "MediaLiveAlerts",
            topic_name=f"medialive-alerts-{self.stream_name}",
            display_name="MediaLive Alert Notifications",
        )

        # Create CloudWatch alarms for MediaLive channel
        self.error_alarm = cloudwatch.Alarm(
            self,
            "MediaLiveErrorAlarm",
            alarm_name=f"MediaLive-{self.channel_name}-Errors",
            alarm_description="MediaLive channel error alarm",
            metric=cloudwatch.Metric(
                namespace="AWS/MediaLive",
                metric_name="4xxErrors",
                dimensions_map={"ChannelId": self.medialive_channel.ref},
                statistic="Sum",
                period=Duration.minutes(5),
            ),
            threshold=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
            evaluation_periods=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

        self.input_freeze_alarm = cloudwatch.Alarm(
            self,
            "MediaLiveInputFreezeAlarm",
            alarm_name=f"MediaLive-{self.channel_name}-InputVideoFreeze",
            alarm_description="MediaLive input video freeze alarm",
            metric=cloudwatch.Metric(
                namespace="AWS/MediaLive",
                metric_name="InputVideoFreeze",
                dimensions_map={"ChannelId": self.medialive_channel.ref},
                statistic="Maximum",
                period=Duration.minutes(5),
            ),
            threshold=0.5,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=1,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

        # Add SNS actions to alarms
        self.error_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.alert_topic)
        )
        self.input_freeze_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.alert_topic)
        )

        # Create CloudWatch log group for MediaLive
        self.log_group = logs.LogGroup(
            self,
            "MediaLiveLogGroup",
            log_group_name=f"/aws/medialive/{self.channel_name}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY,
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information."""
        # MediaLive input information
        CfnOutput(
            self,
            "MediaLiveInputId",
            value=self.medialive_input.ref,
            description="MediaLive Input ID",
        )

        CfnOutput(
            self,
            "MediaLiveChannelId",
            value=self.medialive_channel.ref,
            description="MediaLive Channel ID",
        )

        CfnOutput(
            self,
            "RTMPInputURL",
            value=cdk.Fn.select(0, self.medialive_input.attr_destinations),
            description="Primary RTMP Input URL",
        )

        # MediaPackage endpoints
        CfnOutput(
            self,
            "HLSEndpointURL",
            value=self.hls_endpoint.attr_url,
            description="HLS Streaming Endpoint URL",
        )

        CfnOutput(
            self,
            "DASHEndpointURL",
            value=self.dash_endpoint.attr_url,
            description="DASH Streaming Endpoint URL",
        )

        # CloudFront distribution
        CfnOutput(
            self,
            "CloudFrontDistributionDomain",
            value=self.cloudfront_distribution.distribution_domain_name,
            description="CloudFront Distribution Domain Name",
        )

        CfnOutput(
            self,
            "CloudFrontHLSURL",
            value=f"https://{self.cloudfront_distribution.distribution_domain_name}/out/v1/index.m3u8",
            description="CloudFront HLS Streaming URL",
        )

        CfnOutput(
            self,
            "CloudFrontDASHURL",
            value=f"https://{self.cloudfront_distribution.distribution_domain_name}/out/v1/index.mpd",
            description="CloudFront DASH Streaming URL",
        )

        # S3 bucket information
        CfnOutput(
            self,
            "ArchiveBucketName",
            value=self.archive_bucket.bucket_name,
            description="S3 Archive Bucket Name",
        )

        CfnOutput(
            self,
            "TestPlayerURL",
            value=f"http://{self.archive_bucket.bucket_name}.s3-website.{self.region}.amazonaws.com/",
            description="Test Player URL",
        )

        # SNS topic for alerts
        CfnOutput(
            self,
            "AlertTopicArn",
            value=self.alert_topic.topic_arn,
            description="SNS Topic ARN for MediaLive Alerts",
        )

    def _add_tags(self) -> None:
        """Add tags to all stack resources."""
        Tags.of(self).add("Project", "LiveStreaming")
        Tags.of(self).add("Environment", "Production")
        Tags.of(self).add("ManagedBy", "CDK")
        Tags.of(self).add("StreamName", self.stream_name)
        Tags.of(self).add("ChannelName", self.channel_name)


class LiveStreamingApp(cdk.App):
    """CDK Application for Live Streaming Solutions."""

    def __init__(self) -> None:
        """Initialize the CDK application."""
        super().__init__()

        # Get configuration from environment variables or use defaults
        stream_name = os.getenv("STREAM_NAME", "live-stream")
        channel_name = os.getenv("CHANNEL_NAME", "live-channel")
        environment = os.getenv("ENVIRONMENT", "production")

        # Create the stack
        LiveStreamingStack(
            self,
            "LiveStreamingStack",
            stream_name=stream_name,
            channel_name=channel_name,
            env=cdk.Environment(
                account=os.getenv("CDK_DEFAULT_ACCOUNT"),
                region=os.getenv("CDK_DEFAULT_REGION", "us-east-1"),
            ),
            description=f"Live Streaming Solutions with AWS Elemental MediaLive - {environment}",
        )


# Create and run the application
if __name__ == "__main__":
    app = LiveStreamingApp()
    app.synth()