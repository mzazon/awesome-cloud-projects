"""
Setup configuration for AWS CDK Python Business Task Scheduling application.

This setup.py file defines the package metadata and dependencies for the
automated business task scheduling CDK application.
"""

import setuptools
from typing import List


def read_requirements() -> List[str]:
    """Read requirements from requirements.txt file."""
    try:
        with open("requirements.txt", "r", encoding="utf-8") as f:
            return [
                line.strip()
                for line in f.readlines()
                if line.strip() and not line.startswith("#")
            ]
    except FileNotFoundError:
        return []


setuptools.setup(
    name="business-task-scheduling-cdk",
    version="1.0.0",
    description="AWS CDK Python application for automated business task scheduling",
    long_description="""
    This AWS CDK application creates infrastructure for automated business workflows using:
    - EventBridge Scheduler for flexible scheduling
    - Lambda functions for task processing  
    - S3 bucket for report storage
    - SNS topic for notifications
    - IAM roles with least privilege access
    
    The application demonstrates enterprise-grade serverless automation patterns
    with proper security, monitoring, and cost optimization features.
    """,
    long_description_content_type="text/plain",
    
    # Author information
    author="AWS CDK Team",
    author_email="aws-cdk@amazon.com",
    
    # Package information
    python_requires=">=3.8",
    packages=setuptools.find_packages(),
    
    # Dependencies
    install_requires=read_requirements(),
    
    # Classifiers for PyPI
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
        "Topic :: System :: Systems Administration",
        "Topic :: Office/Business :: Scheduling",
    ],
    
    # Keywords for discovery
    keywords="aws cdk eventbridge scheduler lambda automation business workflows serverless",
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
    },
    
    # Entry points (if needed for CLI tools)
    entry_points={
        "console_scripts": [
            # "business-scheduler=app:main",  # Uncomment if CLI needed
        ],
    },
    
    # Additional package data
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    include_package_data=True,
    
    # Zip safe flag
    zip_safe=False,
)