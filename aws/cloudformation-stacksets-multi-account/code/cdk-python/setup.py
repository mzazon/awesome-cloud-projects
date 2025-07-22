#!/usr/bin/env python3
"""
Setup configuration for CloudFormation StackSets Multi-Account Multi-Region CDK application.

This setup.py file configures the Python package for the CDK application that demonstrates
organization-wide infrastructure governance using CloudFormation StackSets with AWS Organizations
integration, automated deployment pipelines, and comprehensive monitoring.
"""

from setuptools import setup, find_packages

# Read the contents of README file
from pathlib import Path
this_directory = Path(__file__).parent
long_description = (this_directory / "README.md").read_text() if (this_directory / "README.md").exists() else ""

setup(
    name="stacksets-multi-account-cdk",
    version="1.0.0",
    description="CDK Python application for CloudFormation StackSets Multi-Account Multi-Region Management",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS Recipe Generator",
    author_email="recipes@aws.com",
    url="https://github.com/aws-samples/cloudformation-stacksets-multi-account-multi-region",
    
    # Package discovery
    packages=find_packages(),
    
    # Include non-Python files
    include_package_data=True,
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=[
        "aws-cdk-lib>=2.168.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.34.0,<2.0.0",
        "botocore>=1.29.0,<2.0.0",
    ],
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.7.0",
            "flake8>=6.0.0",
            "mypy>=1.5.0",
            "pre-commit>=3.4.0",
            "bandit>=1.7.5",
            "safety>=2.3.0",
            "cdk-nag>=2.27.0",
        ],
        "docs": [
            "sphinx>=7.1.0",
            "sphinx-rtd-theme>=1.3.0",
        ],
        "test": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "moto>=4.2.0",  # AWS service mocking
            "boto3-stubs[cloudformation,iam,s3,sns,lambda,cloudwatch,logs,events]>=1.34.0",
        ],
    },
    
    # Entry points for command line tools
    entry_points={
        "console_scripts": [
            "stacksets-deploy=app:main",
        ],
    },
    
    # Package classification
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
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Utilities",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "cloudformation",
        "stacksets",
        "multi-account",
        "multi-region",
        "organizations",
        "governance",
        "infrastructure",
        "devops",
        "automation",
    ],
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/cloudformation-stacksets-multi-account-multi-region/issues",
        "Source": "https://github.com/aws-samples/cloudformation-stacksets-multi-account-multi-region",
        "Documentation": "https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/what-is-cfnstacksets.html",
        "AWS CDK": "https://docs.aws.amazon.com/cdk/",
        "AWS CloudFormation": "https://docs.aws.amazon.com/cloudformation/",
        "AWS Organizations": "https://docs.aws.amazon.com/organizations/",
    },
    
    # License
    license="Apache-2.0",
    
    # Zip safe
    zip_safe=False,
    
    # Package data
    package_data={
        "": ["*.md", "*.txt", "*.yaml", "*.yml", "*.json"],
    },
    
    # Manifest template
    include_package_data=True,
)