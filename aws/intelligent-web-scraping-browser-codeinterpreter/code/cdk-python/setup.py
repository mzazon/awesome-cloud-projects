"""
Setup configuration for Intelligent Web Scraping CDK Python Application

This setup.py file configures the Python package for the CDK application
that deploys intelligent web scraping infrastructure using AWS services.
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
                # Skip empty lines and comments
                if line and not line.startswith("#"):
                    # Remove inline comments
                    requirement = line.split("#")[0].strip()
                    if requirement:
                        requirements.append(requirement)
            return requirements
    except FileNotFoundError:
        # Fallback requirements if file not found
        return [
            "aws-cdk-lib>=2.120.0,<3.0.0",
            "constructs>=10.3.0,<11.0.0"
        ]


def read_long_description() -> str:
    """Read long description from README file"""
    try:
        with open("README.md", "r", encoding="utf-8") as f:
            return f.read()
    except FileNotFoundError:
        return """
        # Intelligent Web Scraping CDK Application
        
        AWS CDK Python application for deploying intelligent web scraping infrastructure
        using AWS Bedrock AgentCore Browser and Code Interpreter services.
        
        ## Features
        - Automated web navigation with AgentCore Browser
        - Intelligent data processing with Code Interpreter
        - Serverless orchestration with AWS Lambda
        - Scalable storage with Amazon S3
        - Comprehensive monitoring with CloudWatch
        - Scheduled execution with EventBridge
        """


setuptools.setup(
    name="intelligent-web-scraping-cdk",
    version="1.0.0",
    
    description="AWS CDK Python application for intelligent web scraping with AgentCore services",
    long_description=read_long_description(),
    long_description_content_type="text/markdown",
    
    author="AWS CDK Generator",
    author_email="aws-cdk@example.com",
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Code Generators",
        "Topic :: Utilities",
        "Typing :: Typed",
    ],
    
    install_requires=read_requirements(),
    
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.8.0",
            "boto3-stubs[essential]>=1.34.0",
        ]
    },
    
    packages=setuptools.find_packages(exclude=["tests*"]),
    
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"]
    },
    
    entry_points={
        "console_scripts": [
            "intelligent-scraping-cdk=app:main",
        ],
    },
    
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "Tracker": "https://github.com/aws/aws-cdk/issues",
    },
    
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "web-scraping",
        "ai",
        "agentcore",
        "automation",
        "serverless"
    ],
    
    zip_safe=False,
)