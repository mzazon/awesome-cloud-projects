#!/usr/bin/env python3
"""
AWS CDK Python Application for Static Website Hosting

This CDK application creates a complete static website hosting solution using:
- Amazon S3 for storage
- Amazon CloudFront for global content delivery
- AWS Certificate Manager for SSL certificates
- Route 53 for DNS management (optional)
- Origin Access Control for secure S3 access

Author: AWS CDK Recipe Generator
Version: 1.0
"""

import os
from typing import Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_s3 as s3,
    aws_cloudfront as cloudfront,
    aws_cloudfront_origins as origins,
    aws_certificatemanager as acm,
    aws_route53 as route53,
    aws_route53_targets as targets,
    aws_iam as iam,
)
from constructs import Construct


class StaticWebsiteStack(Stack):
    """
    CDK Stack for hosting static websites with S3 and CloudFront.
    
    This stack creates:
    - S3 bucket for website content
    - S3 bucket for access logs
    - CloudFront distribution with Origin Access Control
    - SSL certificate via ACM (if domain provided)
    - Route 53 DNS records (if domain and hosted zone provided)
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        domain_name: Optional[str] = None,
        hosted_zone_id: Optional[str] = None,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Store configuration
        self.domain_name = domain_name
        self.hosted_zone_id = hosted_zone_id

        # Create S3 buckets
        self._create_s3_buckets()

        # Create SSL certificate if domain is provided
        if self.domain_name:
            self._create_ssl_certificate()

        # Create CloudFront distribution
        self._create_cloudfront_distribution()

        # Create Route 53 records if domain and hosted zone are provided
        if self.domain_name and self.hosted_zone_id:
            self._create_route53_records()

        # Create outputs
        self._create_outputs()

    def _create_s3_buckets(self) -> None:
        """Create S3 buckets for website content and access logs."""
        
        # Create bucket for CloudFront access logs
        self.logs_bucket = s3.Bucket(
            self,
            "AccessLogsBucket",
            bucket_name=None,  # Let CDK generate unique name
            access_control=s3.BucketAccessControl.LOG_DELIVERY_WRITE,
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteOldLogs",
                    enabled=True,
                    expiration=Duration.days(90),
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30)
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(60)
                        )
                    ]
                )
            ]
        )

        # Create bucket for website content
        self.website_bucket = s3.Bucket(
            self,
            "WebsiteBucket",
            bucket_name=None,  # Let CDK generate unique name
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            versioned=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteOldVersions",
                    enabled=True,
                    noncurrent_version_expiration=Duration.days(30),
                    noncurrent_versions_to_retain=5
                )
            ]
        )

        # Add tags to buckets
        cdk.Tags.of(self.website_bucket).add("Purpose", "StaticWebsiteContent")
        cdk.Tags.of(self.logs_bucket).add("Purpose", "CloudFrontAccessLogs")

    def _create_ssl_certificate(self) -> None:
        """Create SSL certificate for the domain using ACM."""
        
        # Look up the hosted zone if ID is provided
        if self.hosted_zone_id:
            hosted_zone = route53.HostedZone.from_hosted_zone_attributes(
                self,
                "HostedZone",
                hosted_zone_id=self.hosted_zone_id,
                zone_name=self.domain_name
            )
        else:
            hosted_zone = None

        # Create certificate
        self.certificate = acm.Certificate(
            self,
            "SslCertificate",
            domain_name=self.domain_name,
            validation=acm.CertificateValidation.from_dns(hosted_zone) if hosted_zone else acm.CertificateValidation.from_email(),
            subject_alternative_names=[f"www.{self.domain_name}"] if not self.domain_name.startswith("www.") else None
        )

    def _create_cloudfront_distribution(self) -> None:
        """Create CloudFront distribution with Origin Access Control."""
        
        # Create Origin Access Control
        origin_access_control = cloudfront.S3OriginAccessControl(
            self,
            "OriginAccessControl",
            signing_behavior=cloudfront.OriginAccessControlSigningBehavior.ALWAYS,
            signing_protocol=cloudfront.OriginAccessControlSigningProtocol.SIGV4,
            origin_access_control_name="S3OriginAccessControl"
        )

        # Configure cache behaviors
        cache_behavior = cloudfront.BehaviorOptions(
            origin=origins.S3BucketOrigin.with_origin_access_control(
                bucket=self.website_bucket,
                origin_access_control=origin_access_control
            ),
            viewer_protocol_policy=cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
            allowed_methods=cloudfront.AllowedMethods.ALLOW_GET_HEAD,
            cached_methods=cloudfront.CachedMethods.CACHE_GET_HEAD,
            cache_policy=cloudfront.CachePolicy.CACHING_OPTIMIZED,
            origin_request_policy=cloudfront.OriginRequestPolicy.CORS_S3_ORIGIN,
            compress=True
        )

        # Configure distribution properties
        distribution_props = {
            "default_behavior": cache_behavior,
            "default_root_object": "index.html",
            "error_responses": [
                cloudfront.ErrorResponse(
                    http_status=404,
                    response_http_status=404,
                    response_page_path="/error.html",
                    ttl=Duration.minutes(5)
                ),
                cloudfront.ErrorResponse(
                    http_status=403,
                    response_http_status=404,
                    response_page_path="/error.html",
                    ttl=Duration.minutes(5)
                )
            ],
            "price_class": cloudfront.PriceClass.PRICE_CLASS_100,
            "enabled": True,
            "comment": f"Static website distribution for {self.domain_name}" if self.domain_name else "Static website distribution",
            "logging_config": cloudfront.LoggingConfiguration(
                bucket=self.logs_bucket,
                prefix="cloudfront-logs/"
            )
        }

        # Add domain and certificate if provided
        if self.domain_name and hasattr(self, 'certificate'):
            distribution_props.update({
                "domain_names": [self.domain_name],
                "certificate": self.certificate,
                "minimum_protocol_version": cloudfront.SecurityPolicyProtocol.TLS_V1_2_2021
            })

        # Create CloudFront distribution
        self.distribution = cloudfront.Distribution(
            self,
            "Distribution",
            **distribution_props
        )

        # Grant CloudFront access to S3 bucket
        self.website_bucket.add_to_resource_policy(
            iam.PolicyStatement(
                sid="AllowCloudFrontServicePrincipalReadOnly",
                effect=iam.Effect.ALLOW,
                principals=[iam.ServicePrincipal("cloudfront.amazonaws.com")],
                actions=["s3:GetObject"],
                resources=[f"{self.website_bucket.bucket_arn}/*"],
                conditions={
                    "StringEquals": {
                        "AWS:SourceArn": f"arn:aws:cloudfront::{self.account}:distribution/{self.distribution.distribution_id}"
                    }
                }
            )
        )

    def _create_route53_records(self) -> None:
        """Create Route 53 A record pointing to CloudFront distribution."""
        
        # Look up the hosted zone
        hosted_zone = route53.HostedZone.from_hosted_zone_attributes(
            self,
            "DnsHostedZone",
            hosted_zone_id=self.hosted_zone_id,
            zone_name=self.domain_name
        )

        # Create A record pointing to CloudFront
        self.dns_record = route53.ARecord(
            self,
            "DnsRecord",
            zone=hosted_zone,
            record_name=self.domain_name,
            target=route53.RecordTarget.from_alias(
                targets.CloudFrontTarget(self.distribution)
            ),
            comment=f"A record for {self.domain_name} pointing to CloudFront distribution"
        )

        # Create www subdomain record if the domain doesn't start with www
        if not self.domain_name.startswith("www."):
            self.www_dns_record = route53.ARecord(
                self,
                "WwwDnsRecord",
                zone=hosted_zone,
                record_name=f"www.{self.domain_name}",
                target=route53.RecordTarget.from_alias(
                    targets.CloudFrontTarget(self.distribution)
                ),
                comment=f"A record for www.{self.domain_name} pointing to CloudFront distribution"
            )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        
        # S3 bucket outputs
        CfnOutput(
            self,
            "WebsiteBucketName",
            value=self.website_bucket.bucket_name,
            description="Name of the S3 bucket containing website content",
            export_name=f"{self.stack_name}-WebsiteBucketName"
        )

        CfnOutput(
            self,
            "LogsBucketName",
            value=self.logs_bucket.bucket_name,
            description="Name of the S3 bucket containing CloudFront access logs",
            export_name=f"{self.stack_name}-LogsBucketName"
        )

        # CloudFront outputs
        CfnOutput(
            self,
            "DistributionId",
            value=self.distribution.distribution_id,
            description="CloudFront distribution ID",
            export_name=f"{self.stack_name}-DistributionId"
        )

        CfnOutput(
            self,
            "DistributionDomainName",
            value=self.distribution.distribution_domain_name,
            description="CloudFront distribution domain name",
            export_name=f"{self.stack_name}-DistributionDomainName"
        )

        CfnOutput(
            self,
            "WebsiteUrl",
            value=f"https://{self.distribution.distribution_domain_name}",
            description="Website URL via CloudFront",
            export_name=f"{self.stack_name}-WebsiteUrl"
        )

        # Domain-specific outputs
        if self.domain_name:
            CfnOutput(
                self,
                "CustomDomainUrl",
                value=f"https://{self.domain_name}",
                description="Website URL with custom domain",
                export_name=f"{self.stack_name}-CustomDomainUrl"
            )

        if hasattr(self, 'certificate'):
            CfnOutput(
                self,
                "CertificateArn",
                value=self.certificate.certificate_arn,
                description="ARN of the SSL certificate",
                export_name=f"{self.stack_name}-CertificateArn"
            )


class StaticWebsiteApp(cdk.App):
    """CDK App for Static Website Hosting."""

    def __init__(self, **kwargs) -> None:
        super().__init__(**kwargs)

        # Get configuration from environment variables or context
        domain_name = self.node.try_get_context("domain_name") or os.environ.get("DOMAIN_NAME")
        hosted_zone_id = self.node.try_get_context("hosted_zone_id") or os.environ.get("HOSTED_ZONE_ID")
        
        # Get environment configuration
        env = cdk.Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
        )

        # Create the stack
        StaticWebsiteStack(
            self,
            "StaticWebsiteStack",
            domain_name=domain_name,
            hosted_zone_id=hosted_zone_id,
            env=env,
            description="Static website hosting with S3 and CloudFront",
            tags={
                "Project": "StaticWebsite",
                "Environment": self.node.try_get_context("environment") or "development",
                "ManagedBy": "AWS-CDK"
            }
        )


# Create and run the app
if __name__ == "__main__":
    app = StaticWebsiteApp()
    app.synth()