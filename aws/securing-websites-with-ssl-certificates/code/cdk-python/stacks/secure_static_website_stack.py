"""
Secure Static Website Stack
===========================

This CDK stack implements a complete secure static website hosting solution
using AWS Certificate Manager, CloudFront, and S3.

Components:
- S3 bucket for static content storage with versioning
- ACM certificate with DNS validation for HTTPS
- CloudFront distribution with Origin Access Control
- Route 53 records for domain resolution
- Sample website content deployment
"""

from typing import Optional

import aws_cdk as cdk
from aws_cdk import (
    Duration,
    RemovalPolicy,
    Stack,
    StackProps,
    aws_certificatemanager as acm,
    aws_cloudfront as cloudfront,
    aws_cloudfront_origins as origins,
    aws_iam as iam,
    aws_route53 as route53,
    aws_route53_targets as targets,
    aws_s3 as s3,
    aws_s3_deployment as s3deploy,
)
from constructs import Construct


class SecureStaticWebsiteStack(Stack):
    """
    Stack for deploying a secure static website with ACM certificate and CloudFront.
    
    This stack creates:
    1. S3 bucket for static content storage
    2. ACM certificate with DNS validation  
    3. CloudFront distribution with OAC
    4. Route 53 records for domain resolution
    5. Sample website content
    """
    
    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        domain_name: str,
        subdomain: str,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)
        
        self.domain_name = domain_name
        self.subdomain = subdomain
        
        # Create S3 bucket for static website content
        self.website_bucket = self._create_website_bucket()
        
        # Create Route 53 hosted zone (if not exists) and get reference
        self.hosted_zone = self._get_or_create_hosted_zone()
        
        # Create ACM certificate with DNS validation
        self.certificate = self._create_ssl_certificate()
        
        # Create Origin Access Control for S3
        self.origin_access_control = self._create_origin_access_control()
        
        # Create CloudFront distribution
        self.distribution = self._create_cloudfront_distribution()
        
        # Update S3 bucket policy for CloudFront access
        self._update_bucket_policy()
        
        # Create Route 53 records for the domain
        self._create_dns_records()
        
        # Deploy sample website content
        self._deploy_sample_content()
        
        # Create outputs
        self._create_outputs()
    
    def _create_website_bucket(self) -> s3.Bucket:
        """Create S3 bucket for static website hosting."""
        bucket = s3.Bucket(
            self,
            "WebsiteBucket",
            bucket_name=f"static-website-{self.account}-{self.region}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )
        
        # Add tags
        cdk.Tags.of(bucket).add("Purpose", "StaticWebsiteHosting")
        cdk.Tags.of(bucket).add("SSLEnabled", "true")
        
        return bucket
    
    def _get_or_create_hosted_zone(self) -> route53.IHostedZone:
        """Get existing or create new Route 53 hosted zone."""
        try:
            # Try to import existing hosted zone
            hosted_zone = route53.HostedZone.from_lookup(
                self,
                "HostedZone",
                domain_name=self.domain_name
            )
            return hosted_zone
        except Exception:
            # Create new hosted zone if not found
            hosted_zone = route53.HostedZone(
                self,
                "HostedZone",
                zone_name=self.domain_name,
                comment=f"Hosted zone for {self.domain_name} static website"
            )
            return hosted_zone
    
    def _create_ssl_certificate(self) -> acm.Certificate:
        """Create ACM certificate with DNS validation."""
        certificate = acm.Certificate(
            self,
            "SSLCertificate",
            domain_name=self.domain_name,
            subject_alternative_names=[self.subdomain],
            validation=acm.CertificateValidation.from_dns(self.hosted_zone),
            certificate_name=f"Certificate for {self.domain_name}",
            key_algorithm=acm.KeyAlgorithm.RSA_2048,
        )
        
        # Add tags
        cdk.Tags.of(certificate).add("Purpose", "StaticWebsiteSSL")
        cdk.Tags.of(certificate).add("Domain", self.domain_name)
        
        return certificate
    
    def _create_origin_access_control(self) -> cloudfront.S3OriginAccessControl:
        """Create Origin Access Control for secure S3 access."""
        oac = cloudfront.S3OriginAccessControl(
            self,
            "OriginAccessControl",
            description=f"OAC for {self.domain_name} static website",
            signing=cloudfront.Signing.SIGV4_ALWAYS,
        )
        
        return oac
    
    def _create_cloudfront_distribution(self) -> cloudfront.Distribution:
        """Create CloudFront distribution with SSL certificate."""
        # Create S3 origin with OAC
        s3_origin = origins.S3BucketOrigin.with_origin_access_control(
            self.website_bucket,
            origin_access_control=self.origin_access_control
        )
        
        # Create CloudFront distribution
        distribution = cloudfront.Distribution(
            self,
            "CloudFrontDistribution",
            default_behavior=cloudfront.BehaviorOptions(
                origin=s3_origin,
                viewer_protocol_policy=cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
                cache_policy=cloudfront.CachePolicy.CACHING_OPTIMIZED,
                response_headers_policy=cloudfront.ResponseHeadersPolicy.SECURITY_HEADERS,
                allowed_methods=cloudfront.AllowedMethods.ALLOW_GET_HEAD,
                cached_methods=cloudfront.CachedMethods.CACHE_GET_HEAD,
                compress=True,
            ),
            domain_names=[self.domain_name, self.subdomain],
            certificate=self.certificate,
            minimum_protocol_version=cloudfront.SecurityPolicyProtocol.TLS_V1_2_2021,
            ssl_support_method=cloudfront.SSLMethod.SNI,
            default_root_object="index.html",
            error_responses=[
                cloudfront.ErrorResponse(
                    http_status=404,
                    response_http_status=404,
                    response_page_path="/error.html",
                    ttl=Duration.minutes(5),
                ),
                cloudfront.ErrorResponse(
                    http_status=403,
                    response_http_status=404,
                    response_page_path="/error.html",
                    ttl=Duration.minutes(5),
                ),
            ],
            price_class=cloudfront.PriceClass.PRICE_CLASS_100,
            enable_logging=True,
            comment=f"CloudFront distribution for {self.domain_name}",
        )
        
        # Add tags
        cdk.Tags.of(distribution).add("Purpose", "StaticWebsiteDistribution")
        cdk.Tags.of(distribution).add("Domain", self.domain_name)
        cdk.Tags.of(distribution).add("SSL", "enabled")
        
        return distribution
    
    def _update_bucket_policy(self) -> None:
        """Update S3 bucket policy to allow CloudFront access."""
        # Create bucket policy for CloudFront access
        bucket_policy = iam.PolicyStatement(
            sid="AllowCloudFrontServicePrincipal",
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
        
        self.website_bucket.add_to_resource_policy(bucket_policy)
    
    def _create_dns_records(self) -> None:
        """Create Route 53 records for the domain."""
        # Create A record for root domain
        route53.ARecord(
            self,
            "RootDomainRecord",
            zone=self.hosted_zone,
            record_name=self.domain_name,
            target=route53.RecordTarget.from_alias(
                targets.CloudFrontTarget(self.distribution)
            ),
            comment=f"A record for {self.domain_name} pointing to CloudFront",
        )
        
        # Create A record for subdomain
        route53.ARecord(
            self,
            "SubdomainRecord",
            zone=self.hosted_zone,
            record_name=self.subdomain,
            target=route53.RecordTarget.from_alias(
                targets.CloudFrontTarget(self.distribution)
            ),
            comment=f"A record for {self.subdomain} pointing to CloudFront",
        )
        
        # Create AAAA records for IPv6 support
        route53.AaaaRecord(
            self,
            "RootDomainIPv6Record",
            zone=self.hosted_zone,
            record_name=self.domain_name,
            target=route53.RecordTarget.from_alias(
                targets.CloudFrontTarget(self.distribution)
            ),
            comment=f"AAAA record for {self.domain_name} IPv6 support",
        )
        
        route53.AaaaRecord(
            self,
            "SubdomainIPv6Record",
            zone=self.hosted_zone,
            record_name=self.subdomain,
            target=route53.RecordTarget.from_alias(
                targets.CloudFrontTarget(self.distribution)
            ),
            comment=f"AAAA record for {self.subdomain} IPv6 support",
        )
    
    def _deploy_sample_content(self) -> None:
        """Deploy sample website content to S3 bucket."""
        # Create sample HTML content
        s3deploy.BucketDeployment(
            self,
            "DeployWebsiteContent",
            sources=[
                s3deploy.Source.data(
                    "index.html",
                    self._get_index_html_content()
                ),
                s3deploy.Source.data(
                    "error.html",
                    self._get_error_html_content()
                ),
            ],
            destination_bucket=self.website_bucket,
            distribution=self.distribution,
            distribution_paths=["/*"],
            retain_on_delete=False,
            memory_limit=512,
        )
    
    def _get_index_html_content(self) -> str:
        """Generate index.html content."""
        return f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Secure Static Website - {self.domain_name}</title>
    <style>
        body {{
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            line-height: 1.6;
            color: #333;
            max-width: 800px;
            margin: 0 auto;
            padding: 2rem;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
        }}
        .container {{
            background: white;
            border-radius: 10px;
            padding: 2rem;
            box-shadow: 0 10px 30px rgba(0,0,0,0.2);
        }}
        .secure {{
            color: #28a745;
            font-weight: bold;
            display: inline-flex;
            align-items: center;
        }}
        .secure::before {{
            content: "🔒";
            margin-right: 0.5rem;
        }}
        .features {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 1rem;
            margin: 2rem 0;
        }}
        .feature {{
            background: #f8f9fa;
            padding: 1rem;
            border-radius: 5px;
            border-left: 4px solid #667eea;
        }}
        .badge {{
            display: inline-block;
            background: #28a745;
            color: white;
            padding: 0.2rem 0.5rem;
            border-radius: 3px;
            font-size: 0.8rem;
            margin: 0.2rem;
        }}
        h1 {{
            color: #2c3e50;
            margin-bottom: 1rem;
        }}
        .tech-stack {{
            background: #e9ecef;
            padding: 1rem;
            border-radius: 5px;
            margin: 1rem 0;
        }}
        footer {{
            text-align: center;
            margin-top: 2rem;
            padding-top: 1rem;
            border-top: 1px solid #dee2e6;
            color: #6c757d;
            font-size: 0.9rem;
        }}
        .status {{
            display: flex;
            align-items: center;
            gap: 0.5rem;
            margin: 1rem 0;
        }}
        .status-dot {{
            width: 8px;
            height: 8px;
            background: #28a745;
            border-radius: 50%;
            animation: pulse 2s infinite;
        }}
        @keyframes pulse {{
            0% {{ opacity: 1; }}
            50% {{ opacity: 0.5; }}
            100% {{ opacity: 1; }}
        }}
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 Welcome to Your <span class="secure">Secure</span> Static Website</h1>
        
        <div class="status">
            <span class="status-dot"></span>
            <strong>Status: Secure HTTPS Connection Active</strong>
        </div>
        
        <p>Congratulations! Your static website is now running securely with enterprise-grade infrastructure powered by AWS.</p>
        
        <div class="tech-stack">
            <h3>🏗️ Technology Stack</h3>
            <div>
                <span class="badge">AWS S3</span>
                <span class="badge">CloudFront CDN</span>
                <span class="badge">ACM Certificate</span>
                <span class="badge">Route 53 DNS</span>
                <span class="badge">Origin Access Control</span>
            </div>
        </div>
        
        <div class="features">
            <div class="feature">
                <h4>🔐 SSL/TLS Security</h4>
                <p>Automatic HTTPS with AWS Certificate Manager providing free, auto-renewing SSL certificates.</p>
            </div>
            
            <div class="feature">
                <h4>🌍 Global Performance</h4>
                <p>CloudFront CDN delivers your content from edge locations worldwide for optimal performance.</p>
            </div>
            
            <div class="feature">
                <h4>🛡️ Enhanced Security</h4>
                <p>Origin Access Control ensures S3 content is only accessible through CloudFront.</p>
            </div>
            
            <div class="feature">
                <h4>📊 Monitoring Ready</h4>
                <p>Built-in CloudWatch logging and monitoring for performance and security insights.</p>
            </div>
        </div>
        
        <div class="tech-stack">
            <h3>✅ Security Features Active</h3>
            <ul>
                <li>✅ HTTPS enforcement (HTTP redirects to HTTPS)</li>
                <li>✅ TLS 1.2+ minimum protocol version</li>
                <li>✅ Origin Access Control (OAC) protecting S3</li>
                <li>✅ Security headers via CloudFront</li>
                <li>✅ Automatic certificate renewal</li>
                <li>✅ IPv6 support enabled</li>
            </ul>
        </div>
        
        <p><strong>Domain:</strong> {self.domain_name}<br>
        <strong>Subdomain:</strong> {self.subdomain}<br>
        <strong>SSL Certificate:</strong> AWS Certificate Manager<br>
        <strong>CDN:</strong> Amazon CloudFront</p>
        
        <footer>
            <p>Deployed with AWS CDK | Infrastructure as Code | 
            <a href="https://aws.amazon.com/certificate-manager/" target="_blank">Learn more about ACM</a></p>
        </footer>
    </div>
</body>
</html>"""
    
    def _get_error_html_content(self) -> str:
        """Generate error.html content."""
        return f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Page Not Found - {self.domain_name}</title>
    <style>
        body {{
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            line-height: 1.6;
            color: #333;
            max-width: 600px;
            margin: 0 auto;
            padding: 2rem;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }}
        .container {{
            background: white;
            border-radius: 10px;
            padding: 2rem;
            box-shadow: 0 10px 30px rgba(0,0,0,0.2);
            text-align: center;
        }}
        .error-code {{
            font-size: 6rem;
            font-weight: bold;
            color: #e74c3c;
            margin: 0;
            line-height: 1;
        }}
        .error-message {{
            font-size: 1.5rem;
            color: #2c3e50;
            margin: 1rem 0;
        }}
        .error-description {{
            color: #6c757d;
            margin-bottom: 2rem;
        }}
        .back-button {{
            display: inline-block;
            background: #667eea;
            color: white;
            padding: 1rem 2rem;
            text-decoration: none;
            border-radius: 5px;
            transition: background 0.3s;
        }}
        .back-button:hover {{
            background: #5a6fd8;
        }}
        .secure-indicator {{
            margin-top: 2rem;
            padding: 1rem;
            background: #d4edda;
            border: 1px solid #c3e6cb;
            border-radius: 5px;
            color: #155724;
        }}
    </style>
</head>
<body>
    <div class="container">
        <div class="error-code">404</div>
        <div class="error-message">Page Not Found</div>
        <div class="error-description">
            The page you're looking for doesn't exist or has been moved.
            But don't worry, your connection is still secure!
        </div>
        
        <a href="/" class="back-button">🏠 Return Home</a>
        
        <div class="secure-indicator">
            🔒 This error page is served securely via HTTPS with AWS Certificate Manager
        </div>
    </div>
</body>
</html>"""
    
    def _create_outputs(self) -> None:
        """Create CloudFormation outputs."""
        cdk.CfnOutput(
            self,
            "WebsiteBucketName",
            value=self.website_bucket.bucket_name,
            description="Name of the S3 bucket hosting the static website content",
        )
        
        cdk.CfnOutput(
            self,
            "DistributionId",
            value=self.distribution.distribution_id,
            description="CloudFront distribution ID",
        )
        
        cdk.CfnOutput(
            self,
            "DistributionDomainName",
            value=self.distribution.distribution_domain_name,
            description="CloudFront distribution domain name",
        )
        
        cdk.CfnOutput(
            self,
            "WebsiteURL",
            value=f"https://{self.domain_name}",
            description="URL of the secure static website",
        )
        
        cdk.CfnOutput(
            self,
            "SubdomainURL",
            value=f"https://{self.subdomain}",
            description="URL of the secure static website subdomain",
        )
        
        cdk.CfnOutput(
            self,
            "CertificateArn",
            value=self.certificate.certificate_arn,
            description="ARN of the ACM certificate",
        )
        
        cdk.CfnOutput(
            self,
            "HostedZoneId",
            value=self.hosted_zone.hosted_zone_id,
            description="Route 53 hosted zone ID",
        )