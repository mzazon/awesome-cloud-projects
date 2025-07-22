"""
AWS CDK Python setup configuration for S3 Data Archiving Solutions.

This setup.py file configures the Python package for the CDK application,
including dependencies, package metadata, and development requirements.
"""

import setuptools
from pathlib import Path

# Read the long description from README
long_description = """
# AWS S3 Data Archiving Solutions with CDK Python

This AWS CDK Python application creates a comprehensive data archiving solution using S3 lifecycle policies,
intelligent tiering, monitoring, and cost optimization features.

## Features

- **S3 Bucket Configuration**: Secure bucket with versioning, encryption, and public access blocking
- **Lifecycle Policies**: Automated transitions between storage classes for different data types
- **Intelligent Tiering**: Automatic cost optimization for media files based on access patterns
- **CloudWatch Monitoring**: Alarms for bucket size and object count with SNS notifications
- **S3 Analytics**: Storage class analysis for optimizing transition schedules
- **S3 Inventory**: Daily reports for storage usage tracking
- **IAM Security**: Least-privilege roles for automated lifecycle management

## Architecture

The solution creates different lifecycle policies for various data types:

- **Documents**: 30 days → IA, 90 days → Glacier, 365 days → Deep Archive
- **Logs**: 7 days → IA, 30 days → Glacier, 90 days → Deep Archive, 7 years expiration
- **Backups**: 1 day → IA, 30 days → Glacier
- **Media**: Immediate intelligent tiering with Archive and Deep Archive access

## Usage

```bash
# Install dependencies
pip install -r requirements.txt

# Deploy the stack
cdk deploy

# Clean up resources
cdk destroy
```

## Configuration

Configure the application using environment variables:

- `BUCKET_NAME`: Custom S3 bucket name (optional)
- `NOTIFICATION_EMAIL`: Email for CloudWatch alarm notifications (optional)
- `CDK_DEFAULT_ACCOUNT`: AWS account ID
- `CDK_DEFAULT_REGION`: AWS region

Alternatively, use CDK context:

```bash
cdk deploy --context bucketName=my-custom-bucket --context notificationEmail=admin@example.com
```
"""

# Read requirements from requirements.txt
requirements_path = Path(__file__).parent / "requirements.txt"
if requirements_path.exists():
    with open(requirements_path, "r", encoding="utf-8") as f:
        requirements = [
            line.strip()
            for line in f
            if line.strip() and not line.startswith("#") and not line.startswith("-")
        ]
else:
    requirements = [
        "aws-cdk-lib>=2.114.0",
        "constructs>=10.0.0,<11.0.0",
    ]

setuptools.setup(
    name="s3-data-archiving-cdk",
    version="1.0.0",
    author="AWS Solutions",
    author_email="aws-solutions@amazon.com",
    description="AWS CDK Python application for S3 data archiving solutions with lifecycle policies",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/aws-cdk-examples",
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/s3/latest/userguide/object-lifecycle-mgmt.html",
        "Source": "https://github.com/aws-samples/aws-cdk-examples",
        "Tracker": "https://github.com/aws-samples/aws-cdk-examples/issues",
    },
    packages=setuptools.find_packages(),
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Environment :: Console",
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
        "Topic :: System :: Archiving",
        "Topic :: System :: Storage",
        "Typing :: Typed",
    ],
    keywords=[
        "aws",
        "cdk",
        "s3",
        "lifecycle",
        "archiving",
        "storage",
        "intelligent-tiering",
        "cloudwatch",
        "monitoring",
        "cost-optimization",
        "data-management",
    ],
    python_requires=">=3.8",
    install_requires=requirements,
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "black>=22.0.0",
            "flake8>=4.0.0",
            "mypy>=0.991",
            "boto3>=1.26.0",
            "moto>=4.0.0",
            "types-boto3>=1.0.0",
            "types-setuptools>=65.0.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "boto3>=1.26.0",
            "moto>=4.0.0",
        ],
        "lint": [
            "black>=22.0.0",
            "flake8>=4.0.0",
            "mypy>=0.991",
            "types-boto3>=1.0.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "s3-archiving-cdk=app:main",
        ],
    },
    include_package_data=True,
    zip_safe=False,
    # CDK-specific metadata
    cdk_version=">=2.114.0",
    platforms=["any"],
)