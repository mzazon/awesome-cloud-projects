#!/usr/bin/env python3
"""
Setup configuration for AWS Batch with Fargate CDK Python application
"""

import setuptools
from pathlib import Path

# Read the contents of README file
this_directory = Path(__file__).parent
long_description = (this_directory / "README.md").read_text() if (this_directory / "README.md").exists() else ""

setuptools.setup(
    name="batch-fargate-cdk",
    version="1.0.0",
    
    description="AWS CDK Python application for batch processing with Fargate",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS CDK Developer",
    author_email="developer@example.com",
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Utilities",
    ],
    
    install_requires=[
        "aws-cdk-lib>=2.100.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
    ],
    
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "types-setuptools>=68.0.0",
            "types-requests>=2.31.0",
        ],
        "optional": [
            "boto3>=1.28.0",
            "botocore>=1.31.0",
            "jsonschema>=4.0.0",
            "PyYAML>=6.0.0",
            "rich>=13.0.0",
        ],
    },
    
    packages=setuptools.find_packages(),
    
    package_data={
        "": ["*.json", "*.yaml", "*.yml"],
    },
    
    entry_points={
        "console_scripts": [
            "batch-fargate-cdk=app:main",
        ],
    },
    
    project_urls={
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Source": "https://github.com/aws/aws-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
    },
    
    keywords="aws cdk batch fargate serverless containers",
    
    zip_safe=False,
)