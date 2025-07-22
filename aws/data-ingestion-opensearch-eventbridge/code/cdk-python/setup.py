"""
Setup configuration for the Automated Data Ingestion Pipeline CDK application.

This package provides Infrastructure as Code (IaC) for deploying an automated
data ingestion pipeline using Amazon OpenSearch Ingestion and EventBridge Scheduler.
"""

from setuptools import setup, find_packages
import os

# Read the contents of README file
this_directory = os.path.abspath(os.path.dirname(__file__))
readme_path = os.path.join(this_directory, "README.md")

long_description = ""
if os.path.exists(readme_path):
    with open(readme_path, encoding="utf-8") as f:
        long_description = f.read()

# Package metadata
setup(
    name="automated-data-ingestion-pipeline-cdk",
    version="1.0.0",
    description="CDK Python application for automated data ingestion with OpenSearch and EventBridge",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS Solutions Architect",
    author_email="solutions@example.com",
    url="https://github.com/aws-samples/data-ingestion-pipeline-cdk",
    license="MIT",
    
    # Package discovery
    packages=find_packages(exclude=["tests", "tests.*"]),
    include_package_data=True,
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Core dependencies
    install_requires=[
        "aws-cdk-lib==2.170.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.35.0",
        "botocore>=1.35.0",
        "pyyaml>=6.0.0",
        "jsonschema>=4.21.0",
    ],
    
    # Development dependencies
    extras_require={
        "dev": [
            "mypy>=1.10.0",
            "black>=24.0.0",
            "flake8>=7.0.0",
            "pylint>=3.0.0",
            "pytest>=8.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.2.0",
            "sphinx>=7.0.0",
            "sphinx-rtd-theme>=2.0.0",
            "bandit>=1.7.0",
            "safety>=3.0.0",
        ],
        "cli": [
            "awscli>=1.34.0",
        ]
    },
    
    # Package classification
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP :: Indexing/Search",
        "Topic :: Scientific/Engineering :: Information Analysis",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "opensearch",
        "data-ingestion",
        "eventbridge",
        "scheduler",
        "analytics",
        "pipeline",
        "automation",
        "serverless",
        "infrastructure-as-code",
        "data-processing",
        "search",
        "logging",
        "monitoring"
    ],
    
    # Entry points for CLI commands
    entry_points={
        "console_scripts": [
            "data-ingestion-deploy=app:main",
        ],
    },
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/data-ingestion-pipeline-cdk/issues",
        "Source": "https://github.com/aws-samples/data-ingestion-pipeline-cdk",
        "Documentation": "https://docs.aws.amazon.com/opensearch-service/",
        "AWS CDK": "https://docs.aws.amazon.com/cdk/",
        "OpenSearch": "https://opensearch.org/",
    },
    
    # Package data
    package_data={
        "": [
            "*.md",
            "*.txt",
            "*.yaml",
            "*.yml",
            "*.json",
        ],
    },
    
    # Zip safe configuration
    zip_safe=False,
)