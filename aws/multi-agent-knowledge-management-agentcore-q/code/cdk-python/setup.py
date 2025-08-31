#!/usr/bin/env python3
"""
Setup script for Multi-Agent Knowledge Management CDK Application

This setup.py file configures the Python package for the CDK application
that deploys a multi-agent knowledge management system using Amazon Bedrock
AgentCore, Q Business, and supporting AWS services.
"""

import setuptools
from pathlib import Path

# Read the README file for long description
readme_path = Path(__file__).parent / "README.md"
long_description = readme_path.read_text(encoding="utf-8") if readme_path.exists() else ""

# Define package metadata
setuptools.setup(
    name="multi-agent-knowledge-management-cdk",
    version="1.0.0",
    description="CDK application for Multi-Agent Knowledge Management with Bedrock AgentCore and Q Business",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS CDK Development Team",
    author_email="aws-cdk-dev@amazon.com",
    url="https://github.com/aws/aws-cdk",
    license="Apache-2.0",
    
    # Package configuration
    python_requires=">=3.8",
    py_modules=["app"],
    
    # Package dependencies
    install_requires=[
        "aws-cdk-lib==2.161.1",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.34.0",
        "botocore>=1.34.0",
        "typing-extensions>=4.8.0",
    ],
    
    # Development dependencies
    extras_require={
        "dev": [
            "mypy>=1.8.0",
            "pytest>=8.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
        ],
    },
    
    # Package classifiers
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Typing :: Typed",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "bedrock",
        "agentcore", 
        "q-business",
        "multi-agent",
        "knowledge-management",
        "ai",
        "machine-learning",
    ],
    
    # Package data and resources
    include_package_data=True,
    zip_safe=False,
    
    # Entry points for command-line tools
    entry_points={
        "console_scripts": [
            "multi-agent-km-cdk=app:main",
        ],
    },
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
    },
)