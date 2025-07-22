#!/usr/bin/env python3
"""
CDK Python application for Secure Content Delivery with CloudFront WAF

This application creates a secure content delivery solution using:
- Amazon CloudFront for global content delivery
- AWS WAF for web application firewall protection
- S3 bucket for content storage with Origin Access Control
- CloudWatch for monitoring and logging

Author: AWS CDK Generator v1.3
Recipe: content-delivery-cloudfront-waf
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    App,
    Stack,
    StackProps,
    Environment,
    CfnOutput,
    RemovalPolicy,
    Duration,
)
from aws_cdk import aws_s3 as s3
from aws_cdk import aws_s3_deployment as s3deploy
from aws_cdk import aws_cloudfront as cloudfront
from aws_cdk import aws_cloudfront_origins as origins
from aws_cdk import aws_wafv2 as wafv2
from aws_cdk import aws_iam as iam
from aws_cdk import aws_logs as logs
from constructs import Construct


class SecureContentDeliveryStack(Stack):
    """
    CDK Stack for secure content delivery with CloudFront and WAF.
    
    This stack creates:
    - S3 bucket for content storage
    - WAF Web ACL with managed rules and rate limiting
    - CloudFront distribution with Origin Access Control
    - Monitoring and logging configuration
    """
    
    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)
        
        # Get environment variables for configuration
        self.environment_name = self.node.try_get_context("environment") or "dev"
        self.blocked_countries = self.node.try_get_context("blocked_countries") or ["RU", "CN"]
        self.rate_limit = int(self.node.try_get_context("rate_limit") or "2000")
        
        # Create S3 bucket for content storage
        self.content_bucket = self._create_content_bucket()
        
        # Create WAF Web ACL with security rules
        self.web_acl = self._create_waf_web_acl()
        
        # Create CloudFront distribution with WAF protection
        self.distribution = self._create_cloudfront_distribution()
        
        # Update S3 bucket policy for CloudFront access
        self._configure_bucket_policy()
        
        # Create CloudWatch log group for WAF
        self._create_logging()
        
        # Create stack outputs
        self._create_outputs()
    
    def _create_content_bucket(self) -> s3.Bucket:
        """
        Create S3 bucket for content storage with security best practices.
        
        Returns:
            s3.Bucket: The created S3 bucket
        """
        bucket = s3.Bucket(
            self,
            "ContentBucket",
            bucket_name=f"secure-content-{self.environment_name}-{self.account}-{self.region}",
            versioning=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            server_access_logs_prefix="access-logs/",
            event_bridge_enabled=True,
        )
        
        # Add sample content
        s3deploy.BucketDeployment(
            self,
            "SampleContent",
            sources=[s3deploy.Source.data(
                "index.html",
                "<html><body><h1>Secure Content Test</h1>"
                "<p>This content is protected by AWS WAF and CloudFront.</p>"
                f"<p>Environment: {self.environment_name}</p>"
                "</body></html>"
            )],
            destination_bucket=bucket,
        )
        
        # Add security tags
        cdk.Tags.of(bucket).add("Environment", self.environment_name)
        cdk.Tags.of(bucket).add("Purpose", "SecureContentDelivery")
        cdk.Tags.of(bucket).add("Security", "High")
        
        return bucket
    
    def _create_waf_web_acl(self) -> wafv2.CfnWebACL:
        """
        Create WAF Web ACL with managed rules and rate-based protection.
        
        Returns:
            wafv2.CfnWebACL: The created WAF Web ACL
        """
        # Define managed rule groups
        managed_rules = [
            # AWS Core Rule Set for common attacks
            wafv2.CfnWebACL.RuleProperty(
                name="AWSManagedRulesCommonRuleSet",
                priority=1,
                statement=wafv2.CfnWebACL.StatementProperty(
                    managed_rule_group_statement=wafv2.CfnWebACL.ManagedRuleGroupStatementProperty(
                        vendor_name="AWS",
                        name="AWSManagedRulesCommonRuleSet",
                        excluded_rules=[
                            # Exclude specific rules if needed for your application
                            # wafv2.CfnWebACL.ExcludedRuleProperty(name="SizeRestrictions_BODY")
                        ]
                    )
                ),
                override_action=wafv2.CfnWebACL.OverrideActionProperty(none={}),
                visibility_config=wafv2.CfnWebACL.VisibilityConfigProperty(
                    sampled_requests_enabled=True,
                    cloud_watch_metrics_enabled=True,
                    metric_name="CommonRuleSetMetric"
                )
            ),
            
            # Known Bad Inputs Rule Set
            wafv2.CfnWebACL.RuleProperty(
                name="AWSManagedRulesKnownBadInputsRuleSet",
                priority=2,
                statement=wafv2.CfnWebACL.StatementProperty(
                    managed_rule_group_statement=wafv2.CfnWebACL.ManagedRuleGroupStatementProperty(
                        vendor_name="AWS",
                        name="AWSManagedRulesKnownBadInputsRuleSet"
                    )
                ),
                override_action=wafv2.CfnWebACL.OverrideActionProperty(none={}),
                visibility_config=wafv2.CfnWebACL.VisibilityConfigProperty(
                    sampled_requests_enabled=True,
                    cloud_watch_metrics_enabled=True,
                    metric_name="KnownBadInputsMetric"
                )
            ),
            
            # Rate-based rule for DDoS protection
            wafv2.CfnWebACL.RuleProperty(
                name="RateLimitRule",
                priority=3,
                statement=wafv2.CfnWebACL.StatementProperty(
                    rate_based_statement=wafv2.CfnWebACL.RateBasedStatementProperty(
                        limit=self.rate_limit,
                        aggregate_key_type="IP"
                    )
                ),
                action=wafv2.CfnWebACL.RuleActionProperty(block={}),
                visibility_config=wafv2.CfnWebACL.VisibilityConfigProperty(
                    sampled_requests_enabled=True,
                    cloud_watch_metrics_enabled=True,
                    metric_name="RateLimitMetric"
                )
            )
        ]
        
        # Create WAF Web ACL
        web_acl = wafv2.CfnWebACL(
            self,
            "SecureWebACL",
            name=f"secure-web-acl-{self.environment_name}",
            scope="CLOUDFRONT",
            default_action=wafv2.CfnWebACL.DefaultActionProperty(allow={}),
            description=f"Web ACL for secure content delivery - {self.environment_name}",
            rules=managed_rules,
            visibility_config=wafv2.CfnWebACL.VisibilityConfigProperty(
                sampled_requests_enabled=True,
                cloud_watch_metrics_enabled=True,
                metric_name=f"SecureWebACL-{self.environment_name}"
            ),
            tags=[
                cdk.CfnTag(key="Environment", value=self.environment_name),
                cdk.CfnTag(key="Purpose", value="ContentSecurityProtection"),
                cdk.CfnTag(key="Security", value="Critical")
            ]
        )
        
        return web_acl
    
    def _create_cloudfront_distribution(self) -> cloudfront.Distribution:
        """
        Create CloudFront distribution with WAF protection and security headers.
        
        Returns:
            cloudfront.Distribution: The created CloudFront distribution
        """
        # Create Origin Access Control
        oac = cloudfront.OriginAccessControl(
            self,
            "OriginAccessControl",
            description=f"OAC for secure content bucket - {self.environment_name}",
            origin_access_control_origin_type=cloudfront.OriginAccessControlOriginType.S3,
            signing_behavior=cloudfront.SigningBehavior.ALWAYS,
            signing_protocol=cloudfront.SigningProtocol.SIGV4
        )
        
        # Create response headers policy for security
        response_headers_policy = cloudfront.ResponseHeadersPolicy(
            self,
            "SecurityHeadersPolicy",
            response_headers_policy_name=f"security-headers-{self.environment_name}",
            comment="Security headers for content delivery",
            security_headers_behavior=cloudfront.ResponseSecurityHeadersBehavior(
                strict_transport_security=cloudfront.ResponseHeadersStrictTransportSecurity(
                    access_control_max_age=Duration.seconds(63072000),  # 2 years
                    include_subdomains=True,
                    override=True
                ),
                content_type_options=cloudfront.ResponseHeadersContentTypeOptions(override=True),
                frame_options=cloudfront.ResponseHeadersFrameOptions(
                    frame_option=cloudfront.HeadersFrameOption.DENY,
                    override=True
                ),
                referrer_policy=cloudfront.ResponseHeadersReferrerPolicy(
                    referrer_policy=cloudfront.HeadersReferrerPolicy.STRICT_ORIGIN_WHEN_CROSS_ORIGIN,
                    override=True
                )
            )
        )
        
        # Create cache policy for optimized caching
        cache_policy = cloudfront.CachePolicy(
            self,
            "OptimizedCachePolicy",
            cache_policy_name=f"optimized-cache-{self.environment_name}",
            comment="Optimized caching for static content",
            default_ttl=Duration.days(1),
            max_ttl=Duration.days(365),
            min_ttl=Duration.seconds(0),
            cookie_behavior=cloudfront.CacheCookieBehavior.none(),
            header_behavior=cloudfront.CacheHeaderBehavior.none(),
            query_string_behavior=cloudfront.CacheQueryStringBehavior.none(),
            enable_accept_encoding_gzip=True,
            enable_accept_encoding_brotli=True
        )
        
        # Create CloudFront distribution
        distribution = cloudfront.Distribution(
            self,
            "SecureDistribution",
            comment=f"Secure content delivery distribution - {self.environment_name}",
            default_behavior=cloudfront.BehaviorOptions(
                origin=origins.S3Origin(
                    bucket=self.content_bucket,
                    origin_access_control=oac
                ),
                viewer_protocol_policy=cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
                cache_policy=cache_policy,
                response_headers_policy=response_headers_policy,
                allowed_methods=cloudfront.AllowedMethods.ALLOW_GET_HEAD,
                cached_methods=cloudfront.CachedMethods.CACHE_GET_HEAD,
                compress=True
            ),
            geo_restriction=cloudfront.GeoRestriction.blacklist(*self.blocked_countries),
            price_class=cloudfront.PriceClass.PRICE_CLASS_100,  # Use only North America and Europe
            web_acl_id=self.web_acl.attr_arn,
            enable_logging=True,
            log_bucket=self.content_bucket,
            log_file_prefix="cloudfront-logs/",
            log_includes_cookies=False,
            minimum_protocol_version=cloudfront.SecurityPolicyProtocol.TLS_V1_2_2021,
            http_version=cloudfront.HttpVersion.HTTP2_AND_3,
            enable_ipv6=True
        )
        
        # Add tags to distribution
        cdk.Tags.of(distribution).add("Environment", self.environment_name)
        cdk.Tags.of(distribution).add("Purpose", "SecureContentDelivery")
        cdk.Tags.of(distribution).add("Security", "Protected")
        
        return distribution
    
    def _configure_bucket_policy(self) -> None:
        """Configure S3 bucket policy to allow CloudFront Origin Access Control."""
        # Create policy statement for CloudFront access
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
            }
        )
        
        # Add policy to bucket
        self.content_bucket.add_to_resource_policy(policy_statement)
    
    def _create_logging(self) -> None:
        """Create CloudWatch log group for WAF logging."""
        # Create log group for WAF
        log_group = logs.LogGroup(
            self,
            "WAFLogGroup",
            log_group_name=f"/aws/wafv2/webacl/secure-web-acl-{self.environment_name}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY
        )
        
        # Enable logging for WAF Web ACL
        wafv2.CfnLoggingConfiguration(
            self,
            "WAFLoggingConfiguration",
            resource_arn=self.web_acl.attr_arn,
            log_destination_configs=[log_group.log_group_arn]
        )
        
        # Add tags to log group
        cdk.Tags.of(log_group).add("Environment", self.environment_name)
        cdk.Tags.of(log_group).add("Purpose", "WAFSecurityLogging")
    
    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource identifiers."""
        CfnOutput(
            self,
            "ContentBucketName",
            value=self.content_bucket.bucket_name,
            description="Name of the S3 bucket containing the content",
            export_name=f"ContentBucket-{self.environment_name}"
        )
        
        CfnOutput(
            self,
            "CloudFrontDistributionId",
            value=self.distribution.distribution_id,
            description="CloudFront distribution ID",
            export_name=f"DistributionId-{self.environment_name}"
        )
        
        CfnOutput(
            self,
            "CloudFrontDomainName",
            value=self.distribution.distribution_domain_name,
            description="CloudFront distribution domain name",
            export_name=f"DistributionDomain-{self.environment_name}"
        )
        
        CfnOutput(
            self,
            "CloudFrontDistributionURL",
            value=f"https://{self.distribution.distribution_domain_name}",
            description="Complete HTTPS URL for the CloudFront distribution",
            export_name=f"DistributionURL-{self.environment_name}"
        )
        
        CfnOutput(
            self,
            "WAFWebACLArn",
            value=self.web_acl.attr_arn,
            description="ARN of the WAF Web ACL",
            export_name=f"WAFWebACLArn-{self.environment_name}"
        )
        
        CfnOutput(
            self,
            "WAFWebACLId",
            value=self.web_acl.attr_id,
            description="ID of the WAF Web ACL",
            export_name=f"WAFWebACLId-{self.environment_name}"
        )


def main() -> None:
    """Main function to create and deploy the CDK application."""
    app = App()
    
    # Get environment from context or default to development
    environment_name = app.node.try_get_context("environment") or "dev"
    
    # Define environment for the stack
    env = Environment(
        account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
        region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
    )
    
    # Create the secure content delivery stack
    SecureContentDeliveryStack(
        app,
        f"SecureContentDeliveryStack-{environment_name}",
        env=env,
        description=f"Secure content delivery with CloudFront and WAF for {environment_name} environment",
        tags={
            "Project": "SecureContentDelivery",
            "Environment": environment_name,
            "ManagedBy": "CDK",
            "Recipe": "content-delivery-cloudfront-waf"
        }
    )
    
    app.synth()


if __name__ == "__main__":
    main()