"""
Setup configuration for CDK Python Content Delivery Network application.

This setup.py file configures the Python package for the CDK application
that implements a Content Delivery Network with CloudFront and S3.
"""

from setuptools import setup, find_packages

# Read requirements from requirements.txt
with open("requirements.txt", "r", encoding="utf-8") as fh:
    requirements = [
        line.strip() for line in fh.readlines() 
        if line.strip() and not line.startswith("#")
    ]

# Read README for long description
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = """
    CDK Python application for Content Delivery Networks with CloudFront S3.
    
    This application creates a complete CDN solution including:
    - S3 bucket for content storage with proper security configuration
    - CloudFront distribution with Origin Access Control (OAC)
    - Multiple cache behaviors optimized for different content types
    - CloudWatch alarms for monitoring distribution performance
    - S3 bucket for CloudFront access logs
    """

setup(
    name="content-delivery-network-cdk",
    version="1.0.0",
    author="AWS CDK Team",
    author_email="aws-cdk@amazon.com",
    description="CDK Python application for Content Delivery Networks with CloudFront S3",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/aws-cdk-examples",
    packages=find_packages(),
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
    ],
    python_requires=">=3.8",
    install_requires=requirements,
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "isort>=5.12.0",
            "mypy>=1.5.0",
            "pre-commit>=3.0.0",
        ],
        "docs": [
            "sphinx>=4.0.0",
            "sphinx-rtd-theme>=1.0.0",
            "myst-parser>=0.18.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "cdk-cdn=app:main",
        ],
    },
    keywords=[
        "aws",
        "cdk",
        "cloudfront",
        "s3",
        "cdn",
        "content-delivery",
        "networking",
        "infrastructure",
        "python",
    ],
    project_urls={
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Source": "https://github.com/aws/aws-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "CDK Workshop": "https://cdkworkshop.com/",
    },
    zip_safe=False,
    include_package_data=True,
    package_data={
        "": [
            "*.json",
            "*.yaml",
            "*.yml",
            "*.md",
            "*.txt",
        ],
    },
)