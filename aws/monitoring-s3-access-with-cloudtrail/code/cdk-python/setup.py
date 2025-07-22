"""
Setup configuration for S3 Access Logging and Security Monitoring CDK application.

This setup.py file configures the Python package for the CDK application,
including dependencies, metadata, and development tools.
"""

from setuptools import setup, find_packages

# Read the contents of the README file
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "S3 Access Logging and Security Monitoring CDK Application"

setup(
    name="s3-access-logging-security-monitoring",
    version="1.0.0",
    author="AWS CDK Team",
    author_email="aws-cdk-team@amazon.com",
    description="CDK application for implementing S3 access logging and security monitoring",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws/aws-cdk",
    packages=find_packages(),
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Typing :: Typed",
    ],
    python_requires=">=3.8",
    install_requires=[
        "aws-cdk-lib>=2.166.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.26.0",
        "botocore>=1.29.0",
    ],
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "isort>=5.0.0",
            "types-requests>=2.0.0",
            "boto3-stubs[s3,cloudtrail,logs,iam,events,sns,lambda,cloudwatch]>=1.0.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",
            "coverage>=6.0.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "s3-security-monitoring=app:main",
        ],
    },
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.yml", "*.yaml", "*.json"],
    },
    keywords=[
        "aws",
        "cdk",
        "s3",
        "security",
        "monitoring",
        "logging",
        "cloudtrail",
        "cloudwatch",
        "eventbridge",
        "sns",
        "lambda",
        "compliance",
        "audit",
    ],
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "Tracker": "https://github.com/aws/aws-cdk/issues",
    },
)