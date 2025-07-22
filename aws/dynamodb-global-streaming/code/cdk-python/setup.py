"""
Setup script for Advanced DynamoDB Streaming with Global Tables CDK Application.

This package contains the CDK Python application for deploying a sophisticated
DynamoDB Global Tables architecture with comprehensive streaming capabilities.
"""

import setuptools
from setuptools import setup, find_packages

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

# Read requirements from requirements.txt
with open("requirements.txt", "r", encoding="utf-8") as f:
    requirements = [line.strip() for line in f if line.strip() and not line.startswith("#")]

setup(
    name="advanced-dynamodb-streaming-global-tables",
    version="1.0.0",
    
    description="CDK Python application for Advanced DynamoDB Streaming with Global Tables",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS Solutions Architecture Team",
    author_email="solutions-architecture@amazon.com",
    
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
    
    packages=find_packages(exclude=["tests*"]),
    
    install_requires=requirements,
    
    extras_require={
        "dev": [
            "mypy>=1.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "isort>=5.12.0",
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.2.0",
        ],
        "docs": [
            "sphinx>=6.0.0",
            "sphinx-rtd-theme>=1.3.0",
        ],
    },
    
    entry_points={
        "console_scripts": [
            "advanced-dynamodb-streaming=app:app",
        ],
    },
    
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/advanced-dynamodb-streaming/issues",
        "Source": "https://github.com/aws-samples/advanced-dynamodb-streaming",
        "Documentation": "https://docs.aws.amazon.com/dynamodb/latest/developerguide/GlobalTables.html",
    },
    
    keywords=[
        "aws",
        "cdk",
        "dynamodb",
        "global-tables",
        "streaming",
        "kinesis",
        "lambda",
        "eventbridge",
        "cloudwatch",
        "infrastructure-as-code",
    ],
    
    package_data={
        "": ["*.md", "*.txt", "*.json"],
    },
    
    include_package_data=True,
    
    zip_safe=False,
)