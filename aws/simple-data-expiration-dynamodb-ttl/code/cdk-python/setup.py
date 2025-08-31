"""
Setup configuration for DynamoDB TTL CDK Python application

This setup.py file configures the Python package for the DynamoDB TTL
demonstration application built with AWS CDK.
"""

import os
from setuptools import setup, find_packages

# Read the contents of README file
this_directory = os.path.abspath(os.path.dirname(__file__))
readme_file = os.path.join(this_directory, "README.md")
long_description = "DynamoDB TTL Data Expiration Automation CDK Application"

# Try to read README if it exists
if os.path.exists(readme_file):
    with open(readme_file, encoding="utf-8") as f:
        long_description = f.read()

# Package configuration
setup(
    name="dynamodb-ttl-cdk",
    version="1.0.0",
    description="AWS CDK Python application for DynamoDB TTL data expiration automation",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS CDK Generator",
    author_email="development@example.com",
    url="https://github.com/aws-samples/dynamodb-ttl-cdk",
    license="MIT",
    
    # Package discovery
    packages=find_packages(exclude=["tests*"]),
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Package dependencies
    install_requires=[
        "aws-cdk-lib==2.168.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.35.0",
        "botocore>=1.35.0",
    ],
    
    # Optional development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "mypy>=1.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "boto3-stubs[dynamodb,lambda,iam,cloudwatch,logs]>=1.35.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",  # For mocking AWS services
        ]
    },
    
    # Entry points for command-line scripts
    entry_points={
        "console_scripts": [
            "dynamodb-ttl-deploy=app:main",
        ],
    },
    
    # Package classifiers
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Database",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk", 
        "dynamodb",
        "ttl",
        "time-to-live",
        "data-expiration",
        "infrastructure",
        "cloud",
        "serverless",
        "automation"
    ],
    
    # Include additional files
    include_package_data=True,
    zip_safe=False,
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/dynamodb-ttl-cdk/issues",
        "Source": "https://github.com/aws-samples/dynamodb-ttl-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "AWS DynamoDB": "https://aws.amazon.com/dynamodb/",
    },
)