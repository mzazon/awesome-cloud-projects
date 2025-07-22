"""
Setup configuration for CQRS Event Sourcing CDK Python Application

This package provides Infrastructure as Code (IaC) for implementing
CQRS and Event Sourcing patterns using AWS EventBridge and DynamoDB.

Author: AWS Recipe Generator
Version: 1.0
License: MIT
"""

import setuptools
from pathlib import Path

# Read the README file for long description
readme_file = Path(__file__).parent / "README.md"
long_description = readme_file.read_text(encoding="utf-8") if readme_file.exists() else ""

# Define package metadata
setuptools.setup(
    name="cqrs-event-sourcing-cdk",
    version="1.0.0",
    
    # Package description
    description="AWS CDK Python application for CQRS and Event Sourcing with EventBridge and DynamoDB",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    # Author information
    author="AWS Recipe Generator",
    author_email="recipes@aws.example.com",
    
    # Project URLs
    url="https://github.com/aws-samples/cqrs-event-sourcing-recipe",
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws-samples/cqrs-event-sourcing-recipe",
        "Bug Tracker": "https://github.com/aws-samples/cqrs-event-sourcing-recipe/issues",
    },
    
    # Package configuration
    packages=setuptools.find_packages(exclude=["tests*"]),
    include_package_data=True,
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Package dependencies
    install_requires=[
        "aws-cdk-lib==2.130.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.28.0",
        "botocore>=1.31.0",
    ],
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "mypy>=1.5.0",
            "types-boto3>=1.0.2",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "isort>=5.12.0",
            "bandit>=1.7.5",
            "safety>=2.3.0",
        ],
        "docs": [
            "sphinx>=6.0.0",
            "sphinx-rtd-theme>=1.3.0",
        ],
    },
    
    # Package classifiers
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP :: HTTP Servers",
        "Typing :: Typed",
    ],
    
    # Keywords for PyPI
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "cqrs",
        "event-sourcing",
        "eventbridge",
        "dynamodb",
        "lambda",
        "serverless",
        "microservices",
        "architecture",
    ],
    
    # Entry points for command-line scripts
    entry_points={
        "console_scripts": [
            "cqrs-cdk=app:main",
        ],
    },
    
    # License
    license="MIT",
    
    # Zip safety
    zip_safe=False,
)