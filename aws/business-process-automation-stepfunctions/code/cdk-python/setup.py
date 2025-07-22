"""
Setup configuration for Business Process Automation CDK Application

This setup.py file configures the Python package for the business process
automation solution using AWS CDK. The package includes all necessary
dependencies and metadata for deploying Step Functions workflows with
Lambda, SQS, SNS, and API Gateway integration.
"""

from setuptools import setup, find_packages
import os


def read_requirements():
    """Read requirements from requirements.txt file."""
    requirements_path = os.path.join(os.path.dirname(__file__), 'requirements.txt')
    try:
        with open(requirements_path, 'r', encoding='utf-8') as f:
            return [
                line.strip() 
                for line in f 
                if line.strip() and not line.startswith('#')
            ]
    except FileNotFoundError:
        return []


def read_long_description():
    """Read long description from README.md if available."""
    readme_path = os.path.join(os.path.dirname(__file__), 'README.md')
    try:
        with open(readme_path, 'r', encoding='utf-8') as f:
            return f.read()
    except FileNotFoundError:
        return "Business Process Automation with AWS Step Functions, Lambda, SQS, SNS, and API Gateway"


setup(
    name="business-process-automation-cdk",
    version="1.0.0",
    description="AWS CDK application for business process automation using Step Functions",
    long_description=read_long_description(),
    long_description_content_type="text/markdown",
    
    # Author and contact information
    author="AWS CDK Team",
    author_email="aws-cdk@amazon.com",
    
    # Project URLs
    url="https://github.com/aws/aws-cdk",
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "Tracker": "https://github.com/aws/aws-cdk/issues",
    },
    
    # Package discovery and classification
    packages=find_packages(exclude=["tests*"]),
    include_package_data=True,
    zip_safe=False,
    
    # Python version requirements
    python_requires=">=3.8",
    
    # Package dependencies
    install_requires=read_requirements(),
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "pip-tools>=6.0.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",
            "boto3-stubs[stepfunctions,lambda,sqs,sns,apigateway]>=1.26.0",
        ],
    },
    
    # Package metadata for PyPI
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
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP",
        "Typing :: Typed",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "step-functions",
        "lambda",
        "sqs",
        "sns",
        "api-gateway",
        "workflow",
        "automation",
        "business-process",
        "orchestration",
        "serverless",
    ],
    
    # Entry points for command-line tools
    entry_points={
        "console_scripts": [
            "deploy-business-process=app:BusinessProcessAutomationApp",
        ],
    },
    
    # Package data and manifest
    package_data={
        "": [
            "*.md",
            "*.txt",
            "*.yaml",
            "*.yml",
            "*.json",
        ],
    },
    
    # License information
    license="Apache License 2.0",
    license_files=["LICENSE"],
)