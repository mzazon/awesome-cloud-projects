"""
Setup configuration for the Data Encryption CDK Python application.

This package implements comprehensive data encryption strategies for AWS
infrastructure using AWS CDK Python constructs.
"""

from setuptools import setup, find_packages

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setup(
    name="data-encryption-cdk",
    version="1.0.0",
    author="AWS CDK Team",
    author_email="aws-cdk@amazon.com",
    description="AWS CDK application for Data Encryption at Rest and in Transit",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws/aws-cdk",
    packages=find_packages(),
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Security :: Cryptography",
        "Typing :: Typed",
    ],
    python_requires=">=3.8",
    install_requires=[
        "aws-cdk-lib>=2.120.0",
        "constructs>=10.0.0",
        "boto3>=1.34.0",
        "botocore>=1.34.0",
    ],
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "bandit>=1.7.0",
            "safety>=3.0.0",
        ],
        "docs": [
            "sphinx>=7.0.0",
            "sphinx-rtd-theme>=1.3.0",
        ],
        "typing": [
            "types-boto3>=1.0.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "data-encryption-cdk=app:main",
        ],
    },
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "encryption",
        "security",
        "kms",
        "s3",
        "rds",
        "ec2",
        "infrastructure",
        "iac",
        "devops",
        "compliance",
        "hipaa",
        "pci-dss",
        "data-protection",
        "at-rest",
        "in-transit",
        "tls",
        "ssl",
        "certificates",
        "secrets-manager",
        "cloudtrail",
        "audit",
        "logging",
    ],
    project_urls={
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "CDK Workshop": "https://cdkworkshop.com/",
        "AWS CDK Examples": "https://github.com/aws-samples/aws-cdk-examples",
    },
    zip_safe=False,
)