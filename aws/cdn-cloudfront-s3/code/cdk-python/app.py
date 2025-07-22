#!/usr/bin/env python3
"""
CDK Python application for Content Delivery Networks with CloudFront S3.

This application creates a complete CDN solution with:
- S3 bucket for content storage
- S3 bucket for CloudFront access logs
- CloudFront distribution with Origin Access Control
- CloudWatch alarms for monitoring
- Custom cache behaviors for different content types
"""

import os
from aws_cdk import (
    App,
    Environment,
    Stack,
    StackProps,
    CfnOutput,
    RemovalPolicy,
    Duration,
    aws_s3 as s3,
    aws_cloudfront as cloudfront,
    aws_cloudfront_origins as origins,
    aws_cloudwatch as cloudwatch,
    aws_iam as iam,
)
from constructs import Construct
from typing import Dict, List, Optional


class ContentDeliveryNetworkStack(Stack):
    """
    CDK Stack for implementing a Content Delivery Network with CloudFront and S3.
    
    This stack creates a complete CDN solution with proper security, monitoring,
    and performance optimization for global content delivery.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        content_bucket_name: Optional[str] = None,
        logs_bucket_name: Optional[str] = None,
        enable_logging: bool = True,
        enable_monitoring: bool = True,
        price_class: str = "PriceClass_100",
        **kwargs
    ) -> None:
        """
        Initialize the CDN stack.
        
        Args:
            scope: The parent construct
            construct_id: The construct ID
            content_bucket_name: Optional custom name for content bucket
            logs_bucket_name: Optional custom name for logs bucket
            enable_logging: Whether to enable CloudFront logging
            enable_monitoring: Whether to create CloudWatch alarms
            price_class: CloudFront price class (PriceClass_100, PriceClass_200, PriceClass_All)
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resources
        unique_suffix = self.node.addr[:8].lower()
        
        # Create S3 bucket for content storage
        self.content_bucket = self._create_content_bucket(
            content_bucket_name or f"cdn-content-{unique_suffix}"
        )
        
        # Create S3 bucket for CloudFront logs (if logging enabled)
        self.logs_bucket = None
        if enable_logging:
            self.logs_bucket = self._create_logs_bucket(
                logs_bucket_name or f"cdn-logs-{unique_suffix}"
            )
        
        # Create Origin Access Control for secure S3 access
        self.origin_access_control = self._create_origin_access_control()
        
        # Create CloudFront distribution
        self.distribution = self._create_cloudfront_distribution(
            price_class=price_class,
            enable_logging=enable_logging
        )
        
        # Configure S3 bucket policy for OAC access
        self._configure_bucket_policy()
        
        # Create CloudWatch alarms (if monitoring enabled)
        if enable_monitoring:
            self._create_cloudwatch_alarms()
        
        # Create stack outputs
        self._create_outputs()

    def _create_content_bucket(self, bucket_name: str) -> s3.Bucket:
        """
        Create S3 bucket for content storage with security best practices.
        
        Args:
            bucket_name: Name for the S3 bucket
            
        Returns:
            S3 bucket for content storage
        """
        bucket = s3.Bucket(
            self,
            "ContentBucket",
            bucket_name=bucket_name,
            # Block all public access - content will be served through CloudFront
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            # Enable versioning for content management
            versioned=True,
            # Enable server-side encryption
            encryption=s3.BucketEncryption.S3_MANAGED,
            # Configure lifecycle rules for cost optimization
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteIncompleteMultipartUploads",
                    abort_incomplete_multipart_uploads_after=Duration.days(1),
                    enabled=True,
                ),
                s3.LifecycleRule(
                    id="TransitionToIA",
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30),
                        ),
                    ],
                    enabled=True,
                ),
            ],
            # Configure for production use - change to DESTROY for development
            removal_policy=RemovalPolicy.RETAIN,
        )
        
        return bucket

    def _create_logs_bucket(self, bucket_name: str) -> s3.Bucket:
        """
        Create S3 bucket for CloudFront access logs.
        
        Args:
            bucket_name: Name for the logs bucket
            
        Returns:
            S3 bucket for CloudFront logs
        """
        logs_bucket = s3.Bucket(
            self,
            "LogsBucket",
            bucket_name=bucket_name,
            # Block public access to logs
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            # Enable server-side encryption for logs
            encryption=s3.BucketEncryption.S3_MANAGED,
            # Configure lifecycle rules for log retention
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteOldLogs",
                    expiration=Duration.days(90),
                    enabled=True,
                ),
                s3.LifecycleRule(
                    id="TransitionLogsToIA",
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30),
                        ),
                    ],
                    enabled=True,
                ),
            ],
            # Logs can be destroyed for cost optimization
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        return logs_bucket

    def _create_origin_access_control(self) -> cloudfront.CfnOriginAccessControl:
        """
        Create Origin Access Control for secure S3 access.
        
        Returns:
            CloudFront Origin Access Control resource
        """
        oac = cloudfront.CfnOriginAccessControl(
            self,
            "OriginAccessControl",
            origin_access_control_config=cloudfront.CfnOriginAccessControl.OriginAccessControlConfigProperty(
                name=f"CDN-OAC-{self.node.addr[:8]}",
                description="Origin Access Control for CDN content bucket",
                origin_access_control_origin_type="s3",
                signing_behavior="always",
                signing_protocol="sigv4",
            ),
        )
        
        return oac

    def _create_cloudfront_distribution(
        self,
        price_class: str,
        enable_logging: bool
    ) -> cloudfront.Distribution:
        """
        Create CloudFront distribution with optimized cache behaviors.
        
        Args:
            price_class: CloudFront price class for edge location selection
            enable_logging: Whether to enable access logging
            
        Returns:
            CloudFront distribution
        """
        # Convert price class string to enum
        price_class_map = {
            "PriceClass_100": cloudfront.PriceClass.PRICE_CLASS_100,
            "PriceClass_200": cloudfront.PriceClass.PRICE_CLASS_200,
            "PriceClass_All": cloudfront.PriceClass.PRICE_CLASS_ALL,
        }
        
        # Create S3 origin
        origin = origins.S3Origin(
            self.content_bucket,
            # OAC will be configured separately due to CDK limitations
        )
        
        # Define cache behaviors for different content types
        cache_behaviors = {
            # CSS files - long cache duration for static assets
            "*.css": cloudfront.BehaviorOptions(
                origin=origin,
                viewer_protocol_policy=cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
                cache_policy=cloudfront.CachePolicy.CACHING_OPTIMIZED,
                compress=True,
                allowed_methods=cloudfront.AllowedMethods.ALLOW_GET_HEAD,
            ),
            # JavaScript files - long cache duration for static assets
            "*.js": cloudfront.BehaviorOptions(
                origin=origin,
                viewer_protocol_policy=cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
                cache_policy=cloudfront.CachePolicy.CACHING_OPTIMIZED,
                compress=True,
                allowed_methods=cloudfront.AllowedMethods.ALLOW_GET_HEAD,
            ),
            # Images - very long cache duration
            "*.jpg": cloudfront.BehaviorOptions(
                origin=origin,
                viewer_protocol_policy=cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
                cache_policy=cloudfront.CachePolicy.CACHING_OPTIMIZED,
                compress=True,
                allowed_methods=cloudfront.AllowedMethods.ALLOW_GET_HEAD,
            ),
            "*.png": cloudfront.BehaviorOptions(
                origin=origin,
                viewer_protocol_policy=cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
                cache_policy=cloudfront.CachePolicy.CACHING_OPTIMIZED,
                compress=True,
                allowed_methods=cloudfront.AllowedMethods.ALLOW_GET_HEAD,
            ),
            # API endpoints - shorter cache duration
            "api/*": cloudfront.BehaviorOptions(
                origin=origin,
                viewer_protocol_policy=cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
                cache_policy=cloudfront.CachePolicy.CACHING_DISABLED,
                compress=True,
                allowed_methods=cloudfront.AllowedMethods.ALLOW_GET_HEAD,
            ),
        }
        
        # Create custom error responses
        error_responses = [
            cloudfront.ErrorResponse(
                http_status=404,
                response_http_status=200,
                response_page_path="/index.html",
                ttl=Duration.minutes(5),
            ),
            cloudfront.ErrorResponse(
                http_status=403,
                response_http_status=200,
                response_page_path="/index.html",
                ttl=Duration.minutes(5),
            ),
        ]
        
        # Create distribution
        distribution = cloudfront.Distribution(
            self,
            "CDNDistribution",
            comment="CDN for global content delivery",
            default_root_object="index.html",
            default_behavior=cloudfront.BehaviorOptions(
                origin=origin,
                viewer_protocol_policy=cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
                cache_policy=cloudfront.CachePolicy.CACHING_OPTIMIZED,
                compress=True,
                allowed_methods=cloudfront.AllowedMethods.ALLOW_GET_HEAD,
            ),
            additional_behaviors=cache_behaviors,
            error_responses=error_responses,
            price_class=price_class_map.get(price_class, cloudfront.PriceClass.PRICE_CLASS_100),
            enable_ipv6=True,
            http_version=cloudfront.HttpVersion.HTTP2,
            minimum_protocol_version=cloudfront.SecurityPolicyProtocol.TLS_V1_2_2021,
            enable_logging=enable_logging,
            log_bucket=self.logs_bucket if enable_logging else None,
            log_file_prefix="cloudfront-logs/" if enable_logging else None,
            log_includes_cookies=False,
        )
        
        return distribution

    def _configure_bucket_policy(self) -> None:
        """
        Configure S3 bucket policy to allow CloudFront Origin Access Control access.
        """
        # Create bucket policy statement for OAC access
        policy_statement = iam.PolicyStatement(
            sid="AllowCloudFrontServicePrincipal",
            effect=iam.Effect.ALLOW,
            principals=[iam.ServicePrincipal("cloudfront.amazonaws.com")],
            actions=["s3:GetObject"],
            resources=[f"{self.content_bucket.bucket_arn}/*"],
            conditions={
                "StringEquals": {
                    "AWS:SourceArn": f"arn:aws:cloudfront::{self.account}:distribution/{self.distribution.distribution_id}"
                }
            },
        )
        
        # Add policy to bucket
        self.content_bucket.add_to_resource_policy(policy_statement)

    def _create_cloudwatch_alarms(self) -> None:
        """
        Create CloudWatch alarms for monitoring CloudFront performance.
        """
        # High error rate alarm
        cloudwatch.Alarm(
            self,
            "HighErrorRateAlarm",
            alarm_name=f"CloudFront-HighErrorRate-{self.distribution.distribution_id}",
            alarm_description="High error rate for CloudFront distribution",
            metric=cloudwatch.Metric(
                namespace="AWS/CloudFront",
                metric_name="4xxErrorRate",
                dimensions_map={
                    "DistributionId": self.distribution.distribution_id,
                },
                statistic="Average",
                period=Duration.minutes(5),
            ),
            threshold=5.0,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )
        
        # High origin latency alarm
        cloudwatch.Alarm(
            self,
            "HighOriginLatencyAlarm",
            alarm_name=f"CloudFront-HighOriginLatency-{self.distribution.distribution_id}",
            alarm_description="High origin latency for CloudFront distribution",
            metric=cloudwatch.Metric(
                namespace="AWS/CloudFront",
                metric_name="OriginLatency",
                dimensions_map={
                    "DistributionId": self.distribution.distribution_id,
                },
                statistic="Average",
                period=Duration.minutes(5),
            ),
            threshold=1000.0,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )
        
        # Low cache hit rate alarm
        cloudwatch.Alarm(
            self,
            "LowCacheHitRateAlarm",
            alarm_name=f"CloudFront-LowCacheHitRate-{self.distribution.distribution_id}",
            alarm_description="Low cache hit rate for CloudFront distribution",
            metric=cloudwatch.Metric(
                namespace="AWS/CloudFront",
                metric_name="CacheHitRate",
                dimensions_map={
                    "DistributionId": self.distribution.distribution_id,
                },
                statistic="Average",
                period=Duration.minutes(15),
            ),
            threshold=80.0,
            evaluation_periods=3,
            comparison_operator=cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

    def _create_outputs(self) -> None:
        """
        Create CloudFormation outputs for important resource information.
        """
        CfnOutput(
            self,
            "ContentBucketName",
            value=self.content_bucket.bucket_name,
            description="Name of the S3 bucket for content storage",
            export_name=f"{self.stack_name}-ContentBucket",
        )
        
        if self.logs_bucket:
            CfnOutput(
                self,
                "LogsBucketName",
                value=self.logs_bucket.bucket_name,
                description="Name of the S3 bucket for CloudFront logs",
                export_name=f"{self.stack_name}-LogsBucket",
            )
        
        CfnOutput(
            self,
            "DistributionId",
            value=self.distribution.distribution_id,
            description="CloudFront distribution ID",
            export_name=f"{self.stack_name}-DistributionId",
        )
        
        CfnOutput(
            self,
            "DistributionDomainName",
            value=self.distribution.distribution_domain_name,
            description="CloudFront distribution domain name",
            export_name=f"{self.stack_name}-DistributionDomain",
        )
        
        CfnOutput(
            self,
            "DistributionURL",
            value=f"https://{self.distribution.distribution_domain_name}",
            description="CloudFront distribution URL",
            export_name=f"{self.stack_name}-DistributionURL",
        )
        
        CfnOutput(
            self,
            "OriginAccessControlId",
            value=self.origin_access_control.attr_id,
            description="Origin Access Control ID",
            export_name=f"{self.stack_name}-OACId",
        )


def main() -> None:
    """
    Main application entry point.
    """
    app = App()
    
    # Get environment configuration
    account = os.environ.get("CDK_DEFAULT_ACCOUNT")
    region = os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
    
    # Create environment
    env = Environment(account=account, region=region)
    
    # Get configuration from context or environment variables
    content_bucket_name = app.node.try_get_context("contentBucketName")
    logs_bucket_name = app.node.try_get_context("logsBucketName")
    enable_logging = app.node.try_get_context("enableLogging") != "false"
    enable_monitoring = app.node.try_get_context("enableMonitoring") != "false"
    price_class = app.node.try_get_context("priceClass") or "PriceClass_100"
    
    # Create the CDN stack
    ContentDeliveryNetworkStack(
        app,
        "ContentDeliveryNetworkStack",
        env=env,
        content_bucket_name=content_bucket_name,
        logs_bucket_name=logs_bucket_name,
        enable_logging=enable_logging,
        enable_monitoring=enable_monitoring,
        price_class=price_class,
        description="Content Delivery Network with CloudFront and S3",
        tags={
            "Project": "CDN-Implementation",
            "Environment": os.environ.get("ENVIRONMENT", "development"),
            "Owner": "CDK-Python",
        },
    )
    
    app.synth()


if __name__ == "__main__":
    main()