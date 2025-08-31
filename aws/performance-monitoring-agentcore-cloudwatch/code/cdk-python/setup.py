"""
Setup configuration for Performance Monitoring AI Agents CDK Python application.

This setup.py file configures the Python package for the CDK application that creates
a comprehensive monitoring system for AWS Bedrock AgentCore with CloudWatch integration.
"""

import setuptools
from pathlib import Path

# Read the README file for the long description
readme_path = Path(__file__).parent / "README.md"
long_description = readme_path.read_text(encoding="utf-8") if readme_path.exists() else ""

# Read requirements from requirements.txt
requirements_path = Path(__file__).parent / "requirements.txt"
if requirements_path.exists():
    with open(requirements_path, "r", encoding="utf-8") as f:
        requirements = [
            line.strip()
            for line in f
            if line.strip() and not line.startswith("#")
        ]
else:
    requirements = [
        "aws-cdk-lib>=2.172.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.35.0",
    ]

setuptools.setup(
    name="performance-monitoring-agentcore-cloudwatch",
    version="1.0.0",
    description="CDK Python application for Performance Monitoring AI Agents with AgentCore and CloudWatch",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS CDK Team",
    author_email="aws-cdk@amazon.com",
    url="https://github.com/aws/aws-cdk",
    license="Apache-2.0",
    
    # Package configuration
    packages=setuptools.find_packages(where="."),
    package_dir={"": "."},
    
    # Python version requirements
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=requirements,
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=8.0.0",
            "pytest-cov>=6.0.0",
            "black>=24.0.0",
            "flake8>=7.0.0",
            "mypy>=1.8.0",
            "types-boto3>=1.35.0",
        ],
        "docs": [
            "sphinx>=8.0.0",
            "sphinx-rtd-theme>=3.0.0",
        ],
    },
    
    # Package metadata
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
        "Topic :: System :: Monitoring",
        "Topic :: Internet :: WWW/HTTP :: WSGI :: Application",
        "Typing :: Typed",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "monitoring",
        "observability",
        "bedrock",
        "agentcore",
        "cloudwatch",
        "lambda",
        "ai",
        "machine-learning",
        "performance",
        "automation",
    ],
    
    # Entry points for console scripts
    entry_points={
        "console_scripts": [
            "deploy-monitoring=app:main",
        ],
    },
    
    # Include additional files
    include_package_data=True,
    zip_safe=False,
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "CDK Workshop": "https://cdkworkshop.com/",
        "AWS Bedrock": "https://aws.amazon.com/bedrock/",
        "CloudWatch": "https://aws.amazon.com/cloudwatch/",
    },
)