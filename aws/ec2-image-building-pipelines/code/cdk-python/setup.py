"""
Setup configuration for EC2 Image Builder Pipeline CDK Python Application

This setup.py file configures the Python package for the CDK application that creates
EC2 Image Builder pipelines for automated AMI creation with web server configurations.
"""

from setuptools import setup, find_packages

# Read requirements from requirements.txt
with open("requirements.txt", "r", encoding="utf-8") as f:
    requirements = [
        line.strip()
        for line in f
        if line.strip() and not line.startswith("#")
    ]

# Package metadata
PACKAGE_NAME = "ec2-image-builder-pipeline"
VERSION = "1.0.0"
DESCRIPTION = "AWS CDK Python application for EC2 Image Builder pipelines"
LONG_DESCRIPTION = """
# EC2 Image Builder Pipeline CDK Application

This AWS CDK Python application creates a complete EC2 Image Builder pipeline for 
automated AMI creation with web server configurations, security hardening, and 
multi-region distribution capabilities.

## Features

- Automated web server AMI creation with Apache configuration
- Security hardening with best practices
- Comprehensive testing and validation
- Multi-region AMI distribution
- Scheduled builds with dependency tracking
- SNS notifications for build status
- CloudWatch logging and S3 log storage
- IAM roles with least privilege principles

## Components

- **Build Components**: Install and configure Apache web server
- **Test Components**: Comprehensive validation and security testing
- **Image Recipe**: Combines components with Amazon Linux 2 base image
- **Infrastructure Configuration**: Secure build environment setup
- **Distribution Configuration**: Multi-region AMI deployment
- **Pipeline**: Automated scheduling and orchestration

## Usage

Deploy the CDK application to create the complete Image Builder pipeline:

```bash
pip install -r requirements.txt
cdk deploy
```

The pipeline will automatically create web server AMIs on a weekly schedule
and distribute them to the configured regions.
"""

AUTHOR = "AWS CDK Generator"
AUTHOR_EMAIL = "cdk-generator@example.com"
URL = "https://github.com/example/ec2-image-builder-pipeline"

# Classifiers for package categorization
CLASSIFIERS = [
    "Development Status :: 5 - Production/Stable",
    "Intended Audience :: Developers",
    "Intended Audience :: System Administrators",
    "License :: OSI Approved :: MIT License",
    "Operating System :: OS Independent",
    "Programming Language :: Python :: 3",
    "Programming Language :: Python :: 3.8",
    "Programming Language :: Python :: 3.9",
    "Programming Language :: Python :: 3.10",
    "Programming Language :: Python :: 3.11",
    "Programming Language :: Python :: 3.12",
    "Topic :: Software Development :: Libraries :: Python Modules",
    "Topic :: System :: Systems Administration",
    "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
    "Framework :: AWS CDK",
    "Framework :: AWS CDK :: 2",
]

# Keywords for package discovery
KEYWORDS = [
    "aws",
    "cdk",
    "ec2",
    "image-builder",
    "ami",
    "automation",
    "web-server",
    "apache",
    "infrastructure",
    "cloud",
    "devops",
    "pipeline",
]

setup(
    name=PACKAGE_NAME,
    version=VERSION,
    description=DESCRIPTION,
    long_description=LONG_DESCRIPTION,
    long_description_content_type="text/markdown",
    author=AUTHOR,
    author_email=AUTHOR_EMAIL,
    url=URL,
    packages=find_packages(exclude=["tests", "tests.*"]),
    include_package_data=True,
    zip_safe=False,
    install_requires=requirements,
    python_requires=">=3.8",
    classifiers=CLASSIFIERS,
    keywords=" ".join(KEYWORDS),
    project_urls={
        "Documentation": f"{URL}/blob/main/README.md",
        "Source": URL,
        "Tracker": f"{URL}/issues",
    },
    entry_points={
        "console_scripts": [
            "image-builder-pipeline=app:main",
        ],
    },
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "bandit>=1.7.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",
        ],
    },
    package_data={
        PACKAGE_NAME: [
            "*.json",
            "*.yaml",
            "*.yml",
            "components/*.yaml",
            "templates/*.json",
        ],
    },
)