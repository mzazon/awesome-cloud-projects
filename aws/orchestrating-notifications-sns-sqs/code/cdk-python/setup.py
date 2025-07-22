"""
Setup configuration for the Serverless Notification Systems CDK Python application.

This setup.py file configures the Python package for the AWS CDK application
that deploys a comprehensive serverless notification system using SNS, SQS,
and Lambda services.
"""

from setuptools import setup, find_packages

# Read the README file for long description
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "A comprehensive serverless notification system built with AWS CDK Python."

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file."""
    try:
        with open("requirements.txt", "r", encoding="utf-8") as fh:
            return [line.strip() for line in fh if line.strip() and not line.startswith("#")]
    except FileNotFoundError:
        return [
            "aws-cdk-lib==2.162.1",
            "constructs>=10.0.0,<11.0.0",
            "boto3>=1.26.0",
        ]

setup(
    name="serverless-notification-systems-cdk",
    version="1.0.0",
    description="AWS CDK Python application for deploying serverless notification systems",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS CDK Team",
    author_email="aws-cdk-team@amazon.com",
    url="https://github.com/aws/aws-cdk",
    license="Apache-2.0",
    
    # Package configuration
    packages=find_packages(exclude=["tests", "tests.*"]),
    python_requires=">=3.9",
    install_requires=read_requirements(),
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=0.991",
            "boto3-stubs[sns,sqs,lambda]>=1.26.0",
            "autopep8>=1.6.0",
            "isort>=5.10.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.2.0",
        ],
        "security": [
            "bandit>=1.7.0",
            "safety>=2.0.0",
        ],
    },
    
    # Entry points for command line tools
    entry_points={
        "console_scripts": [
            "deploy-notification-system=app:main",
        ],
    },
    
    # Package metadata
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
        "Topic :: Communications :: Email",
        "Topic :: Communications :: Telephony",
        "Framework :: AWS CDK",
        "Framework :: AWS CDK :: 2",
    ],
    
    # Keywords for PyPI
    keywords=[
        "aws",
        "cdk",
        "serverless",
        "notifications",
        "sns",
        "sqs",
        "lambda",
        "email",
        "sms",
        "webhook",
        "cloud",
        "infrastructure",
        "messaging",
        "event-driven",
        "microservices",
    ],
    
    # Include additional files
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Source": "https://github.com/aws/aws-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "AWS CDK Guide": "https://docs.aws.amazon.com/cdk/v2/guide/",
        "Examples": "https://github.com/aws-samples/aws-cdk-examples",
    },
    
    # Minimum requirements check
    zip_safe=False,
)