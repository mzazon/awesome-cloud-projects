"""
Setup configuration for S3 Event Notifications and Automated Processing CDK application.

This setup.py file configures the Python package for the CDK application that
deploys an event-driven file processing architecture using S3, Lambda, SQS, and SNS.
"""

from setuptools import setup, find_packages
from typing import List


def read_requirements() -> List[str]:
    """Read requirements from requirements.txt file."""
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
        # Fallback requirements if file doesn't exist
        return [
            "aws-cdk-lib>=2.110.0,<3.0.0",
            "constructs>=10.0.0,<11.0.0",
            "boto3>=1.34.0",
        ]


setup(
    name="s3-event-processing-cdk",
    version="1.0.0",
    description="AWS CDK Python application for S3 Event Notifications and Automated Processing",
    long_description="""
    This CDK application creates a complete event-driven architecture for processing
    files uploaded to S3. It includes:
    
    - S3 bucket with intelligent event routing based on upload prefix
    - Lambda function for immediate file processing with type detection
    - SQS queue for reliable batch processing with dead letter queue
    - SNS topic for multi-subscriber notifications
    - Proper IAM roles and security policies
    - CloudWatch logging and monitoring
    
    The architecture demonstrates best practices for building scalable,
    event-driven file processing workflows on AWS.
    """,
    long_description_content_type="text/plain",
    author="AWS CDK Team",
    author_email="aws-cdk@amazon.com",
    url="https://github.com/aws/aws-cdk",
    license="Apache-2.0",
    packages=find_packages(exclude=["tests*"]),
    install_requires=read_requirements(),
    python_requires=">=3.8",
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP",
        "Typing :: Typed",
    ],
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "s3",
        "lambda",
        "sqs",
        "sns",
        "event-driven",
        "serverless",
        "file-processing",
        "automation",
    ],
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "Tracker": "https://github.com/aws/aws-cdk/issues",
    },
    include_package_data=True,
    zip_safe=False,
    entry_points={
        "console_scripts": [
            "s3-event-processing=app:main",
        ],
    },
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "pre-commit>=3.0.0",
        ],
        "testing": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",
            "boto3-stubs[essential]>=1.34.0",
        ],
    },
)