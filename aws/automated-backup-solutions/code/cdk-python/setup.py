"""
Setup configuration for the AWS CDK Python automated backup solution.

This module configures the Python package for the automated backup solution
using AWS CDK. It includes all necessary dependencies and package metadata
for enterprise-grade backup automation with cross-region replication.
"""

import setuptools

# Read the long description from README if it exists
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = (
        "AWS CDK Python application for automated backup solutions with AWS Backup. "
        "Features comprehensive backup automation with cross-region replication, "
        "monitoring, compliance controls, and immutable backup protection."
    )

# Package configuration
setuptools.setup(
    name="automated-backup-solutions-aws-backup",
    version="1.2.0",
    author="AWS Recipes Team",
    author_email="aws-recipes@example.com",
    description="Enterprise AWS CDK Python application for automated backup solutions with AWS Backup",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/aws-cdk-examples",
    packages=setuptools.find_packages(),
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "Intended Audience :: Information Technology",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Archiving :: Backup",
        "Topic :: System :: Recovery Tools",
        "Topic :: System :: Systems Administration",
        "Topic :: System :: Monitoring",
        "Typing :: Typed",
        "Framework :: AWS CDK",
        "Environment :: Console"
    ],
    python_requires=">=3.9",
    install_requires=[
        "aws-cdk-lib>=2.170.0,<3.0.0",
        "constructs>=10.4.0",
        "boto3>=1.35.0",
    ],
    extras_require={
        "dev": [
            "pytest>=8.0.0",
            "pytest-cov>=5.0.0",
            "black>=24.0.0",
            "flake8>=7.0.0",
            "mypy>=1.11.0",
            "types-boto3>=1.0.2",
            "boto3-stubs[backup,cloudwatch,config,iam,kms,s3,sns]>=1.35.0",
            "bandit>=1.7.0",
            "pre-commit>=3.6.0",
        ],
        "testing": [
            "moto[backup,cloudwatch,config,iam,kms,s3,sns]>=5.0.0",
            "pytest-mock>=3.12.0",
            "coverage[toml]>=7.4.0",
        ]
    },
    entry_points={
        "console_scripts": [
            "automated-backup-cdk=app:AutomatedBackupApp",
        ],
    },
    keywords=[
        "aws",
        "aws-cdk",
        "aws-backup",
        "backup",
        "automation",
        "disaster-recovery",
        "infrastructure-as-code",
        "cloudformation",
        "python",
        "enterprise",
        "compliance",
        "monitoring",
        "cross-region",
        "vault-lock",
        "immutable-backups"
    ],
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/aws-cdk-examples/issues",
        "Source": "https://github.com/aws-samples/aws-cdk-examples",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "AWS Backup Documentation": "https://docs.aws.amazon.com/aws-backup/",
        "Changelog": "https://github.com/aws-samples/aws-cdk-examples/blob/main/CHANGELOG.md",
    },
)