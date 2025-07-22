"""
Setup configuration for S3 Storage Analytics CDK Python Application

This setup.py file configures the Python package for the CDK application,
including dependencies, metadata, and development tools configuration.
"""

import setuptools
from pathlib import Path

# Read the long description from README if it exists
long_description = ""
readme_path = Path(__file__).parent / "README.md"
if readme_path.exists():
    with open(readme_path, "r", encoding="utf-8") as fh:
        long_description = fh.read()

setuptools.setup(
    name="s3-storage-analytics-cdk",
    version="1.0.0",
    
    description="AWS CDK Python application for S3 Inventory and Storage Analytics Reporting",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS CDK Generator",
    author_email="",
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Code Generators",
        "Topic :: Utilities",
        "Typing :: Typed",
    ],
    
    packages=setuptools.find_packages(),
    
    install_requires=[
        "aws-cdk-lib>=2.120.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.26.0",
        "botocore>=1.29.0",
    ],
    
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "types-boto3>=1.0.0",
            "boto3-stubs[essential]>=1.26.0",
        ]
    },
    
    entry_points={
        "console_scripts": [
            "s3-storage-analytics-cdk=app:main",
        ],
    },
    
    project_urls={
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Source": "https://github.com/aws/aws-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
    },
    
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "s3",
        "storage",
        "analytics",
        "inventory",
        "athena",
        "lambda",
        "cloudwatch"
    ],
    
    # Package metadata
    zip_safe=False,
    include_package_data=True,
    
    # Development tool configurations
    options={
        "build_scripts": {
            "executable": "/usr/bin/env python3",
        },
    },
)