#!/usr/bin/env python3
"""
AWS CDK Python application for CloudFront CDN with Origin Access Controls.

This application creates a complete content delivery network using Amazon CloudFront
with Origin Access Control (OAC) for secure S3 access, AWS WAF for security,
and comprehensive monitoring.

Author: AWS CDK Recipe Generator
Version: 1.0
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_s3 as s3,
    aws_s3_deployment as s3_deployment,
    aws_cloudfront as cloudfront,
    aws_cloudfront_origins as origins,
    aws_wafv2 as wafv2,
    aws_cloudwatch as cloudwatch,
    aws_iam as iam,
    aws_certificatemanager as acm,
)
from constructs import Construct


class CloudFrontCdnStack(Stack):
    """
    AWS CDK Stack for CloudFront CDN with Origin Access Controls.
    
    This stack creates:
    - S3 buckets for content storage and logging
    - CloudFront distribution with OAC
    - WAF Web ACL for security
    - CloudWatch alarms for monitoring
    - Sample content deployment
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        domain_name: str = None,
        certificate_arn: str = None,
        enable_waf: bool = True,
        price_class: cloudfront.PriceClass = cloudfront.PriceClass.PRICE_CLASS_ALL,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Store configuration parameters
        self.domain_name = domain_name
        self.certificate_arn = certificate_arn
        self.enable_waf = enable_waf
        self.price_class = price_class

        # Create unique suffix for resource names
        self.unique_suffix = construct_id.lower()

        # Create S3 buckets
        self.content_bucket = self._create_content_bucket()
        self.logs_bucket = self._create_logs_bucket()

        # Deploy sample content
        self._deploy_sample_content()

        # Create WAF Web ACL if enabled
        self.web_acl = None
        if self.enable_waf:
            self.web_acl = self._create_waf_web_acl()

        # Create CloudFront distribution
        self.distribution = self._create_cloudfront_distribution()

        # Create monitoring alarms
        self._create_monitoring_alarms()

        # Create stack outputs
        self._create_outputs()

    def _create_content_bucket(self) -> s3.Bucket:
        """
        Create S3 bucket for content storage with security best practices.
        
        Returns:
            s3.Bucket: The created content bucket
        """
        bucket = s3.Bucket(
            self,
            "ContentBucket",
            bucket_name=f"cdn-content-{self.unique_suffix}",
            # Security configurations
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            encryption=s3.BucketEncryption.S3_MANAGED,
            enforce_ssl=True,
            # Lifecycle configurations
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            # Versioning for content management
            versioned=True,
            # CORS configuration for web access
            cors=[
                s3.CorsRule(
                    allowed_headers=["*"],
                    allowed_methods=[
                        s3.HttpMethods.GET,
                        s3.HttpMethods.HEAD,
                    ],
                    allowed_origins=["*"],
                    max_age=3600,
                )
            ],
        )

        # Add bucket notification for monitoring (optional)
        # This can be extended for real-time content updates
        
        return bucket

    def _create_logs_bucket(self) -> s3.Bucket:
        """
        Create S3 bucket for CloudFront access logs.
        
        Returns:
            s3.Bucket: The created logs bucket
        """
        bucket = s3.Bucket(
            self,
            "LogsBucket",
            bucket_name=f"cdn-logs-{self.unique_suffix}",
            # Security configurations
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            encryption=s3.BucketEncryption.S3_MANAGED,
            enforce_ssl=True,
            # Lifecycle configurations
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            # Lifecycle rule for log management
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteOldLogs",
                    enabled=True,
                    expiration=Duration.days(90),
                    # Transition to cheaper storage classes
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.STANDARD_INFREQUENT_ACCESS,
                            transition_after=Duration.days(30),
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(60),
                        ),
                    ],
                )
            ],
        )

        return bucket

    def _deploy_sample_content(self) -> None:
        """
        Deploy sample content to the S3 bucket for testing.
        """
        # Create sample content deployment
        s3_deployment.BucketDeployment(
            self,
            "SampleContentDeployment",
            sources=[
                # You can replace this with actual content sources
                s3_deployment.Source.data(
                    "index.html",
                    """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>CDN Test Page</title>
    <link rel="stylesheet" href="/css/styles.css">
</head>
<body>
    <div class="container">
        <h1>CloudFront CDN Test</h1>
        <p>This page is served through Amazon CloudFront with Origin Access Control.</p>
        <img src="/images/aws-logo.png" alt="AWS Logo" class="logo">
        <div class="features">
            <h2>Features Implemented:</h2>
            <ul>
                <li>✅ Global Content Delivery Network</li>
                <li>✅ Origin Access Control (OAC)</li>
                <li>✅ AWS WAF Security Protection</li>
                <li>✅ CloudWatch Monitoring</li>
                <li>✅ HTTPS Encryption</li>
                <li>✅ Optimized Caching</li>
            </ul>
        </div>
    </div>
    <script src="/js/main.js"></script>
</body>
</html>""",
                ),
                s3_deployment.Source.data(
                    "css/styles.css",
                    """/* CDN Test Styles */
body {
    font-family: 'Amazon Ember', Arial, sans-serif;
    margin: 0;
    padding: 40px;
    background: linear-gradient(135deg, #232F3E 0%, #37475A 100%);
    color: #ffffff;
    line-height: 1.6;
}

.container {
    max-width: 800px;
    margin: 0 auto;
    padding: 40px;
    background: rgba(255, 255, 255, 0.1);
    border-radius: 12px;
    backdrop-filter: blur(10px);
    box-shadow: 0 8px 32px rgba(0, 0, 0, 0.3);
}

h1 {
    color: #FF9900;
    text-align: center;
    margin-bottom: 30px;
    font-size: 2.5em;
    text-shadow: 2px 2px 4px rgba(0, 0, 0, 0.5);
}

h2 {
    color: #FF9900;
    border-bottom: 2px solid #FF9900;
    padding-bottom: 10px;
}

.logo {
    display: block;
    margin: 30px auto;
    max-width: 200px;
    height: auto;
}

.features {
    background: rgba(255, 255, 255, 0.05);
    padding: 30px;
    border-radius: 8px;
    margin-top: 30px;
}

ul {
    list-style: none;
    padding: 0;
}

li {
    padding: 10px 0;
    font-size: 1.1em;
}

/* Responsive design */
@media (max-width: 768px) {
    body {
        padding: 20px;
    }
    
    .container {
        padding: 20px;
    }
    
    h1 {
        font-size: 2em;
    }
}""",
                ),
                s3_deployment.Source.data(
                    "js/main.js",
                    """// CDN Test JavaScript
console.log('CloudFront CDN assets loaded successfully!');

// Display cache information if available
if (performance && performance.getEntriesByType) {
    const resources = performance.getEntriesByType('resource');
    console.log('Loaded resources:', resources.length);
    
    // Log cache hits for debugging
    resources.forEach(resource => {
        if (resource.name.includes('.css') || resource.name.includes('.js')) {
            console.log(`Resource: ${resource.name}, Duration: ${resource.duration}ms`);
        }
    });
}

// Simple feature to test JavaScript execution
document.addEventListener('DOMContentLoaded', function() {
    const container = document.querySelector('.container');
    if (container) {
        // Add a subtle animation
        container.style.opacity = '0';
        container.style.transform = 'translateY(20px)';
        container.style.transition = 'all 0.6s ease-out';
        
        setTimeout(() => {
            container.style.opacity = '1';
            container.style.transform = 'translateY(0)';
        }, 100);
    }
    
    // Add click tracking for analytics (example)
    document.addEventListener('click', function(e) {
        console.log('Click tracked:', e.target.tagName);
    });
});""",
                ),
                s3_deployment.Source.data(
                    "images/aws-logo.png",
                    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg=="  # 1x1 transparent PNG placeholder
                ),
            ],
            destination_bucket=self.content_bucket,
            # Cache control for different content types
            cache_control=[
                s3_deployment.CacheControl.set_public(),
                s3_deployment.CacheControl.max_age(Duration.hours(24)),
            ],
            metadata={
                "Content-Type": "text/html",
            },
        )

    def _create_waf_web_acl(self) -> wafv2.CfnWebACL:
        """
        Create AWS WAF Web ACL for CloudFront protection.
        
        Returns:
            wafv2.CfnWebACL: The created Web ACL
        """
        web_acl = wafv2.CfnWebACL(
            self,
            "CdnWebAcl",
            name=f"cdn-waf-{self.unique_suffix}",
            scope="CLOUDFRONT",
            default_action=wafv2.CfnWebACL.DefaultActionProperty(allow={}),
            rules=[
                # AWS Managed Core Rule Set
                wafv2.CfnWebACL.RuleProperty(
                    name="AWSManagedRulesCommonRuleSet",
                    priority=1,
                    override_action=wafv2.CfnWebACL.OverrideActionProperty(none={}),
                    statement=wafv2.CfnWebACL.StatementProperty(
                        managed_rule_group_statement=wafv2.CfnWebACL.ManagedRuleGroupStatementProperty(
                            vendor_name="AWS",
                            name="AWSManagedRulesCommonRuleSet",
                        )
                    ),
                    visibility_config=wafv2.CfnWebACL.VisibilityConfigProperty(
                        sampled_requests_enabled=True,
                        cloud_watch_metrics_enabled=True,
                        metric_name="CommonRuleSetMetric",
                    ),
                ),
                # AWS Managed Known Bad Inputs Rule Set
                wafv2.CfnWebACL.RuleProperty(
                    name="AWSManagedRulesKnownBadInputsRuleSet",
                    priority=2,
                    override_action=wafv2.CfnWebACL.OverrideActionProperty(none={}),
                    statement=wafv2.CfnWebACL.StatementProperty(
                        managed_rule_group_statement=wafv2.CfnWebACL.ManagedRuleGroupStatementProperty(
                            vendor_name="AWS",
                            name="AWSManagedRulesKnownBadInputsRuleSet",
                        )
                    ),
                    visibility_config=wafv2.CfnWebACL.VisibilityConfigProperty(
                        sampled_requests_enabled=True,
                        cloud_watch_metrics_enabled=True,
                        metric_name="KnownBadInputsMetric",
                    ),
                ),
                # Rate limiting rule
                wafv2.CfnWebACL.RuleProperty(
                    name="RateLimitRule",
                    priority=3,
                    action=wafv2.CfnWebACL.RuleActionProperty(block={}),
                    statement=wafv2.CfnWebACL.StatementProperty(
                        rate_based_statement=wafv2.CfnWebACL.RateBasedStatementProperty(
                            limit=2000,
                            aggregate_key_type="IP",
                        )
                    ),
                    visibility_config=wafv2.CfnWebACL.VisibilityConfigProperty(
                        sampled_requests_enabled=True,
                        cloud_watch_metrics_enabled=True,
                        metric_name="RateLimitMetric",
                    ),
                ),
            ],
            visibility_config=wafv2.CfnWebACL.VisibilityConfigProperty(
                sampled_requests_enabled=True,
                cloud_watch_metrics_enabled=True,
                metric_name="CDNWebACL",
            ),
        )

        return web_acl

    def _create_cloudfront_distribution(self) -> cloudfront.Distribution:
        """
        Create CloudFront distribution with Origin Access Control.
        
        Returns:
            cloudfront.Distribution: The created distribution
        """
        # Create Origin Access Control
        oac = cloudfront.S3OriginAccessControl(
            self,
            "OriginAccessControl",
            description=f"OAC for {self.content_bucket.bucket_name}",
        )

        # Create S3 origin
        s3_origin = origins.S3BucketOrigin(
            bucket=self.content_bucket,
            origin_access_control=oac,
        )

        # Configure certificate if provided
        viewer_certificate = None
        if self.domain_name and self.certificate_arn:
            certificate = acm.Certificate.from_certificate_arn(
                self, "Certificate", self.certificate_arn
            )
            viewer_certificate = cloudfront.ViewerCertificate.from_acm_certificate(
                certificate,
                aliases=[self.domain_name],
                security_policy=cloudfront.SecurityPolicyProtocol.TLS_V1_2_2021,
            )
        else:
            viewer_certificate = cloudfront.ViewerCertificate.from_cloudfront_default_certificate()

        # Create distribution
        distribution = cloudfront.Distribution(
            self,
            "CdnDistribution",
            default_behavior=cloudfront.BehaviorOptions(
                origin=s3_origin,
                viewer_protocol_policy=cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
                cache_policy=cloudfront.CachePolicy.CACHING_OPTIMIZED,
                origin_request_policy=cloudfront.OriginRequestPolicy.CORS_S3_ORIGIN,
                response_headers_policy=cloudfront.ResponseHeadersPolicy.SECURITY_HEADERS,
                compress=True,
            ),
            additional_behaviors={
                # Optimized caching for static assets
                "/images/*": cloudfront.BehaviorOptions(
                    origin=s3_origin,
                    viewer_protocol_policy=cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
                    cache_policy=cloudfront.CachePolicy.CACHING_OPTIMIZED,
                    compress=True,
                ),
                "/css/*": cloudfront.BehaviorOptions(
                    origin=s3_origin,
                    viewer_protocol_policy=cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
                    cache_policy=cloudfront.CachePolicy.CACHING_OPTIMIZED,
                    compress=True,
                ),
                "/js/*": cloudfront.BehaviorOptions(
                    origin=s3_origin,
                    viewer_protocol_policy=cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
                    cache_policy=cloudfront.CachePolicy.CACHING_OPTIMIZED,
                    compress=True,
                ),
            },
            # Error pages configuration
            error_responses=[
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
            ],
            # Logging configuration
            log_bucket=self.logs_bucket,
            log_file_prefix="cloudfront-logs/",
            log_includes_cookies=False,
            # Geographic restrictions (can be customized)
            geo_restriction=cloudfront.GeoRestriction.allowlist(),
            # Price class configuration
            price_class=self.price_class,
            # Enable IPv6
            enable_ipv6=True,
            # HTTP version
            http_version=cloudfront.HttpVersion.HTTP2_AND_3,
            # Default root object
            default_root_object="index.html",
            # Certificate configuration
            certificate=viewer_certificate,
            # Comment for identification
            comment=f"CDN Distribution for {self.unique_suffix}",
            # WAF Web ACL association
            web_acl_id=self.web_acl.attr_arn if self.web_acl else None,
        )

        # Grant CloudFront access to S3 bucket
        self.content_bucket.add_to_resource_policy(
            iam.PolicyStatement(
                sid="AllowCloudFrontServicePrincipalReadOnly",
                effect=iam.Effect.ALLOW,
                principals=[iam.ServicePrincipal("cloudfront.amazonaws.com")],
                actions=["s3:GetObject"],
                resources=[f"{self.content_bucket.bucket_arn}/*"],
                conditions={
                    "StringEquals": {
                        "AWS:SourceArn": f"arn:aws:cloudfront::{self.account}:distribution/{distribution.distribution_id}"
                    }
                },
            )
        )

        return distribution

    def _create_monitoring_alarms(self) -> None:
        """
        Create CloudWatch alarms for monitoring the CDN.
        """
        # Alarm for high 4xx error rate
        cloudwatch.Alarm(
            self,
            "HighErrorRateAlarm",
            alarm_name=f"CloudFront-4xx-Errors-{self.distribution.distribution_id}",
            alarm_description="High 4xx error rate for CloudFront distribution",
            metric=self.distribution.metric_4xx_error_rate(
                statistic=cloudwatch.Statistic.AVERAGE,
                period=Duration.minutes(5),
            ),
            threshold=5.0,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

        # Alarm for low cache hit rate
        cloudwatch.Alarm(
            self,
            "LowCacheHitRateAlarm",
            alarm_name=f"CloudFront-Low-Cache-Hit-Rate-{self.distribution.distribution_id}",
            alarm_description="Low cache hit rate for CloudFront distribution",
            metric=self.distribution.metric_cache_hit_rate(
                statistic=cloudwatch.Statistic.AVERAGE,
                period=Duration.minutes(5),
            ),
            threshold=80.0,
            comparison_operator=cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
            evaluation_periods=3,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

        # Alarm for high origin latency
        cloudwatch.Alarm(
            self,
            "HighOriginLatencyAlarm",
            alarm_name=f"CloudFront-High-Origin-Latency-{self.distribution.distribution_id}",
            alarm_description="High origin latency for CloudFront distribution",
            metric=self.distribution.metric_origin_latency(
                statistic=cloudwatch.Statistic.AVERAGE,
                period=Duration.minutes(5),
            ),
            threshold=3000,  # 3 seconds
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

    def _create_outputs(self) -> None:
        """
        Create CloudFormation outputs for easy access to resources.
        """
        CfnOutput(
            self,
            "ContentBucketName",
            description="Name of the S3 content bucket",
            value=self.content_bucket.bucket_name,
        )

        CfnOutput(
            self,
            "LogsBucketName",
            description="Name of the S3 logs bucket",
            value=self.logs_bucket.bucket_name,
        )

        CfnOutput(
            self,
            "DistributionId",
            description="CloudFront distribution ID",
            value=self.distribution.distribution_id,
        )

        CfnOutput(
            self,
            "DistributionDomainName",
            description="CloudFront distribution domain name",
            value=self.distribution.distribution_domain_name,
        )

        CfnOutput(
            self,
            "DistributionUrl",
            description="CloudFront distribution URL",
            value=f"https://{self.distribution.distribution_domain_name}",
        )

        if self.web_acl:
            CfnOutput(
                self,
                "WebAclArn",
                description="WAF Web ACL ARN",
                value=self.web_acl.attr_arn,
            )

        # Test URLs for different content types
        CfnOutput(
            self,
            "TestUrls",
            description="Test URLs for validating the CDN",
            value="; ".join([
                f"Main: https://{self.distribution.distribution_domain_name}",
                f"CSS: https://{self.distribution.distribution_domain_name}/css/styles.css",
                f"JS: https://{self.distribution.distribution_domain_name}/js/main.js",
                f"Image: https://{self.distribution.distribution_domain_name}/images/aws-logo.png",
            ]),
        )


class CloudFrontCdnApp(cdk.App):
    """
    CDK Application for CloudFront CDN deployment.
    """

    def __init__(self) -> None:
        super().__init__()

        # Get configuration from environment variables or context
        domain_name = self.node.try_get_context("domain_name")
        certificate_arn = self.node.try_get_context("certificate_arn")
        enable_waf = self.node.try_get_context("enable_waf") != "false"
        
        # Parse price class from context
        price_class_str = self.node.try_get_context("price_class") or "all"
        price_class_map = {
            "100": cloudfront.PriceClass.PRICE_CLASS_100,
            "200": cloudfront.PriceClass.PRICE_CLASS_200,
            "all": cloudfront.PriceClass.PRICE_CLASS_ALL,
        }
        price_class = price_class_map.get(price_class_str.lower(), cloudfront.PriceClass.PRICE_CLASS_ALL)

        # Get AWS environment
        env = Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
        )

        # Create the stack
        CloudFrontCdnStack(
            self,
            "CloudFrontCdnStack",
            domain_name=domain_name,
            certificate_arn=certificate_arn,
            enable_waf=enable_waf,
            price_class=price_class,
            env=env,
            description="CloudFront CDN with Origin Access Controls - AWS CDK Recipe",
            tags={
                "Project": "CDN-Recipe",
                "Environment": self.node.try_get_context("environment") or "dev",
                "Owner": self.node.try_get_context("owner") or "aws-cdk-recipes",
            },
        )


# Application entry point
app = CloudFrontCdnApp()
app.synth()