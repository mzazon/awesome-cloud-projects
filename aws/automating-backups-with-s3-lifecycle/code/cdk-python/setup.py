"""
Setup configuration for Scheduled Backups with Amazon S3 CDK Python application

This setup.py file configures the Python package for the CDK application,
including dependencies, package metadata, and installation requirements.
"""

from setuptools import setup, find_packages

# Read requirements from requirements.txt
with open("requirements.txt", "r", encoding="utf-8") as fh:
    requirements = [line.strip() for line in fh if line.strip() and not line.startswith("#")]

# Read long description from README if it exists
long_description = """
# Scheduled Backups with Amazon S3 - CDK Python Application

This AWS CDK Python application creates an automated backup solution using:

- **Amazon S3**: Primary and backup buckets with versioning and lifecycle policies
- **AWS Lambda**: Backup function that copies objects between buckets
- **Amazon EventBridge**: Scheduled rule that triggers backups daily
- **AWS IAM**: Properly scoped roles and policies for secure access
- **Amazon CloudWatch**: Logging and monitoring for backup operations

## Features

- **Automated Scheduling**: Daily backups at 1:00 AM UTC (configurable)
- **Cost Optimization**: Lifecycle policies transition old backups to cheaper storage
- **Versioning**: Backup bucket maintains multiple versions of objects
- **Security**: Least privilege IAM roles and SSL-encrypted S3 buckets
- **Monitoring**: CloudWatch logs for backup operation tracking

## Architecture

The solution uses EventBridge to trigger a Lambda function on a schedule.
The Lambda function lists all objects in the primary bucket and copies
them to the backup bucket. Lifecycle policies automatically manage
storage costs by transitioning older backups to Standard-IA and Glacier.

## Prerequisites

- AWS CLI configured with appropriate permissions
- Python 3.9 or later
- AWS CDK CLI installed (`npm install -g aws-cdk`)

## Deployment

```bash
# Install dependencies
pip install -r requirements.txt

# Bootstrap CDK (first time only)
cdk bootstrap

# Deploy the stack
cdk deploy
```

## Customization

You can customize the backup schedule, lifecycle policies, and other
parameters by modifying the CDK code in `app.py`.
"""

setup(
    name="scheduled-backups-s3-cdk",
    version="1.0.0",
    description="AWS CDK Python application for scheduled S3 backups",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS CDK Python Generator",
    author_email="noreply@example.com",
    url="https://github.com/aws-samples/scheduled-backups-s3-cdk",
    packages=find_packages(),
    
    # Python version requirement
    python_requires=">=3.9",
    
    # Package dependencies
    install_requires=requirements,
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",  # AWS service mocking for tests
        ],
    },
    
    # Package classification
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
        "Topic :: System :: Archiving :: Backup",
        "Topic :: System :: Systems Administration",
    ],
    
    # Entry points for command line tools
    entry_points={
        "console_scripts": [
            "deploy-scheduled-backups=app:main",
        ],
    },
    
    # Additional package data
    package_data={
        "": ["*.txt", "*.md", "*.json"],
    },
    
    # Include additional files
    include_package_data=True,
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "s3",
        "backup",
        "lambda",
        "eventbridge",
        "automation",
        "infrastructure",
        "cloud",
        "storage",
    ],
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/scheduled-backups-s3-cdk/issues",
        "Source": "https://github.com/aws-samples/scheduled-backups-s3-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "AWS CDK Guide": "https://docs.aws.amazon.com/cdk/v2/guide/",
    },
    
    # Zip safe setting
    zip_safe=False,
)