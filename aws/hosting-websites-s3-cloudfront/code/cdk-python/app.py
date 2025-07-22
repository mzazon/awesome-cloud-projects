#!/usr/bin/env python3
"""
CDK Python application for static website hosting with S3, CloudFront, and Route 53.

This application creates a complete static website hosting solution including:
- S3 buckets for website content and root domain redirect
- CloudFront distribution for global content delivery
- Route 53 DNS records for custom domain
- SSL/TLS certificate via Certificate Manager
"""

import os
from typing import Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    aws_s3 as s3,
    aws_s3_deployment as s3_deployment,
    aws_cloudfront as cloudfront,
    aws_cloudfront_origins as origins,
    aws_certificatemanager as acm,
    aws_route53 as route53,
    aws_route53_targets as targets,
    aws_iam as iam,
    RemovalPolicy,
    Duration,
    CfnOutput,
)
from constructs import Construct


class StaticWebsiteStack(Stack):
    """
    CDK Stack for static website hosting with S3, CloudFront, and Route 53.
    
    This stack creates a production-ready static website hosting solution with:
    - S3 bucket for website content with proper security configuration
    - S3 bucket for root domain redirect (www canonicalization)
    - CloudFront distribution with global edge caching
    - SSL/TLS certificate with automatic DNS validation
    - Route 53 DNS records for custom domain routing
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        domain_name: str,
        hosted_zone_id: Optional[str] = None,
        **kwargs
    ) -> None:
        """
        Initialize the Static Website Stack.
        
        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            domain_name: The root domain name (e.g., 'example.com')
            hosted_zone_id: Optional existing Route 53 hosted zone ID
            **kwargs: Additional keyword arguments
        """
        super().__init__(scope, construct_id, **kwargs)
        
        self.domain_name = domain_name
        self.subdomain = f"www.{domain_name}"
        
        # Look up or create hosted zone
        if hosted_zone_id:
            self.hosted_zone = route53.HostedZone.from_hosted_zone_attributes(
                self, "HostedZone",
                hosted_zone_id=hosted_zone_id,
                zone_name=domain_name
            )
        else:
            self.hosted_zone = route53.HostedZone.from_lookup(
                self, "HostedZone",
                domain_name=domain_name
            )
        
        # Create S3 buckets
        self._create_s3_buckets()
        
        # Create SSL certificate
        self._create_ssl_certificate()
        
        # Create CloudFront distribution
        self._create_cloudfront_distribution()
        
        # Create Route 53 records
        self._create_route53_records()
        
        # Deploy sample content
        self._deploy_sample_content()
        
        # Output important information
        self._create_outputs()

    def _create_s3_buckets(self) -> None:
        """Create S3 buckets for website hosting and root domain redirect."""
        
        # Main website bucket (www subdomain)
        self.website_bucket = s3.Bucket(
            self, "WebsiteBucket",
            bucket_name=self.subdomain,
            website_index_document="index.html",
            website_error_document="error.html",
            public_read_access=True,
            block_public_access=s3.BlockPublicAccess(
                block_public_acls=False,
                block_public_policy=False,
                ignore_public_acls=False,
                restrict_public_buckets=False
            ),
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            versioned=False,
            server_access_logs_prefix="access-logs/"
        )
        
        # Add bucket policy for public read access
        self.website_bucket.add_to_resource_policy(
            iam.PolicyStatement(
                sid="PublicReadGetObject",
                effect=iam.Effect.ALLOW,
                principals=[iam.AnyPrincipal()],
                actions=["s3:GetObject"],
                resources=[f"{self.website_bucket.bucket_arn}/*"]
            )
        )
        
        # Root domain redirect bucket
        self.redirect_bucket = s3.Bucket(
            self, "RedirectBucket",
            bucket_name=self.domain_name,
            website_redirect_host=self.subdomain,
            website_redirect_protocol=s3.RedirectProtocol.HTTPS,
            public_read_access=True,
            block_public_access=s3.BlockPublicAccess(
                block_public_acls=False,
                block_public_policy=False,
                ignore_public_acls=False,
                restrict_public_buckets=False
            ),
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True
        )

    def _create_ssl_certificate(self) -> None:
        """Create SSL certificate for both root domain and www subdomain."""
        
        # Certificate must be in us-east-1 for CloudFront
        self.certificate = acm.Certificate(
            self, "Certificate",
            domain_name=self.domain_name,
            subject_alternative_names=[self.subdomain],
            validation=acm.CertificateValidation.from_dns(self.hosted_zone),
            certificate_name=f"{self.domain_name}-certificate"
        )

    def _create_cloudfront_distribution(self) -> None:
        """Create CloudFront distribution for global content delivery."""
        
        # Create Origin Access Identity for S3 bucket access
        origin_access_identity = cloudfront.OriginAccessIdentity(
            self, "OriginAccessIdentity",
            comment=f"OAI for {self.subdomain}"
        )
        
        # Grant CloudFront access to S3 bucket
        self.website_bucket.grant_read(origin_access_identity)
        
        # Create cache policy for static website
        cache_policy = cloudfront.CachePolicy(
            self, "CachePolicy",
            cache_policy_name=f"{self.domain_name}-cache-policy",
            comment="Cache policy for static website",
            default_ttl=Duration.days(1),
            max_ttl=Duration.days(365),
            min_ttl=Duration.seconds(0),
            cookie_behavior=cloudfront.CacheCookieBehavior.none(),
            header_behavior=cloudfront.CacheHeaderBehavior.none(),
            query_string_behavior=cloudfront.CacheQueryStringBehavior.none(),
            enable_accept_encoding_brotli=True,
            enable_accept_encoding_gzip=True
        )
        
        # Create CloudFront distribution
        self.distribution = cloudfront.Distribution(
            self, "Distribution",
            domain_names=[self.subdomain],
            certificate=self.certificate,
            minimum_protocol_version=cloudfront.SecurityPolicyProtocol.TLS_V1_2_2021,
            ssl_support_method=cloudfront.SSLMethod.SNI,
            default_behavior=cloudfront.BehaviorOptions(
                origin=origins.S3Origin(
                    self.website_bucket,
                    origin_access_identity=origin_access_identity
                ),
                compress=True,
                viewer_protocol_policy=cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
                cache_policy=cache_policy,
                allowed_methods=cloudfront.AllowedMethods.ALLOW_GET_HEAD,
                cached_methods=cloudfront.CachedMethods.CACHE_GET_HEAD
            ),
            default_root_object="index.html",
            error_responses=[
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
            price_class=cloudfront.PriceClass.PRICE_CLASS_100,
            geo_restriction=cloudfront.GeoRestriction.allowlist("US", "CA", "GB", "DE", "FR"),
            comment=f"CloudFront distribution for {self.subdomain}",
            enabled=True
        )

    def _create_route53_records(self) -> None:
        """Create Route 53 DNS records for custom domain routing."""
        
        # A record for www subdomain pointing to CloudFront
        self.www_record = route53.ARecord(
            self, "WwwRecord",
            zone=self.hosted_zone,
            record_name=self.subdomain,
            target=route53.RecordTarget.from_alias(
                targets.CloudFrontTarget(self.distribution)
            ),
            comment=f"A record for {self.subdomain} pointing to CloudFront"
        )
        
        # A record for root domain pointing to S3 redirect bucket
        self.root_record = route53.ARecord(
            self, "RootRecord",
            zone=self.hosted_zone,
            record_name=self.domain_name,
            target=route53.RecordTarget.from_alias(
                targets.BucketWebsiteTarget(self.redirect_bucket)
            ),
            comment=f"A record for {self.domain_name} pointing to S3 redirect bucket"
        )

    def _deploy_sample_content(self) -> None:
        """Deploy sample website content to S3 bucket."""
        
        # Create sample HTML content
        index_html = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Welcome to {self.domain_name}</title>
    <style>
        body {{ 
            font-family: Arial, sans-serif; 
            margin: 40px; 
            text-align: center; 
            background-color: #f0f8ff;
            color: #333;
        }}
        h1 {{ 
            color: #2c3e50; 
            margin-bottom: 20px;
        }}
        p {{ 
            color: #7f8c8d; 
            font-size: 18px; 
            line-height: 1.6;
        }}
        .container {{
            max-width: 800px;
            margin: 0 auto;
            padding: 20px;
        }}
        .badge {{
            background-color: #3498db;
            color: white;
            padding: 5px 10px;
            border-radius: 3px;
            font-size: 14px;
            margin: 0 5px;
        }}
    </style>
</head>
<body>
    <div class="container">
        <h1>Welcome to {self.domain_name}</h1>
        <p>Your static website is now live with global CDN delivery!</p>
        <p>
            <span class="badge">AWS S3</span>
            <span class="badge">CloudFront</span>
            <span class="badge">Route 53</span>
        </p>
        <p>This website is deployed using AWS CDK and follows security best practices.</p>
    </div>
</body>
</html>"""
        
        error_html = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Page Not Found - {self.domain_name}</title>
    <style>
        body {{ 
            font-family: Arial, sans-serif; 
            margin: 40px; 
            text-align: center; 
            background-color: #fff5f5;
            color: #333;
        }}
        h1 {{ 
            color: #e74c3c; 
            margin-bottom: 20px;
        }}
        p {{
            color: #7f8c8d;
            font-size: 18px;
            line-height: 1.6;
        }}
        a {{
            color: #3498db;
            text-decoration: none;
        }}
        a:hover {{
            text-decoration: underline;
        }}
        .container {{
            max-width: 600px;
            margin: 0 auto;
            padding: 20px;
        }}
    </style>
