"""
Setup configuration for Secure Static Website CDK Python application.

This setup.py file configures the Python package for the CDK application
that deploys secure static websites using AWS Certificate Manager,
CloudFront, and S3.
"""

import setuptools
from pathlib import Path

# Read long description from README if it exists
long_description = "CDK Python application for deploying secure static websites with AWS Certificate Manager"
readme_path = Path(__file__).parent / "README.md"
if readme_path.exists():
    with open(readme_path, "r", encoding="utf-8") as fh:
        long_description = fh.read()

# Read requirements from requirements.txt
requirements = []
requirements_path = Path(__file__).parent / "requirements.txt"
if requirements_path.exists():
    with open(requirements_path, "r", encoding="utf-8") as fh:
        requirements = [
            line.strip() 
            for line in fh 
            if line.strip() and not line.startswith("#")
        ]

setuptools.setup(
    name="secure-static-website-cdk",
    version="1.0.0",
    
    description="CDK Python application for secure static website hosting with ACM certificates",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS CDK Developer",
    author_email="developer@example.com",
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP :: HTTP Servers",
        "Topic :: Security :: Cryptography",
    ],
    
    keywords=[
        "aws", "cdk", "cloudformation", "infrastructure",
        "static-website", "ssl", "https", "certificate-manager",
        "cloudfront", "s3", "route53", "security", "cdn"
    ],
    
    packages=setuptools.find_packages(exclude=["tests*"]),
    
    install_requires=requirements,
    
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.5.0",
            "isort>=5.12.0",
        ],
        "docs": [
            "sphinx>=7.1.0",
            "sphinx-rtd-theme>=1.3.0",
        ],
    },
    
    entry_points={
        "console_scripts": [
            "deploy-secure-website=app:main",
        ],
    },
    
    project_urls={
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Source": "https://github.com/aws/aws-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "AWS Certificate Manager": "https://aws.amazon.com/certificate-manager/",
        "CloudFront": "https://aws.amazon.com/cloudfront/",
    },
    
    # Package data and manifest
    include_package_data=True,
    zip_safe=False,
    
    # CDK-specific metadata
    metadata={
        "cdk_version": ">=2.150.0",
        "aws_services": [
            "S3",
            "CloudFront", 
            "Certificate Manager",
            "Route 53",
            "IAM"
        ],
        "deployment_target": "AWS",
        "infrastructure_type": "Static Website Hosting",
        "security_features": [
            "HTTPS Enforcement",
            "SSL/TLS Certificates",
            "Origin Access Control",
            "Security Headers"
        ]
    }
)