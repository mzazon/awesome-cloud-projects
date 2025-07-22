#!/usr/bin/env python3
"""
CDK Python Application for Securing Websites with SSL Certificates
================================================================================

This CDK application implements a secure static website hosting solution using:
- Amazon S3 for static content storage
- AWS Certificate Manager (ACM) for SSL/TLS certificates
- Amazon CloudFront for global content delivery with HTTPS
- Route 53 for DNS management and certificate validation

Architecture:
- S3 bucket configured for static website hosting
- ACM certificate with DNS validation
- CloudFront distribution with Origin Access Control (OAC)
- Route 53 records for domain resolution

Security Features:
- HTTPS-only access (HTTP redirects to HTTPS)
- Origin Access Control prevents direct S3 access
- Automatic certificate renewal via ACM
- Modern TLS protocols only
"""

import os
from typing import Optional

import aws_cdk as cdk
from aws_cdk import (
    App,
    Environment,
    Stack,
    StackProps,
)

from constructs import Construct
from stacks.secure_static_website_stack import SecureStaticWebsiteStack


class SecureStaticWebsiteApp(App):
    """
    CDK Application for deploying secure static websites with ACM certificates.
    
    This application creates a complete infrastructure stack for hosting
    static websites with enterprise-grade security and performance.
    """
    
    def __init__(self) -> None:
        super().__init__()
        
        # Environment configuration
        account = os.environ.get("CDK_DEFAULT_ACCOUNT")
        region = os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
        
        # Domain configuration (customize these values)
        domain_name = os.environ.get("DOMAIN_NAME", "example.com")
        subdomain = os.environ.get("SUBDOMAIN", f"www.{domain_name}")
        
        # Environment for the stack
        env = Environment(
            account=account,
            region=region
        )
        
        # Create the main stack
        SecureStaticWebsiteStack(
            self,
            "SecureStaticWebsiteStack",
            domain_name=domain_name,
            subdomain=subdomain,
            env=env,
            description="Secure static website hosting with ACM certificates and CloudFront",
            tags={
                "Project": "SecureStaticWebsite",
                "Purpose": "Static website hosting with SSL/TLS",
                "Environment": "production",
                "ManagedBy": "CDK"
            }
        )


def main() -> None:
    """Main entry point for the CDK application."""
    app = SecureStaticWebsiteApp()
    app.synth()


if __name__ == "__main__":
    main()