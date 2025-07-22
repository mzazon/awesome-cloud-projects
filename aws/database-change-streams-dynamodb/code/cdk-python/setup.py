"""
Setup configuration for Real-time Database Change Streams CDK Application

This setup.py file configures the Python package for the CDK application that
creates a real-time database change stream processing system using Amazon 
DynamoDB Streams and AWS Lambda.
"""

import setuptools
from pathlib import Path

# Read the contents of README file if it exists
readme_path = Path(__file__).parent / "README.md"
long_description = ""
if readme_path.exists():
    with open(readme_path, "r", encoding="utf-8") as fh:
        long_description = fh.read()
else:
    long_description = """
    Real-time Database Change Streams with DynamoDB Streams

    This CDK application creates a complete real-time database change stream 
    processing system using Amazon DynamoDB Streams and AWS Lambda. It demonstrates 
    event-driven architecture patterns for processing database changes in near real-time.

    Features:
    - DynamoDB table with streams enabled
    - Lambda function for processing stream records
    - S3 bucket for audit logging
    - SNS topic for notifications
    - SQS dead letter queue for error handling
    - CloudWatch alarms for monitoring
    - Appropriate IAM roles and policies
    """

# Read requirements from requirements.txt
requirements_path = Path(__file__).parent / "requirements.txt"
install_requires = []
if requirements_path.exists():
    with open(requirements_path, "r", encoding="utf-8") as fh:
        install_requires = [
            line.strip() 
            for line in fh 
            if line.strip() and not line.startswith("#")
        ]

setuptools.setup(
    name="dynamodb-stream-processing-cdk",
    version="1.0.0",
    
    author="AWS CDK Team",
    author_email="aws-cdk-team@amazon.com",
    
    description="Real-time Database Change Streams with DynamoDB Streams - CDK Application",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    url="https://github.com/aws/aws-cdk",
    
    packages=setuptools.find_packages(),
    
    install_requires=install_requires,
    
    python_requires=">=3.8",
    
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
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Distributed Computing",
        "Topic :: Database",
        "Typing :: Typed",
    ],
    
    keywords=[
        "aws",
        "cdk",
        "dynamodb",
        "streams",
        "lambda",
        "real-time",
        "event-driven",
        "serverless",
        "change-data-capture",
        "infrastructure-as-code"
    ],
    
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "Tracker": "https://github.com/aws/aws-cdk/issues",
    },
    
    # Entry points for command line scripts
    entry_points={
        "console_scripts": [
            "deploy-stream-processing=app:main",
        ],
    },
    
    # Include additional files in the package
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "pre-commit>=3.0.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
    },
    
    # Zip-safe flag
    zip_safe=False,
    
    # Package metadata
    platforms=["any"],
    license="Apache-2.0",
)