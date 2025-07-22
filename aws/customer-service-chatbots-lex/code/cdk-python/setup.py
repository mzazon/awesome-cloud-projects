"""
Setup configuration for Customer Service Chatbot CDK Application

This package contains AWS CDK code for deploying a customer service chatbot
solution using Amazon Lex V2, AWS Lambda, and Amazon DynamoDB.

Author: AWS Recipe Generator
Version: 1.0
License: MIT
"""

import setuptools
from pathlib import Path

# Read the README file for long description
long_description = """
# Customer Service Chatbot CDK Application

This AWS CDK application deploys a complete customer service chatbot solution featuring:

## Components
- **Amazon Lex V2**: Conversational AI platform with natural language understanding
- **AWS Lambda**: Serverless compute for intent fulfillment and backend integration
- **Amazon DynamoDB**: NoSQL database for customer data storage
- **IAM Roles**: Secure access controls following least privilege principles

## Features
- Multi-intent support (Order Status, Billing Inquiry, Product Information)
- Real-time customer data integration
- Slot-filling for natural conversation flow
- Production-ready error handling and logging
- Comprehensive testing capabilities

## Quick Start

1. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```

2. Configure AWS credentials:
   ```bash
   aws configure
   ```

3. Deploy the stack:
   ```bash
   cdk deploy
   ```

4. Test the chatbot:
   ```bash
   aws lexv2-runtime recognize-text \\
       --bot-id <BOT_ID> \\
       --bot-alias-id TSTALIASID \\
       --locale-id en_US \\
       --session-id test-session \\
       --text "What is my order status for customer 12345?"
   ```

## Architecture

The solution implements a serverless architecture pattern optimized for:
- Automatic scaling based on conversation volume
- Cost-effective pay-per-use pricing model
- High availability across multiple AZs
- Real-time response capabilities

## Security

All components follow AWS security best practices:
- IAM roles with minimal required permissions
- Encryption at rest and in transit
- VPC isolation options (configurable)
- CloudTrail logging for audit compliance

## Cost Optimization

- Amazon Lex V2 free tier: 10,000 text requests/month
- Lambda free tier: 1M requests and 400,000 GB-seconds/month
- DynamoDB on-demand pricing: Pay only for actual usage
- No idle resource costs with serverless architecture

For detailed documentation, visit the AWS CDK Developer Guide.
"""

setuptools.setup(
    name="customer-service-chatbot-cdk",
    version="1.0.0",
    
    description="AWS CDK application for customer service chatbot using Amazon Lex V2",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS Recipe Generator",
    author_email="recipes@aws.example.com",
    
    url="https://github.com/aws-samples/customer-service-chatbot-cdk",
    
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Utilities",
        "Typing :: Typed",
    ],
    
    keywords=[
        "aws",
        "cdk",
        "amazon-lex",
        "chatbot",
        "conversational-ai",
        "customer-service",
        "serverless",
        "lambda",
        "dynamodb",
        "infrastructure-as-code"
    ],
    
    packages=setuptools.find_packages(where=".", exclude=["tests*"]),
    
    python_requires=">=3.8",
    
    install_requires=[
        "aws-cdk-lib>=2.100.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.26.0",
        "botocore>=1.29.0",
    ],
    
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "types-boto3>=1.0.0",
            "boto3-stubs[dynamodb,lex-runtime-v2,lambda]>=1.26.0",
        ],
        "cli": [
            "awscli>=2.7.0",
        ]
    },
    
    entry_points={
        "console_scripts": [
            "deploy-chatbot=app:main",
        ],
    },
    
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/customer-service-chatbot-cdk/issues",
        "Documentation": "https://docs.aws.amazon.com/cdk/latest/guide/",
        "Source": "https://github.com/aws-samples/customer-service-chatbot-cdk",
        "AWS CDK": "https://aws.amazon.com/cdk/",
        "Amazon Lex": "https://aws.amazon.com/lex/",
    },
    
    include_package_data=True,
    zip_safe=False,
    
    # Package metadata for PyPI
    license="MIT",
    platforms=["any"],
    
    # Additional metadata
    package_data={
        "": ["*.md", "*.txt", "*.yaml", "*.yml", "*.json"],
    },
)