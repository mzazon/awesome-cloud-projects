"""
Setup configuration for S3 Cross-Region Replication CDK Python application.

This setup.py file provides package configuration for the CDK application,
including dependencies, metadata, and installation requirements for production-ready
S3 cross-region replication with encryption and access controls.
"""

from setuptools import setup, find_packages
import pathlib

here = pathlib.Path(__file__).parent.resolve()

# Read requirements from requirements.txt
with open(here / 'requirements.txt', 'r', encoding='utf-8') as f:
    requirements = [
        line.strip() for line in f 
        if line.strip() and not line.startswith('#') and not line.startswith('-')
    ]

# Read README if it exists
try:
    with open(here / 'README.md', 'r', encoding='utf-8') as f:
        long_description = f.read()
except FileNotFoundError:
    long_description = """
    AWS CDK Python application for S3 Cross-Region Replication with Encryption and Access Controls.
    
    This application implements a comprehensive S3 cross-region replication solution with:
    - KMS encryption in both source and destination regions
    - IAM roles with least privilege principles
    - CloudWatch monitoring and alarms
    - Secure bucket policies enforcing encryption
    - Complete cross-region replication configuration
    """

setup(
    name="s3-cross-region-replication-cdk",
    version="1.0.0",
    
    description="AWS CDK Python application for S3 Cross-Region Replication with Encryption and Access Controls",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS CDK Recipe Generator",
    author_email="cdk-recipes@example.com",
    
    url="https://github.com/aws-samples/aws-cdk-examples",
    
    packages=find_packages(exclude=["tests*", "*.tests", "*.tests.*", "tests.*"]),
    
    install_requires=requirements,
    
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.0.0",
            "black>=24.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "isort>=5.12.0",
            "pylint>=3.0.0"
        ],
        "test": [
            "pytest>=7.4.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",
            "boto3-stubs[essential]>=1.35.0"
        ]
    },
    
    python_requires=">=3.8",
    
    classifiers=[
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
        "Topic :: System :: Archiving :: Backup",
        "Topic :: Security :: Cryptography",
        "Typing :: Typed"
    ],
    
    keywords=[
        "aws",
        "cdk",
        "s3",
        "cross-region-replication",
        "kms",
        "encryption",
        "security",
        "disaster-recovery",
        "backup",
        "compliance",
        "infrastructure-as-code",
        "cloudwatch",
        "iam"
    ],
    
    entry_points={
        "console_scripts": [
            "s3-crr-deploy=app:main",
        ],
    },
    
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws-samples/aws-cdk-examples",
        "Bug Reports": "https://github.com/aws-samples/aws-cdk-examples/issues",
        "AWS CDK": "https://aws.amazon.com/cdk/",
        "AWS S3": "https://aws.amazon.com/s3/",
    },
    
    zip_safe=False,
    include_package_data=True,
)