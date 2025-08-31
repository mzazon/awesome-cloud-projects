"""
Setup configuration for Persistent Customer Support Agent CDK Application

This package provides AWS CDK Infrastructure as Code for deploying a complete
customer support system with persistent memory capabilities using Amazon
Bedrock AgentCore, Lambda, DynamoDB, and API Gateway.
"""

import setuptools
from typing import List


def read_requirements() -> List[str]:
    """Read requirements from requirements.txt file"""
    try:
        with open("requirements.txt", "r", encoding="utf-8") as f:
            requirements = []
            for line in f:
                line = line.strip()
                # Skip comments and empty lines
                if line and not line.startswith("#"):
                    # Remove inline comments
                    if "#" in line:
                        line = line.split("#")[0].strip()
                    requirements.append(line)
            return requirements
    except FileNotFoundError:
        return [
            "aws-cdk-lib>=2.160.0,<3.0.0",
            "constructs>=10.0.0,<11.0.0",
            "boto3>=1.34.0",
            "botocore>=1.34.0"
        ]


def read_long_description() -> str:
    """Read the long description from README file"""
    try:
        with open("README.md", "r", encoding="utf-8") as f:
            return f.read()
    except FileNotFoundError:
        return """
# Persistent Customer Support Agent with Bedrock AgentCore Memory

This CDK application deploys a complete customer support system with persistent
memory capabilities using Amazon Bedrock AgentCore Memory, Lambda functions,
DynamoDB, and API Gateway.

## Features

- Persistent conversation memory across sessions
- Intelligent customer context retrieval
- Serverless architecture with auto-scaling
- Secure API access with CORS support
- Customer metadata storage and management
- Integration with Bedrock foundation models

## Architecture

The solution includes:
- **Amazon Bedrock AgentCore Memory**: For persistent conversation context
- **AWS Lambda**: Serverless compute for support agent logic
- **Amazon DynamoDB**: Customer metadata and preferences storage
- **Amazon API Gateway**: Secure REST API for client access
- **AWS IAM**: Least privilege security model
- **Amazon CloudWatch**: Logging and monitoring

## Deployment

```bash
pip install -r requirements.txt
cdk deploy
```

See the main recipe documentation for complete setup instructions.
"""


setuptools.setup(
    name="persistent-customer-support-agentcore",
    version="1.0.0",
    author="AWS CDK Recipe Generator",
    author_email="recipes@example.com",
    description="CDK app for persistent customer support with Bedrock AgentCore Memory",
    long_description=read_long_description(),
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/cloud-recipes",
    project_urls={
        "Bug Tracker": "https://github.com/aws-samples/cloud-recipes/issues",
        "Documentation": "https://github.com/aws-samples/cloud-recipes",
        "Source Code": "https://github.com/aws-samples/cloud-recipes",
    },
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
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
        "Topic :: Utilities",
        "Typing :: Typed",
    ],
    package_dir={"": "."},
    packages=setuptools.find_packages(where="."),
    python_requires=">=3.8",
    install_requires=read_requirements(),
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "types-requests",
            "boto3-stubs[bedrock-runtime,bedrock-agentcore,dynamodb,lambda,apigateway]",
        ],
        "docs": [
            "sphinx>=4.0.0",
            "sphinx-rtd-theme>=1.0.0",
            "sphinxcontrib-mermaid>=0.7.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "cdk-deploy=app:main",
        ],
    },
    keywords=[
        "aws",
        "cdk",
        "bedrock",
        "agentcore",
        "customer-support",
        "ai",
        "lambda",
        "dynamodb",
        "apigateway",
        "serverless",
        "memory",
        "persistent",
    ],
    zip_safe=False,
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
)