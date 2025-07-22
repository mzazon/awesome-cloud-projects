#!/usr/bin/env python3
"""
CDK Python application for Creating No-Code AI Applications with PartyRock and S3.

This CDK application creates the infrastructure needed to host a static website
that showcases AI applications built with Amazon PartyRock. The infrastructure
includes an S3 bucket for static website hosting and a CloudFront distribution
for global content delivery with HTTPS support.

Key components:
- S3 bucket with static website hosting enabled
- CloudFront distribution with HTTPS redirect
- Proper security configurations including encryption
- Public read access for website content

Author: AWS Recipes CDK Generator
Version: 1.0
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_s3 as s3,
    aws_cloudfront as cloudfront,
    aws_cloudfront_origins as origins,
    aws_s3_deployment as s3deploy,
    RemovalPolicy,
    CfnOutput,
    Duration
)
from constructs import Construct
import os


class PartyRockS3Stack(Stack):
    """
    CDK Stack for PartyRock AI application hosting infrastructure.
    
    Creates an S3 bucket for static website hosting and CloudFront distribution
    for global content delivery. Includes proper security configurations and
    HTTPS enforcement.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        """
        Initialize the PartyRock S3 stack.
        
        Args:
            scope: The parent construct
            construct_id: The unique identifier for this stack
            **kwargs: Additional keyword arguments passed to Stack
        """
        super().__init__(scope, construct_id, **kwargs)

        # Generate a unique suffix for resource names to avoid conflicts
        unique_suffix = self.node.try_get_context("unique_suffix") or "demo"
        
        # S3 bucket for static website hosting
        website_bucket = s3.Bucket(
            self, "PartyRockWebsiteBucket",
            bucket_name=f"partyrock-app-{unique_suffix}",
            website_index_document="index.html",
            website_error_document="error.html",
            public_read_access=True,
            block_public_access=s3.BlockPublicAccess(
                block_public_acls=False,
                block_public_policy=False,
                ignore_public_acls=False,
                restrict_public_buckets=False
            ),
            encryption=s3.BucketEncryption.S3_MANAGED,
            versioned=True,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True
        )

        # Add tags to the S3 bucket
        cdk.Tags.of(website_bucket).add("Purpose", "PartyRock AI App Hosting")
        cdk.Tags.of(website_bucket).add("Environment", "Demo")
        cdk.Tags.of(website_bucket).add("Project", "NoCode AI Applications")

        # Create the index.html content for the website
        index_html_content = """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AI Business Name Generator</title>
    <style>
        body { 
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; 
            margin: 0; 
            padding: 40px; 
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: #333;
        }
        .container { 
            max-width: 800px; 
            margin: 0 auto; 
            background: white;
            border-radius: 10px;
            padding: 40px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.1);
        }
        .header {
            text-align: center;
            margin-bottom: 40px;
        }
        .header h1 {
            color: #2c3e50;
            margin-bottom: 10px;
        }
        .header p {
            color: #7f8c8d;
            font-size: 18px;
        }
        .partyrock-embed { 
            border: 2px solid #3498db; 
            padding: 30px; 
            border-radius: 8px;
            background: #f8f9fa;
            margin: 30px 0;
            text-align: center;
        }
        .btn { 
            background: linear-gradient(45deg, #ff9900, #ff7700); 
            color: white; 
            padding: 15px 30px; 
            text-decoration: none; 
            border-radius: 25px;
            display: inline-block;
            font-weight: bold;
            transition: transform 0.2s;
            box-shadow: 0 4px 15px rgba(255, 153, 0, 0.3);
        }
        .btn:hover {
            transform: translateY(-2px);
            box-shadow: 0 6px 20px rgba(255, 153, 0, 0.4);
        }
        .features {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin-top: 40px;
        }
        .feature {
            background: #f8f9fa;
            padding: 20px;
            border-radius: 8px;
            border-left: 4px solid #3498db;
        }
        .feature h3 {
            color: #2c3e50;
            margin-top: 0;
        }
        .tech-stack {
            background: #e8f4f8;
            padding: 20px;
            border-radius: 8px;
            margin-top: 30px;
        }
        .tech-stack h3 {
            color: #2c3e50;
            margin-top: 0;
        }
        .tech-badges {
            display: flex;
            flex-wrap: wrap;
            gap: 10px;
            margin-top: 15px;
        }
        .badge {
            background: #3498db;
            color: white;
            padding: 5px 12px;
            border-radius: 15px;
            font-size: 12px;
            font-weight: bold;
        }
        .aws-badge { background: #ff9900; }
        .ai-badge { background: #9b59b6; }
        .web-badge { background: #27ae60; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 AI-Powered Business Name Generator</h1>
            <p>Experience the power of generative AI with our no-code application built using Amazon PartyRock and hosted on AWS infrastructure.</p>
        </div>
        
        <div class="partyrock-embed">
            <h2>✨ Try the AI Application</h2>
            <p>Click the button below to access our intelligent business name generator powered by Amazon Bedrock foundation models:</p>
            <a href="#" class="btn" onclick="showPartyRockInfo()">
                🎯 Launch AI App
            </a>
            <p style="margin-top: 15px; font-size: 14px; color: #666;">
                <em>Replace the href="#" with your actual PartyRock application URL</em>
            </p>
        </div>
        
        <div class="features">
            <div class="feature">
                <h3>🎨 AI-Powered Generation</h3>
                <p>Leverages Amazon Bedrock's Claude and other foundation models for intelligent name suggestions.</p>
            </div>
            <div class="feature">
                <h3>🎯 Industry-Specific</h3>
                <p>Tailored suggestions based on your specific industry and business vertical.</p>
            </div>
            <div class="feature">
                <h3>👥 Audience-Aware</h3>
                <p>Considers your target audience demographics and preferences.</p>
            </div>
            <div class="feature">
                <h3>🎨 Visual Concepts</h3>
                <p>Generates logo and branding concepts to complement your new business name.</p>
            </div>
        </div>

        <div class="tech-stack">
            <h3>🛠️ Technology Stack</h3>
            <p>This application demonstrates modern cloud architecture using AWS services:</p>
            <div class="tech-badges">
                <span class="badge ai-badge">Amazon PartyRock</span>
                <span class="badge ai-badge">Amazon Bedrock</span>
                <span class="badge aws-badge">Amazon S3</span>
                <span class="badge aws-badge">Amazon CloudFront</span>
                <span class="badge web-badge">Static Website</span>
                <span class="badge web-badge">Global CDN</span>
                <span class="badge aws-badge">HTTPS/SSL</span>
            </div>
        </div>
        
        <div style="text-align: center; margin-top: 40px; padding-top: 30px; border-top: 1px solid #ecf0f1;">
            <p style="color: #7f8c8d;">
                Built with ❤️ using AWS CDK and Amazon PartyRock
            </p>
        </div>
    </div>

    <script>
        function showPartyRockInfo() {
            alert('Please replace the href="#" in the Launch AI App button with your actual PartyRock application URL after creating your application on https://partyrock.aws/');
        }
    </script>
</body>
</html>"""

        # Deploy the website content to S3
        s3deploy.BucketDeployment(
            self, "PartyRockWebsiteDeployment",
            sources=[
                s3deploy.Source.data("index.html", index_html_content),
                s3deploy.Source.data("error.html", """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Page Not Found - AI Business Name Generator</title>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; padding: 50px; }
        .error-container { max-width: 600px; margin: 0 auto; }
        .error-code { font-size: 72px; color: #ff9900; font-weight: bold; }
        .error-message { font-size: 24px; color: #333; margin: 20px 0; }
        .btn { background: #ff9900; color: white; padding: 10px 20px; 
               text-decoration: none; border-radius: 5px; }
    </style>
</head>
<body>
    <div class="error-container">
        <div class="error-code">404</div>
        <div class="error-message">Page Not Found</div>
        <p>The page you're looking for doesn't exist.</p>
        <a href="/" class="btn">Return Home</a>
    </div>
</body>
</html>""")
            ],
            destination_bucket=website_bucket,
            retain_on_delete=False
        )

        # CloudFront Origin Access Control for secure S3 access
        origin_access_control = cloudfront.S3OriginAccessControl(
            self, "PartyRockOAC",
            signing=cloudfront.Signing.SIGV4_NO_OVERRIDE
        )

        # CloudFront distribution for global content delivery
        distribution = cloudfront.Distribution(
            self, "PartyRockDistribution",
            default_behavior=cloudfront.BehaviorOptions(
                origin=origins.S3StaticWebsiteOrigin(website_bucket),
                viewer_protocol_policy=cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
                allowed_methods=cloudfront.AllowedMethods.ALLOW_GET_HEAD_OPTIONS,
                cached_methods=cloudfront.CachedMethods.CACHE_GET_HEAD_OPTIONS,
                cache_policy=cloudfront.CachePolicy.CACHING_OPTIMIZED,
                origin_request_policy=cloudfront.OriginRequestPolicy.CORS_S3_ORIGIN,
                response_headers_policy=cloudfront.ResponseHeadersPolicy.SECURITY_HEADERS,
                compress=True
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
            enabled=True,
            comment=f"PartyRock AI Application CDN - {unique_suffix}",
            geo_restriction=cloudfront.GeoRestriction.allowlist()
        )

        # Add tags to CloudFront distribution
        cdk.Tags.of(distribution).add("Purpose", "PartyRock AI App CDN")
        cdk.Tags.of(distribution).add("Environment", "Demo")
        cdk.Tags.of(distribution).add("Project", "NoCode AI Applications")

        # Outputs for easy access to deployed resources
        CfnOutput(
            self, "WebsiteBucketName",
            value=website_bucket.bucket_name,
            description="Name of the S3 bucket hosting the website",
            export_name=f"PartyRock-BucketName-{unique_suffix}"
        )

        CfnOutput(
            self, "WebsiteBucketUrl",
            value=website_bucket.bucket_website_url,
            description="URL of the S3 static website",
            export_name=f"PartyRock-BucketUrl-{unique_suffix}"
        )

        CfnOutput(
            self, "CloudFrontDistributionId",
            value=distribution.distribution_id,
            description="CloudFront distribution ID",
            export_name=f"PartyRock-DistributionId-{unique_suffix}"
        )

        CfnOutput(
            self, "CloudFrontUrl",
            value=f"https://{distribution.distribution_domain_name}",
            description="CloudFront distribution URL (HTTPS)",
            export_name=f"PartyRock-CloudFrontUrl-{unique_suffix}"
        )

        CfnOutput(
            self, "PartyRockPlatformUrl",
            value="https://partyrock.aws/",
            description="Amazon PartyRock platform URL for creating AI applications",
            export_name=f"PartyRock-PlatformUrl-{unique_suffix}"
        )


# CDK App initialization
app = cdk.App()

# Get unique suffix from context or generate one
unique_suffix = app.node.try_get_context("unique_suffix")
if not unique_suffix:
    import secrets
    import string
    unique_suffix = ''.join(secrets.choice(string.ascii_lowercase + string.digits) for _ in range(6))

# Create the stack with environment-specific configuration
PartyRockS3Stack(
    app, "PartyRockS3Stack",
    env=cdk.Environment(
        account=os.getenv('CDK_DEFAULT_ACCOUNT'),
        region=os.getenv('CDK_DEFAULT_REGION', 'us-east-1')
    ),
    description="Infrastructure for hosting PartyRock AI applications with S3 and CloudFront"
)

# Add stack-level tags
cdk.Tags.of(app).add("Project", "PartyRock AI Applications")
cdk.Tags.of(app).add("CreatedBy", "AWS CDK")
cdk.Tags.of(app).add("Purpose", "No-Code AI Application Hosting")

app.synth()