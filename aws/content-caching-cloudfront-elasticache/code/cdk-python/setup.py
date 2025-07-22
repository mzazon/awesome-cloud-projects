"""
Setup configuration for Content Caching Strategies CDK Python Application

This setup.py file configures the Python package for the multi-tier caching
architecture using AWS CDK. It includes all necessary dependencies and
metadata for deployment and development.
"""

import os
from typing import List, Dict, Any

import setuptools


def get_long_description() -> str:
    """
    Read the long description from README.md file.
    
    Returns:
        Long description content for the package
    """
    try:
        with open("README.md", "r", encoding="utf-8") as fh:
            return fh.read()
    except FileNotFoundError:
        return """
        # Content Caching Strategies with CloudFront and ElastiCache
        
        A CDK Python application that demonstrates multi-tier caching architecture
        combining CloudFront for global content distribution with ElastiCache for
        application-level data caching.
        
        ## Features
        
        - S3 bucket for static content storage
        - ElastiCache Redis cluster for application-level caching
        - Lambda function implementing cache-aside pattern
        - API Gateway for RESTful endpoints
        - CloudFront distribution for global content delivery
        - CloudWatch monitoring and alarms
        
        ## Architecture
        
        This solution implements a comprehensive caching strategy that:
        1. Serves static content from CloudFront edge locations
        2. Caches API responses at CloudFront level
        3. Uses ElastiCache for application data caching
        4. Provides monitoring and alerting capabilities
        
        ## Deployment
        
        ```bash
        pip install -r requirements.txt
        cdk deploy
        ```
        """


def get_requirements() -> List[str]:
    """
    Read requirements from requirements.txt file.
    
    Returns:
        List of package requirements
    """
    try:
        with open("requirements.txt", "r", encoding="utf-8") as fh:
            requirements = []
            for line in fh:
                line = line.strip()
                if line and not line.startswith("#"):
                    # Remove version comments if any
                    if " #" in line:
                        line = line.split(" #")[0].strip()
                    requirements.append(line)
            return requirements
    except FileNotFoundError:
        # Fallback requirements if file not found
        return [
            "aws-cdk-lib==2.167.1",
            "constructs>=10.0.0,<11.0.0",
            "jsii>=1.103.1",
            "publication>=0.0.3",
            "typeguard>=2.13.3",
        ]


def get_dev_requirements() -> List[str]:
    """
    Get development requirements for testing and linting.
    
    Returns:
        List of development package requirements
    """
    return [
        "pytest>=7.0.0",
        "pytest-cov>=4.0.0",
        "black>=23.0.0",
        "flake8>=6.0.0",
        "mypy>=1.0.0",
        "sphinx>=7.0.0",
        "sphinx-rtd-theme>=2.0.0",
    ]


# Package metadata
PACKAGE_NAME = "content-caching-strategies"
VERSION = "1.0.0"
AUTHOR = "AWS CDK Developer"
AUTHOR_EMAIL = "developer@example.com"
DESCRIPTION = "Multi-tier caching strategy with CloudFront and ElastiCache using AWS CDK"
URL = "https://github.com/aws-samples/content-caching-strategies"

# Python version requirement
PYTHON_REQUIRES = ">=3.8"

# Package classifiers
CLASSIFIERS = [
    "Development Status :: 4 - Beta",
    "Intended Audience :: Developers",
    "Intended Audience :: System Administrators",
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
    "Topic :: System :: Networking",
    "Typing :: Typed",
]

# Keywords for package discovery
KEYWORDS = [
    "aws",
    "cdk",
    "cloudfront",
    "elasticache",
    "caching",
    "cdn",
    "redis",
    "lambda",
    "api-gateway",
    "s3",
    "cloud",
    "infrastructure",
    "content-delivery",
    "performance",
]

# Package configuration
setuptools.setup(
    name=PACKAGE_NAME,
    version=VERSION,
    author=AUTHOR,
    author_email=AUTHOR_EMAIL,
    description=DESCRIPTION,
    long_description=get_long_description(),
    long_description_content_type="text/markdown",
    url=URL,
    packages=setuptools.find_packages(exclude=["tests", "tests.*"]),
    classifiers=CLASSIFIERS,
    keywords=" ".join(KEYWORDS),
    python_requires=PYTHON_REQUIRES,
    install_requires=get_requirements(),
    extras_require={
        "dev": get_dev_requirements(),
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",  # AWS service mocking for tests
        ],
        "docs": [
            "sphinx>=7.0.0",
            "sphinx-rtd-theme>=2.0.0",
            "sphinx-autodoc-typehints>=1.0.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "content-caching-deploy=app:main",
        ],
    },
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.yml", "*.yaml", "*.json"],
    },
    zip_safe=False,
    # CDK-specific metadata
    project_urls={
        "Bug Reports": f"{URL}/issues",
        "Source": URL,
        "Documentation": f"{URL}/blob/main/README.md",
        "AWS CDK": "https://aws.amazon.com/cdk/",
        "CloudFront": "https://aws.amazon.com/cloudfront/",
        "ElastiCache": "https://aws.amazon.com/elasticache/",
    },
    # License information
    license="Apache License 2.0",
    license_files=["LICENSE"],
    # Platform information
    platforms=["any"],
    # Additional metadata
    maintainer=AUTHOR,
    maintainer_email=AUTHOR_EMAIL,
    download_url=f"{URL}/archive/v{VERSION}.tar.gz",
)