</head>
<body>
    <div class="container">
        <h1>404 - Page Not Found</h1>
        <p>The page you're looking for doesn't exist.</p>
        <p><a href="/">Return to Home</a></p>
    </div>
</body>
</html>"""
        
        # Deploy content to S3
        s3_deployment.BucketDeployment(
            self, "DeployWebsite",
            sources=[
                s3_deployment.Source.data("index.html", index_html),
                s3_deployment.Source.data("error.html", error_html)
            ],
            destination_bucket=self.website_bucket,
            distribution=self.distribution,
            distribution_paths=["/*"],
            retain_on_delete=False
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information."""
        
        CfnOutput(
            self, "WebsiteURL",
            value=f"https://{self.subdomain}",
            description="Website URL"
        )
        
        CfnOutput(
            self, "CloudFrontDistributionId",
            value=self.distribution.distribution_id,
            description="CloudFront Distribution ID"
        )
        
        CfnOutput(
            self, "CloudFrontDomainName",
            value=self.distribution.domain_name,
            description="CloudFront Distribution Domain Name"
        )
        
        CfnOutput(
            self, "S3BucketName",
            value=self.website_bucket.bucket_name,
            description="S3 Bucket Name for Website Content"
        )
        
        CfnOutput(
            self, "CertificateArn",
            value=self.certificate.certificate_arn,
            description="SSL Certificate ARN"
        )
        
        CfnOutput(
            self, "HostedZoneId",
            value=self.hosted_zone.hosted_zone_id,
            description="Route 53 Hosted Zone ID"
        )


def main() -> None:
    """Main function to create and deploy the CDK application."""
    
    # Create CDK app
    app = cdk.App()
    
    # Get configuration from environment variables or context
    domain_name = app.node.try_get_context("domain_name") or os.environ.get("DOMAIN_NAME")
    hosted_zone_id = app.node.try_get_context("hosted_zone_id") or os.environ.get("HOSTED_ZONE_ID")
    
    if not domain_name:
        raise ValueError(
            "Domain name is required. Set DOMAIN_NAME environment variable or "
            "pass domain_name in CDK context."
        )
    
    # Create stack
    StaticWebsiteStack(
        app, "StaticWebsiteStack",
        domain_name=domain_name,
        hosted_zone_id=hosted_zone_id,
        env=Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
        ),
        description="Static website hosting with S3, CloudFront, and Route 53"
    )
    
    # Synthesize CloudFormation template
    app.synth()


if __name__ == "__main__":
    main()