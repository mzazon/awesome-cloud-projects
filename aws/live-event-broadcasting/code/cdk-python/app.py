#!/usr/bin/env python3
"""
CDK Python Application for Live Event Broadcasting with AWS Elemental MediaConnect

This application deploys a complete live event broadcasting solution using:
- AWS Elemental MediaConnect for reliable video transport
- AWS Elemental MediaLive for video encoding
- AWS Elemental MediaPackage for content distribution
- CloudWatch for monitoring and alerting

Architecture:
- Dual MediaConnect flows for redundancy (primary/backup)
- MediaLive channel with automatic failover
- MediaPackage for HLS distribution
- CloudWatch monitoring and alarms
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    CfnOutput,
    Tags,
    aws_iam as iam,
    aws_mediaconnect as mediaconnect,
    aws_medialive as medialive,
    aws_mediapackage as mediapackage,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
)
from constructs import Construct


class LiveEventBroadcastingStack(Stack):
    """
    CDK Stack for Live Event Broadcasting with AWS Elemental MediaConnect
    
    This stack creates a complete live broadcasting pipeline with:
    - Redundant MediaConnect flows for video transport
    - MediaLive channel for encoding with automatic failover
    - MediaPackage for content distribution
    - Comprehensive monitoring and alerting
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        environment_name: str = "production",
        flow_name_prefix: str = "live-event",
        enable_detailed_monitoring: bool = True,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Store configuration parameters
        self.environment_name = environment_name
        self.flow_name_prefix = flow_name_prefix
        self.enable_detailed_monitoring = enable_detailed_monitoring

        # Create unique resource names
        self.resource_suffix = construct_id.lower().replace("-", "")[:8]
        
        # Create IAM role for MediaLive
        self.medialive_role = self._create_medialive_role()
        
        # Create MediaConnect flows
        self.primary_flow = self._create_primary_mediaconnect_flow()
        self.backup_flow = self._create_backup_mediaconnect_flow()
        
        # Create MediaPackage channel
        self.mediapackage_channel = self._create_mediapackage_channel()
        self.hls_endpoint = self._create_hls_endpoint()
        
        # Create MediaLive inputs
        self.primary_input = self._create_medialive_input(
            "primary", self.primary_flow
        )
        self.backup_input = self._create_medialive_input(
            "backup", self.backup_flow
        )
        
        # Create MediaLive channel
        self.medialive_channel = self._create_medialive_channel()
        
        # Create monitoring resources
        if self.enable_detailed_monitoring:
            self._create_monitoring_resources()
        
        # Create outputs
        self._create_outputs()
        
        # Add tags to all resources
        self._add_tags()

    def _create_medialive_role(self) -> iam.Role:
        """Create IAM role for MediaLive with necessary permissions"""
        role = iam.Role(
            self,
            "MediaLiveRole",
            role_name=f"MediaLiveAccessRole-{self.resource_suffix}",
            assumed_by=iam.ServicePrincipal("medialive.amazonaws.com"),
            description="IAM role for MediaLive to access MediaConnect and MediaPackage",
        )

        # Attach necessary policies
        role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name("MediaLiveFullAccess")
        )
        role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name("MediaConnectFullAccess")
        )
        role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name("MediaPackageFullAccess")
        )

        return role

    def _create_primary_mediaconnect_flow(self) -> mediaconnect.CfnFlow:
        """Create primary MediaConnect flow for main video transport"""
        flow = mediaconnect.CfnFlow(
            self,
            "PrimaryFlow",
            name=f"{self.flow_name_prefix}-primary-{self.resource_suffix}",
            availability_zone=f"{self.region}a",
            source=mediaconnect.CfnFlow.SourceProperty(
                name="PrimarySource",
                protocol="rtp",
                ingest_port=5000,
                whitelist_cidr="0.0.0.0/0",
                description="Primary encoder input for live event broadcasting",
            ),
        )

        # Add output for MediaLive
        mediaconnect.CfnFlowOutput(
            self,
            "PrimaryFlowOutput",
            flow_arn=flow.attr_flow_arn,
            name="MediaLiveOutput",
            protocol="rtp-fec",
            destination="0.0.0.0",
            port=5002,
            description="Output to MediaLive primary input",
        )

        return flow

    def _create_backup_mediaconnect_flow(self) -> mediaconnect.CfnFlow:
        """Create backup MediaConnect flow for redundant video transport"""
        flow = mediaconnect.CfnFlow(
            self,
            "BackupFlow",
            name=f"{self.flow_name_prefix}-backup-{self.resource_suffix}",
            availability_zone=f"{self.region}b",
            source=mediaconnect.CfnFlow.SourceProperty(
                name="BackupSource",
                protocol="rtp",
                ingest_port=5001,
                whitelist_cidr="0.0.0.0/0",
                description="Backup encoder input for live event broadcasting",
            ),
        )

        # Add output for MediaLive
        mediaconnect.CfnFlowOutput(
            self,
            "BackupFlowOutput",
            flow_arn=flow.attr_flow_arn,
            name="MediaLiveOutput",
            protocol="rtp-fec",
            destination="0.0.0.0",
            port=5003,
            description="Output to MediaLive backup input",
        )

        return flow

    def _create_mediapackage_channel(self) -> mediapackage.CfnChannel:
        """Create MediaPackage channel for content distribution"""
        channel = mediapackage.CfnChannel(
            self,
            "MediaPackageChannel",
            id=f"{self.flow_name_prefix}-package-{self.resource_suffix}",
            description="MediaPackage channel for live event broadcasting",
        )

        return channel

    def _create_hls_endpoint(self) -> mediapackage.CfnOriginEndpoint:
        """Create HLS origin endpoint for content delivery"""
        endpoint = mediapackage.CfnOriginEndpoint(
            self,
            "HLSEndpoint",
            channel_id=self.mediapackage_channel.id,
            id=f"{self.mediapackage_channel.id}-hls",
            description="HLS endpoint for live event broadcasting",
            hls_package=mediapackage.CfnOriginEndpoint.HlsPackageProperty(
                ad_markers="NONE",
                include_iframe_only_stream=False,
                playlist_type="EVENT",
                playlist_window_seconds=60,
                program_date_time_interval_seconds=0,
                segment_duration_seconds=6,
                stream_selection=mediapackage.CfnOriginEndpoint.StreamSelectionProperty(
                    max_video_bits_per_second=2147483647,
                    min_video_bits_per_second=0,
                    stream_order="ORIGINAL",
                ),
            ),
        )

        return endpoint

    def _create_medialive_input(
        self, input_type: str, flow: mediaconnect.CfnFlow
    ) -> medialive.CfnInput:
        """Create MediaLive input for MediaConnect flow"""
        input_resource = medialive.CfnInput(
            self,
            f"{input_type.title()}Input",
            name=f"{self.flow_name_prefix}-{input_type}-input-{self.resource_suffix}",
            type="MEDIACONNECT",
            media_connect_flows=[
                medialive.CfnInput.MediaConnectFlowRequestProperty(
                    flow_arn=flow.attr_flow_arn
                )
            ],
            role_arn=self.medialive_role.role_arn,
        )

        return input_resource

    def _create_medialive_channel(self) -> medialive.CfnChannel:
        """Create MediaLive channel with dual inputs and MediaPackage output"""
        channel = medialive.CfnChannel(
            self,
            "MediaLiveChannel",
            name=f"{self.flow_name_prefix}-channel-{self.resource_suffix}",
            role_arn=self.medialive_role.role_arn,
            input_specification=medialive.CfnChannel.InputSpecificationProperty(
                codec="AVC",
                resolution="HD",
                maximum_bitrate="MAX_10_MBPS",
            ),
            input_attachments=[
                medialive.CfnChannel.InputAttachmentProperty(
                    input_attachment_name="primary-input",
                    input_id=self.primary_input.ref,
                    input_settings=medialive.CfnChannel.InputSettingsProperty(
                        audio_selectors=[
                            medialive.CfnChannel.AudioSelectorProperty(
                                name="default",
                                selector_settings=medialive.CfnChannel.AudioSelectorSettingsProperty(
                                    audio_pid_selection=medialive.CfnChannel.AudioPidSelectionProperty(
                                        pid=256
                                    )
                                ),
                            )
                        ],
                        video_selector=medialive.CfnChannel.VideoSelectorProperty(
                            program_id=1
                        ),
                    ),
                ),
                medialive.CfnChannel.InputAttachmentProperty(
                    input_attachment_name="backup-input",
                    input_id=self.backup_input.ref,
                    input_settings=medialive.CfnChannel.InputSettingsProperty(
                        audio_selectors=[
                            medialive.CfnChannel.AudioSelectorProperty(
                                name="default",
                                selector_settings=medialive.CfnChannel.AudioSelectorSettingsProperty(
                                    audio_pid_selection=medialive.CfnChannel.AudioPidSelectionProperty(
                                        pid=256
                                    )
                                ),
                            )
                        ],
                        video_selector=medialive.CfnChannel.VideoSelectorProperty(
                            program_id=1
                        ),
                    ),
                ),
            ],
            destinations=[
                medialive.CfnChannel.OutputDestinationProperty(
                    id="mediapackage-destination",
                    media_package_settings=[
                        medialive.CfnChannel.MediaPackageOutputDestinationSettingsProperty(
                            channel_id=self.mediapackage_channel.id
                        )
                    ],
                )
            ],
            encoder_settings=self._get_encoder_settings(),
        )

        return channel

    def _get_encoder_settings(self) -> medialive.CfnChannel.EncoderSettingsProperty:
        """Get encoder settings for MediaLive channel"""
        return medialive.CfnChannel.EncoderSettingsProperty(
            audio_descriptions=[
                medialive.CfnChannel.AudioDescriptionProperty(
                    audio_selector_name="default",
                    codec_settings=medialive.CfnChannel.AudioCodecSettingsProperty(
                        aac_settings=medialive.CfnChannel.AacSettingsProperty(
                            bitrate=128000,
                            coding_mode="CODING_MODE_2_0",
                            input_type="BROADCASTER_MIXED_AD",
                            profile="LC",
                            sample_rate=48000,
                        )
                    ),
                    name="audio_1",
                )
            ],
            video_descriptions=[
                medialive.CfnChannel.VideoDescriptionProperty(
                    codec_settings=medialive.CfnChannel.VideoCodecSettingsProperty(
                        h264_settings=medialive.CfnChannel.H264SettingsProperty(
                            bitrate=2000000,
                            framerate_control="SPECIFIED",
                            framerate_denominator=1,
                            framerate_numerator=30,
                            gop_b_reference="DISABLED",
                            gop_closed_cadence=1,
                            gop_num_b_frames=2,
                            gop_size=90,
                            gop_size_units="FRAMES",
                            level="H264_LEVEL_4_1",
                            look_ahead_rate_control="MEDIUM",
                            max_bitrate=2000000,
                            num_ref_frames=3,
                            par_control="INITIALIZE_FROM_SOURCE",
                            profile="MAIN",
                            rate_control_mode="CBR",
                            syntax="DEFAULT",
                        )
                    ),
                    height=720,
                    name="video_720p30",
                    respond_to_afd="NONE",
                    sharpness=50,
                    width=1280,
                )
            ],
            output_groups=[
                medialive.CfnChannel.OutputGroupProperty(
                    name="mediapackage-output-group",
                    output_group_settings=medialive.CfnChannel.OutputGroupSettingsProperty(
                        media_package_group_settings=medialive.CfnChannel.MediaPackageGroupSettingsProperty(
                            destination=medialive.CfnChannel.OutputLocationRefProperty(
                                destination_ref_id="mediapackage-destination"
                            )
                        )
                    ),
                    outputs=[
                        medialive.CfnChannel.OutputProperty(
                            audio_description_names=["audio_1"],
                            output_name="720p30",
                            output_settings=medialive.CfnChannel.OutputSettingsProperty(
                                media_package_output_settings=medialive.CfnChannel.MediaPackageOutputSettingsProperty()
                            ),
                            video_description_name="video_720p30",
                        )
                    ],
                )
            ],
        )

    def _create_monitoring_resources(self) -> None:
        """Create CloudWatch monitoring and alerting resources"""
        # Create log groups for MediaConnect flows
        logs.LogGroup(
            self,
            "PrimaryFlowLogGroup",
            log_group_name=f"/aws/mediaconnect/{self.primary_flow.name}",
            retention=logs.RetentionDays.ONE_WEEK,
        )

        logs.LogGroup(
            self,
            "BackupFlowLogGroup",
            log_group_name=f"/aws/mediaconnect/{self.backup_flow.name}",
            retention=logs.RetentionDays.ONE_WEEK,
        )

        # Create CloudWatch alarms
        cloudwatch.Alarm(
            self,
            "PrimaryFlowSourceErrors",
            alarm_name=f"{self.primary_flow.name}-source-errors",
            alarm_description="Alert on MediaConnect primary flow source errors",
            metric=cloudwatch.Metric(
                namespace="AWS/MediaConnect",
                metric_name="SourceConnectionErrors",
                dimensions_map={"FlowName": self.primary_flow.name},
                statistic="Sum",
                period=cdk.Duration.minutes(5),
            ),
            threshold=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
            evaluation_periods=1,
        )

        cloudwatch.Alarm(
            self,
            "MediaLiveInputErrors",
            alarm_name=f"{self.medialive_channel.name}-input-errors",
            alarm_description="Alert on MediaLive channel input errors",
            metric=cloudwatch.Metric(
                namespace="AWS/MediaLive",
                metric_name="InputVideoFrameRate",
                dimensions_map={"ChannelId": self.medialive_channel.ref},
                statistic="Average",
                period=cdk.Duration.minutes(5),
            ),
            threshold=1,
            comparison_operator=cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
            evaluation_periods=2,
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources"""
        CfnOutput(
            self,
            "PrimaryFlowArn",
            value=self.primary_flow.attr_flow_arn,
            description="ARN of the primary MediaConnect flow",
        )

        CfnOutput(
            self,
            "BackupFlowArn",
            value=self.backup_flow.attr_flow_arn,
            description="ARN of the backup MediaConnect flow",
        )

        CfnOutput(
            self,
            "MediaLiveChannelId",
            value=self.medialive_channel.ref,
            description="ID of the MediaLive channel",
        )

        CfnOutput(
            self,
            "MediaPackageChannelId",
            value=self.mediapackage_channel.id,
            description="ID of the MediaPackage channel",
        )

        CfnOutput(
            self,
            "HLSEndpointUrl",
            value=self.hls_endpoint.attr_url,
            description="URL of the HLS endpoint for content delivery",
        )

        CfnOutput(
            self,
            "PrimaryIngestEndpoint",
            value=f"{self.primary_flow.attr_source_ingest_ip}:5000",
            description="Primary encoder ingest endpoint",
        )

        CfnOutput(
            self,
            "BackupIngestEndpoint",
            value=f"{self.backup_flow.attr_source_ingest_ip}:5001",
            description="Backup encoder ingest endpoint",
        )

    def _add_tags(self) -> None:
        """Add tags to all resources in the stack"""
        Tags.of(self).add("Environment", self.environment_name)
        Tags.of(self).add("Application", "LiveEventBroadcasting")
        Tags.of(self).add("Stack", self.stack_name)
        Tags.of(self).add("MonitoringLevel", "Detailed" if self.enable_detailed_monitoring else "Basic")


class LiveEventBroadcastingApp(cdk.App):
    """CDK Application for Live Event Broadcasting"""

    def __init__(self) -> None:
        super().__init__()

        # Get environment configuration
        env_config = self._get_environment_config()

        # Create the main stack
        LiveEventBroadcastingStack(
            self,
            "LiveEventBroadcastingStack",
            env=env_config["env"],
            environment_name=env_config["environment_name"],
            flow_name_prefix=env_config["flow_name_prefix"],
            enable_detailed_monitoring=env_config["enable_detailed_monitoring"],
            description="Live Event Broadcasting infrastructure with AWS Elemental MediaConnect",
        )

    def _get_environment_config(self) -> Dict[str, Any]:
        """Get environment configuration from context or environment variables"""
        return {
            "env": Environment(
                account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
                region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
            ),
            "environment_name": self.node.try_get_context("environment") or "production",
            "flow_name_prefix": self.node.try_get_context("flow_name_prefix") or "live-event",
            "enable_detailed_monitoring": self.node.try_get_context("enable_detailed_monitoring") != "false",
        }


# Entry point for the CDK application
if __name__ == "__main__":
    app = LiveEventBroadcastingApp()
    app.synth()