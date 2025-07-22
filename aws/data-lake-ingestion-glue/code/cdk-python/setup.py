"""
Setup configuration for AWS CDK Data Lake Ingestion Pipeline

This setup.py file configures the Python package for the AWS CDK application
that creates a comprehensive data lake solution using AWS Glue for automated
schema discovery, ETL processing, and data catalog management.

The package implements a medallion architecture with Bronze, Silver, and Gold
data layers, following AWS best practices for data lake design and governance.
"""

import setuptools
from pathlib import Path

# Read the README file for long description
readme_path = Path(__file__).parent / "README.md"
try:
    with open(readme_path, "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = """
    AWS CDK Data Lake Ingestion Pipeline
    
    A comprehensive Infrastructure as Code solution for building data lakes
    with AWS Glue, implementing medallion architecture patterns and automated
    data catalog management.
    """

# Read requirements from requirements.txt
requirements_path = Path(__file__).parent / "requirements.txt"
requirements = []
try:
    with open(requirements_path, "r", encoding="utf-8") as fh:
        requirements = [
            line.strip() 
            for line in fh.readlines() 
            if line.strip() and not line.startswith("#")
        ]
except FileNotFoundError:
    requirements = [
        "aws-cdk-lib>=2.158.0",
        "constructs>=10.0.0",
        "aws-cdk.aws-glue-alpha>=2.158.0a0"
    ]

setuptools.setup(
    name="data-lake-glue-cdk",
    version="1.0.0",
    
    # Package metadata
    author="AWS Solutions Architect",
    author_email="solutions@example.com",
    description="AWS CDK application for Data Lake Ingestion Pipelines with Glue",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/data-lake-glue-cdk",
    
    # Package configuration
    packages=setuptools.find_packages(),
    include_package_data=True,
    
    # Dependencies
    install_requires=requirements,
    
    # Python version requirements
    python_requires=">=3.8",
    
    # Package classification
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
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Utilities",
        "Typing :: Typed",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "glue",
        "data-lake",
        "etl",
        "analytics",
        "medallion-architecture",
        "data-catalog",
        "infrastructure-as-code",
        "serverless",
        "big-data",
        "data-engineering"
    ],
    
    # Entry points for console scripts
    entry_points={
        "console_scripts": [
            "deploy-data-lake=app:main",
        ],
    },
    
    # Additional package data
    package_data={
        "": [
            "*.md",
            "*.txt",
            "*.yaml",
            "*.yml",
            "*.json",
            "cdk.json",
            "cdk.context.json"
        ]
    },
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.4.3",
            "pytest-cov>=4.1.0",
            "mypy>=1.8.0",
            "black>=23.12.0",
            "flake8>=6.1.0",
            "isort>=5.13.2",
            "bandit>=1.7.5",
            "safety>=2.3.5"
        ],
        "docs": [
            "sphinx>=7.2.6",
            "sphinx-rtd-theme>=2.0.0"
        ],
        "test": [
            "moto>=4.2.14",
            "boto3>=1.34.0"
        ]
    },
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/data-lake-glue-cdk/issues",
        "Source": "https://github.com/aws-samples/data-lake-glue-cdk",
        "Documentation": "https://aws-samples.github.io/data-lake-glue-cdk/",
        "AWS Glue Documentation": "https://docs.aws.amazon.com/glue/latest/dg/what-is-glue.html",
        "AWS CDK Documentation": "https://docs.aws.amazon.com/cdk/v2/guide/home.html"
    },
    
    # License
    license="Apache-2.0",
    
    # Zip safety
    zip_safe=False,
)