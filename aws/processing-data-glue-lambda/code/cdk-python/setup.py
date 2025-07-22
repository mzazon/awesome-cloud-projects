"""
Python package setup configuration for Serverless ETL Pipeline CDK application.

This setup.py file configures the Python package for the AWS CDK application
that deploys a serverless ETL pipeline using AWS Glue and Lambda.
"""

import setuptools
from typing import List


def read_requirements(filename: str) -> List[str]:
    """Read requirements from requirements.txt file."""
    with open(filename, 'r', encoding='utf-8') as f:
        return [
            line.strip() 
            for line in f 
            if line.strip() and not line.startswith('#')
        ]


def read_long_description() -> str:
    """Read long description from README file."""
    try:
        with open("README.md", "r", encoding="utf-8") as fh:
            return fh.read()
    except FileNotFoundError:
        return """
        # Serverless ETL Pipeline CDK Application
        
        This AWS CDK Python application deploys a complete serverless ETL pipeline
        using AWS Glue for data transformations and AWS Lambda for orchestration.
        
        ## Features
        - S3 bucket for data storage with lifecycle policies
        - AWS Glue database and crawler for data cataloging
        - AWS Glue ETL job for data transformation
        - Lambda function for pipeline orchestration
        - Glue workflow with scheduled triggers
        - S3 event notifications for real-time processing
        - CloudWatch monitoring and logging
        
        ## Deployment
        ```bash
        pip install -r requirements.txt
        cdk deploy
        ```
        """


setuptools.setup(
    name="serverless-etl-pipeline-cdk",
    version="1.0.0",
    author="AWS CDK Team",
    author_email="aws-cdk@amazon.com",
    description="AWS CDK application for serverless ETL pipeline with Glue and Lambda",
    long_description=read_long_description(),
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/serverless-etl-pipeline-cdk",
    packages=setuptools.find_packages(),
    install_requires=read_requirements("requirements.txt"),
    python_requires=">=3.8",
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Utilities",
        "Typing :: Typed",
    ],
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "serverless",
        "etl",
        "glue",
        "lambda",
        "data-processing",
        "analytics"
    ],
    project_urls={
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Source": "https://github.com/aws/aws-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
    },
    entry_points={
        "console_scripts": [
            "serverless-etl-cdk=app:main",
        ],
    },
    package_data={
        "": [
            "*.py",
            "*.txt",
            "*.md",
            "*.json",
        ],
    },
    include_package_data=True,
    zip_safe=False,
)