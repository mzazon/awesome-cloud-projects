"""
Setup configuration for the Centralized SaaS Security Monitoring CDK application.

This setup.py file defines the Python package configuration for the AWS CDK
application that deploys centralized SaaS security monitoring infrastructure.
"""

import setuptools
from typing import List


def read_requirements() -> List[str]:
    """Read and parse requirements from requirements.txt file."""
    try:
        with open("requirements.txt", "r", encoding="utf-8") as requirements_file:
            requirements = []
            for line in requirements_file:
                line = line.strip()
                if line and not line.startswith("#") and not line.startswith("-"):
                    requirements.append(line)
            return requirements
    except FileNotFoundError:
        return [
            "aws-cdk-lib>=2.150.0",
            "constructs>=10.0.0",
            "boto3>=1.26.0",
        ]


def read_long_description() -> str:
    """Read the long description from README.md if available."""
    try:
        with open("README.md", "r", encoding="utf-8") as readme_file:
            return readme_file.read()
    except FileNotFoundError:
        return """
        # Centralized SaaS Security Monitoring CDK Application
        
        This AWS CDK application deploys a comprehensive security monitoring solution
        for SaaS applications using AWS AppFabric, EventBridge, Lambda, and SNS.
        
        ## Features
        - Centralized security log collection from multiple SaaS applications
        - Real-time threat detection and analysis
        - Intelligent security alerting with multi-channel notifications
        - Serverless architecture with automatic scaling
        - OCSF (Open Cybersecurity Schema Framework) compliant log processing
        
        ## Architecture
        The solution includes:
        - AWS AppFabric for SaaS application connectivity
        - S3 bucket for secure log storage
        - Custom EventBridge bus for event routing  
        - Lambda function for intelligent threat detection
        - SNS topic for multi-channel alerting
        - IAM roles with least-privilege access
        """


setuptools.setup(
    name="centralized-saas-security-monitoring",
    version="1.0.0",
    
    # Package metadata
    description="AWS CDK application for centralized SaaS security monitoring",
    long_description=read_long_description(),
    long_description_content_type="text/markdown",
    
    # Author information
    author="AWS Solutions Team",
    author_email="solutions@amazon.com",
    
    # Package configuration
    python_requires=">=3.8",
    packages=setuptools.find_packages(),
    install_requires=read_requirements(),
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "types-boto3>=1.0.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.2.0",
        ],
    },
    
    # Package classification
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: System Administrators",
        "Intended Audience :: Information Technology",
        "Topic :: Security",
        "Topic :: System :: Monitoring",
        "Topic :: System :: Systems Administration",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Operating System :: OS Independent",
        "Framework :: AWS CDK",
        "Framework :: AWS CDK :: 2",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "security",
        "monitoring",
        "saas",
        "appfabric",
        "eventbridge",
        "lambda",
        "sns",
        "threat-detection",
        "ocsf",
        "infrastructure",
        "cloud",
        "serverless",
    ],
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/appfabric/",
        "Source": "https://github.com/aws-samples/",
        "Bug Reports": "https://github.com/aws-samples/issues",
        "AWS AppFabric": "https://aws.amazon.com/appfabric/",
        "AWS EventBridge": "https://aws.amazon.com/eventbridge/",
    },
    
    # Include additional files in the package
    include_package_data=True,
    zip_safe=False,
    
    # Entry points for command line tools
    entry_points={
        "console_scripts": [
            "deploy-saas-security-monitoring=app:main",
        ],
    },
)