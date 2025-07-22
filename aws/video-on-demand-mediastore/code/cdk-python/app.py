#!/usr/bin/env python3
"""
AWS CDK Python application for Video-on-Demand Platform with MediaStore.

This application creates a complete video-on-demand platform using:
- AWS Elemental MediaStore for optimized video origin storage
- CloudFront for global content delivery
- IAM roles for secure access
- CloudWatch monitoring and alarms

Note: AWS Elemental MediaStore support will end on November 13, 2025.
Consider migrating to S3 with CloudFront for new implementations.
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    CfnOutput,
    RemovalPolicy,
    Duration,
    aws_mediastore as mediastore,
    aws_cloudfront as cloudfront,
    aws_cloudfront_origins as origins,
    aws_iam as iam,
    aws_s3 as s3,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
)
from constructs import Construct


class VodPlatformStack(Stack):
    """
    CDK Stack for Video-on-Demand Platform with AWS Elemental MediaStore.
    
    This stack creates a complete VOD platform including:
    - MediaStore container for video origin storage
    - CloudFront distribution for global content delivery
    - IAM roles and security policies
    - CloudWatch monitoring and alarms
    - S3 staging bucket for content upload
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        unique_suffix = self.node.try_get_context("unique_suffix") or "dev"
        
        # Create S3 staging bucket for content upload
        self.staging_bucket = self._create_staging_bucket(unique_suffix)
        
        # Create MediaStore container
        self.mediastore_container = self._create_mediastore_container(unique_suffix)
        
        # Configure container security and CORS policies
        self._configure_container_policies()
        
        # Configure lifecycle management
        self._configure_lifecycle_policy()
        
        # Create IAM role for MediaStore access
        self.mediastore_role = self._create_iam_role(unique_suffix)
        
        # Create CloudFront distribution
        self.cloudfront_distribution = self._create_cloudfront_distribution(unique_suffix)
        
        # Enable monitoring and metrics
        self._setup_monitoring(unique_suffix)
        
        # Create outputs
        self._create_outputs()

    def _create_staging_bucket(self, unique_suffix: str) -> s3.Bucket:
        """Create S3 staging bucket for content upload."""
        bucket = s3.Bucket(
            self,
            "StagingBucket",
            bucket_name=f"vod-staging-{unique_suffix}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )
        
        # Add bucket notification for future processing workflows
        bucket.add_cors_rule(
            allowed_methods=[s3.HttpMethods.GET, s3.HttpMethods.PUT, s3.HttpMethods.POST],
            allowed_origins=["*"],
            allowed_headers=["*"],
            max_age=3000,
        )
        
        return bucket

    def _create_mediastore_container(self, unique_suffix: str) -> mediastore.CfnContainer:
        """Create MediaStore container for video origin storage."""
        container = mediastore.CfnContainer(
            self,
            "MediaStoreContainer",
            container_name=f"vod-platform-{unique_suffix}",
            access_logging_enabled=True,
        )
        
        # Enable metrics for monitoring
        container.add_property_override("MetricPolicy", {
            "ContainerLevelMetrics": "ENABLED",
            "MetricPolicyRules": [
                {
                    "ObjectGroup": "/*",
                    "ObjectGroupName": "AllObjects"
                }
            ]
        })
        
        return container

    def _configure_container_policies(self) -> None:
        """Configure MediaStore container security and CORS policies."""
        # Container policy for secure access
        container_policy = {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Sid": "MediaStoreFullAccess",
                    "Effect": "Allow",
                    "Principal": "*",
                    "Action": [
                        "mediastore:GetObject",
                        "mediastore:DescribeObject"
                    ],
                    "Resource": "*",
                    "Condition": {
                        "Bool": {
                            "aws:SecureTransport": "true"
                        }
                    }
                },
                {
                    "Sid": "MediaStoreUploadAccess",
                    "Effect": "Allow",
                    "Principal": {
                        "AWS": f"arn:aws:iam::{self.account}:root"
                    },
                    "Action": [
                        "mediastore:PutObject",
                        "mediastore:DeleteObject"
                    ],
                    "Resource": "*"
                }
            ]
        }
        
        # Apply container policy
        mediastore.CfnContainerPolicy(
            self,
            "ContainerPolicy",
            container_name=self.mediastore_container.container_name,
            policy=container_policy,
        )
        
        # CORS policy for web applications
        cors_policy = [
            {
                "AllowedOrigins": ["*"],
                "AllowedMethods": ["GET", "HEAD"],
                "AllowedHeaders": ["*"],
                "MaxAgeSeconds": 3000,
                "ExposeHeaders": ["Date", "Server"]
            }
        ]
        
        # Apply CORS policy
        mediastore.CfnContainer(
            self,
            "ContainerCORSPolicy",
            container_name=self.mediastore_container.container_name,
        ).add_property_override("CorsPolicy", cors_policy)

    def _configure_lifecycle_policy(self) -> None:
        """Configure lifecycle management for automatic content cleanup."""
        lifecycle_policy = {
            "Rules": [
                {
                    "ObjectGroup": "/videos/temp/*",
                    "ObjectGroupName": "TempVideos",
                    "Lifecycle": {
                        "TransitionToIA": "AFTER_30_DAYS",
                        "ExpirationInDays": 90
                    }
                },
                {
                    "ObjectGroup": "/videos/archive/*",
                    "ObjectGroupName": "ArchiveVideos",
                    "Lifecycle": {
                        "TransitionToIA": "AFTER_7_DAYS",
                        "ExpirationInDays": 365
                    }
                }
            ]
        }
        
        # Note: Lifecycle policy would be applied via custom resource or manually
        # as CDK doesn't directly support MediaStore lifecycle policies
        
    def _create_iam_role(self, unique_suffix: str) -> iam.Role:
        """Create IAM role for MediaStore access."""
        role = iam.Role(
            self,
            "MediaStoreAccessRole",
            role_name=f"MediaStoreAccessRole-{unique_suffix}",
            assumed_by=iam.ServicePrincipal("mediastore.amazonaws.com"),
            description="IAM role for MediaStore container access",
        )
        
        # Add MediaStore access policy
        mediastore_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "mediastore:GetObject",
                "mediastore:PutObject",
                "mediastore:DeleteObject",
                "mediastore:DescribeObject",
                "mediastore:ListItems"
            ],
            resources=["*"]
        )
        
        role.add_to_policy(mediastore_policy)
        
        return role

    def _create_cloudfront_distribution(self, unique_suffix: str) -> cloudfront.Distribution:
        """Create CloudFront distribution for global content delivery."""
        # Create origin from MediaStore endpoint
        mediastore_origin = origins.HttpOrigin(
            domain_name=self.mediastore_container.attr_endpoint.replace("https://", ""),
            protocol_policy=cloudfront.OriginProtocolPolicy.HTTPS_ONLY,
            origin_ssl_protocols=[cloudfront.OriginSslPolicy.TLS_V1_2],
            custom_headers={
                "User-Agent": f"VOD-Platform-{unique_suffix}"
            }
        )
        
        # Create CloudFront distribution
        distribution = cloudfront.Distribution(
            self,
            "CloudFrontDistribution",
            comment=f"VOD Platform Distribution - {unique_suffix}",
            default_behavior=cloudfront.BehaviorOptions(
                origin=mediastore_origin,
                viewer_protocol_policy=cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
                cache_policy=cloudfront.CachePolicy.CACHING_OPTIMIZED,
                origin_request_policy=cloudfront.OriginRequestPolicy.CORS_S3_ORIGIN,
                compress=True,
                allowed_methods=cloudfront.AllowedMethods.ALLOW_GET_HEAD,
                cached_methods=cloudfront.CachedMethods.CACHE_GET_HEAD,
            ),
            additional_behaviors={
                "/videos/*": cloudfront.BehaviorOptions(
                    origin=mediastore_origin,
                    viewer_protocol_policy=cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
                    cache_policy=cloudfront.CachePolicy.CACHING_OPTIMIZED_FOR_UNCOMPRESSED_OBJECTS,
                    compress=True,
                    allowed_methods=cloudfront.AllowedMethods.ALLOW_GET_HEAD,
                    cached_methods=cloudfront.CachedMethods.CACHE_GET_HEAD,
                )
            },
            price_class=cloudfront.PriceClass.PRICE_CLASS_ALL,
            enabled=True,
        )
        
        return distribution

    def _setup_monitoring(self, unique_suffix: str) -> None:
        """Set up CloudWatch monitoring and alarms."""
        # Create CloudWatch alarm for high request rate
        high_request_alarm = cloudwatch.Alarm(
            self,
            "HighRequestRateAlarm",
            alarm_name=f"MediaStore-HighRequestRate-{unique_suffix}",
            alarm_description="High request rate on MediaStore container",
            metric=cloudwatch.Metric(
                namespace="AWS/MediaStore",
                metric_name="RequestCount",
                dimensions_map={
                    "ContainerName": self.mediastore_container.container_name
                },
                statistic="Sum",
                period=Duration.minutes(5),
            ),
            threshold=1000,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        )
        
        # Create CloudWatch alarm for error rate
        error_rate_alarm = cloudwatch.Alarm(
            self,
            "ErrorRateAlarm",
            alarm_name=f"MediaStore-ErrorRate-{unique_suffix}",
            alarm_description="High error rate on MediaStore container",
            metric=cloudwatch.Metric(
                namespace="AWS/MediaStore",
                metric_name="4xxErrorRate",
                dimensions_map={
                    "ContainerName": self.mediastore_container.container_name
                },
                statistic="Average",
                period=Duration.minutes(5),
            ),
            threshold=5,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        )
        
        # Create CloudWatch dashboard
        dashboard = cloudwatch.Dashboard(
            self,
            "VODPlatformDashboard",
            dashboard_name=f"VOD-Platform-{unique_suffix}",
        )
        
        # Add metrics widgets to dashboard
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="MediaStore Request Count",
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/MediaStore",
                        metric_name="RequestCount",
                        dimensions_map={
                            "ContainerName": self.mediastore_container.container_name
                        },
                        statistic="Sum",
                        period=Duration.minutes(5),
                    )
                ],
                width=12,
                height=6,
            )
        )
        
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="CloudFront Cache Hit Rate",
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/CloudFront",
                        metric_name="CacheHitRate",
                        dimensions_map={
                            "DistributionId": self.cloudfront_distribution.distribution_id
                        },
                        statistic="Average",
                        period=Duration.minutes(5),
                    )
                ],
                width=12,
                height=6,
            )
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        CfnOutput(
            self,
            "MediaStoreContainerName",
            value=self.mediastore_container.container_name,
            description="MediaStore container name for video storage",
        )
        
        CfnOutput(
            self,
            "MediaStoreEndpoint",
            value=self.mediastore_container.attr_endpoint,
            description="MediaStore container endpoint for direct access",
        )
        
        CfnOutput(
            self,
            "CloudFrontDomainName",
            value=self.cloudfront_distribution.distribution_domain_name,
            description="CloudFront distribution domain name",
        )
        
        CfnOutput(
            self,
            "CloudFrontDistributionId",
            value=self.cloudfront_distribution.distribution_id,
            description="CloudFront distribution ID",
        )
        
        CfnOutput(
            self,
            "StagingBucketName",
            value=self.staging_bucket.bucket_name,
            description="S3 staging bucket for content upload",
        )
        
        CfnOutput(
            self,
            "IAMRoleArn",
            value=self.mediastore_role.role_arn,
            description="IAM role ARN for MediaStore access",
        )
        
        CfnOutput(
            self,
            "VideoPlayerURL",
            value=f"https://{self.cloudfront_distribution.distribution_domain_name}/videos/",
            description="Base URL for video content access via CloudFront",
        )


class VodPlatformApp(cdk.App):
    """CDK Application for Video-on-Demand Platform."""
    
    def __init__(self) -> None:
        super().__init__()
        
        # Get configuration from context or environment
        env = cdk.Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
        )
        
        # Create the main stack
        VodPlatformStack(
            self,
            "VodPlatformStack",
            env=env,
            description="Video-on-Demand Platform with AWS Elemental MediaStore and CloudFront",
            tags={
                "Project": "VOD-Platform",
                "Environment": self.node.try_get_context("environment") or "dev",
                "Owner": "CDK-Deploy",
                "CostCenter": "Media-Services"
            }
        )


# Create and run the application
app = VodPlatformApp()
app.synth()