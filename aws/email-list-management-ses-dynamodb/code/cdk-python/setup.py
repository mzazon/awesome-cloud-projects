"""
Setup script for Email List Management System CDK application.

This setup.py file configures the Python package for the AWS CDK application
that deploys a serverless email list management system using SES, DynamoDB,
and Lambda functions.
"""

from setuptools import setup, find_packages
import os

# Read the contents of README file if it exists
current_directory = os.path.abspath(os.path.dirname(__file__))
readme_path = os.path.join(current_directory, "README.md")

long_description = ""
if os.path.exists(readme_path):
    with open(readme_path, encoding="utf-8") as fh:
        long_description = fh.read()
else:
    long_description = """
    Email List Management System CDK Application
    
    A production-ready AWS CDK Python application for deploying a serverless
    email list management system using Amazon SES, DynamoDB, and Lambda.
    
    Features:
    - Subscriber registration and management
    - Newsletter sending with personalization
    - Email validation and duplicate prevention
    - Administrative subscriber listing
    - Scalable serverless architecture
    - Comprehensive error handling and logging
    """

# Read requirements from requirements.txt
def parse_requirements(filename):
    """Load requirements from a pip requirements file."""
    lineiter = (line.strip() for line in open(filename))
    return [line for line in lineiter if line and not line.startswith("#")]

# Define package metadata
setup(
    name="email-list-management-cdk",
    version="1.0.0",
    description="AWS CDK Python application for serverless email list management",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS CDK Developer",
    author_email="developer@example.com",
    url="https://github.com/your-org/email-list-management-cdk",
    
    # Package discovery
    packages=find_packages(exclude=["tests", "tests.*"]),
    package_data={
        "": ["*.md", "*.txt", "*.yaml", "*.json"],
    },
    include_package_data=True,
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=[
        "aws-cdk-lib>=2.171.1,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.35.0",
        "botocore>=1.35.0",
    ],
    
    # Optional dependencies for development
    extras_require={
        "dev": [
            "pytest>=8.3.0",
            "pytest-cov>=6.0.0",
            "black>=24.10.0",
            "flake8>=7.1.0",
            "mypy>=1.13.0",
            "boto3-stubs[ses,dynamodb,lambda,iam]>=1.35.0",
            "bandit>=1.8.0",
            "safety>=3.2.0",
        ],
        "docs": [
            "sphinx>=8.1.0",
            "sphinx-rtd-theme>=3.0.0",
        ],
        "testing": [
            "moto[server]>=5.0.0",
            "responses>=0.25.0",
        ],
    },
    
    # Entry points for command-line interfaces
    entry_points={
        "console_scripts": [
            "email-list-cdk=app:main",
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
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
        "Topic :: Communications :: Email",
        "Topic :: System :: Systems Administration",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "email",
        "newsletter",
        "ses",
        "dynamodb",
        "lambda",
        "serverless",
        "infrastructure",
        "cloud",
        "subscribers",
        "mailing-list",
    ],
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/your-org/email-list-management-cdk",
        "Bug Reports": "https://github.com/your-org/email-list-management-cdk/issues",
        "AWS CDK": "https://aws.amazon.com/cdk/",
        "AWS SES": "https://aws.amazon.com/ses/",
        "AWS DynamoDB": "https://aws.amazon.com/dynamodb/",
        "AWS Lambda": "https://aws.amazon.com/lambda/",
    },
    
    # License
    license="Apache License 2.0",
    
    # Zip safety
    zip_safe=False,
)