"""
Setup configuration for Automated Report Generation CDK Python Application

This setup.py file configures the Python package for the automated report
generation solution using AWS CDK. The package creates infrastructure for
serverless business reporting with EventBridge Scheduler, Lambda, S3, and SES.

Key Features:
- Automated report generation and distribution
- Serverless architecture with AWS managed services
- Security best practices and least-privilege access
- Cost optimization through lifecycle policies
- Comprehensive monitoring and error handling

Author: AWS CDK Team
License: MIT
Version: 1.0.0
"""

import setuptools
from pathlib import Path

# Read the README file for the long description
this_directory = Path(__file__).parent
long_description = (this_directory / "README.md").read_text() if (this_directory / "README.md").exists() else ""

setuptools.setup(
    name="automated-report-generation-cdk",
    version="1.0.0",
    
    description="AWS CDK Python application for automated business report generation",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS CDK Team",
    author_email="aws-cdk-team@amazon.com",
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: Internet :: WWW/HTTP",
        "Topic :: System :: Systems Administration",
        "Typing :: Typed",
    ],
    
    install_requires=[
        "aws-cdk-lib==2.115.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.34.0",
        "typing-extensions>=4.8.0",
    ],
    
    extras_require={
        "dev": [
            "boto3-stubs[essential]==1.34.0",
            "mypy==1.7.1",
            "pytest==7.4.3",
            "pytest-cov==4.1.0",
            "black==23.11.0",
            "flake8==6.1.0",
            "isort==5.12.0",
            "moto[all]==4.2.14",
        ],
        "docs": [
            "sphinx>=4.0.0",
            "sphinx-rtd-theme>=1.0.0",
            "sphinx-autodoc-typehints>=1.12.0",
        ]
    },
    
    packages=setuptools.find_packages(exclude=["tests", "tests.*"]),
    
    package_data={
        "": ["*.md", "*.txt", "*.yaml", "*.yml", "*.json"],
    },
    
    include_package_data=True,
    
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "CDK Workshop": "https://cdkworkshop.com/",
        "AWS CDK Examples": "https://github.com/aws-samples/aws-cdk-examples",
    },
    
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "automation",
        "reporting",
        "serverless",
        "lambda",
        "s3",
        "eventbridge",
        "ses",
        "business-intelligence",
        "data-processing",
        "scheduled-tasks",
    ],
    
    # Entry points for command-line scripts (if needed)
    entry_points={
        "console_scripts": [
            # Add any CLI commands here if needed in the future
            # "report-generator=automated_report_stack:main",
        ],
    },
    
    # Zip safety - CDK works well with zip files
    zip_safe=True,
    
    # Development status and stability
    setup_requires=[
        "setuptools>=45.0.0",
        "wheel>=0.36.0",
    ],
    
    # Minimum Python version check
    python_requires=">=3.8",
)