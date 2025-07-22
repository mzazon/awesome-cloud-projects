"""
Setup configuration for Multi-AZ Database Deployments CDK Application

This setup.py file configures the Python package for the Multi-AZ Aurora PostgreSQL
CDK application. It includes all necessary dependencies and metadata for proper
installation and distribution.
"""

from setuptools import setup, find_packages

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setup(
    name="multi-az-database-cdk",
    version="1.0.0",
    description="AWS CDK application for Multi-AZ Aurora PostgreSQL deployments",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS CDK Recipe Generator",
    author_email="recipes@aws-samples.com",
    url="https://github.com/aws-samples/recipes",
    
    # Package configuration
    packages=find_packages(),
    include_package_data=True,
    zip_safe=False,
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Core dependencies
    install_requires=[
        "aws-cdk-lib>=2.150.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.34.0",
        "botocore>=1.34.0",
    ],
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "isort>=5.12.0",
            "types-setuptools>=68.0.0",
            "boto3-stubs[essential]>=1.34.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.2.0",
        ],
        "security": [
            "bandit>=1.7.0",
            "safety>=2.0.0",
            "cdk-nag>=2.27.0",
        ],
    },
    
    # Entry points for CLI commands
    entry_points={
        "console_scripts": [
            "deploy-multiaz-db=app:main",
        ],
    },
    
    # Package metadata
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
        "Topic :: Database",
        "Topic :: System :: Systems Administration",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Framework :: AWS CDK",
        "Framework :: AWS CDK :: 2",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "aurora",
        "postgresql",
        "multi-az",
        "high-availability",
        "database",
        "rds",
        "infrastructure",
        "cloud",
        "devops",
    ],
    
    # Project URLs
    project_urls={
        "Documentation": "https://github.com/aws-samples/recipes/tree/main/aws/multi-az-database-deployments-high-availability",
        "Source": "https://github.com/aws-samples/recipes",
        "Bug Reports": "https://github.com/aws-samples/recipes/issues",
        "AWS CDK": "https://aws.amazon.com/cdk/",
        "Amazon Aurora": "https://aws.amazon.com/aurora/",
    },
    
    # Package data to include
    package_data={
        "": [
            "*.md",
            "*.txt",
            "*.json",
            "*.yaml",
            "*.yml",
        ],
    },
    
    # Exclude test files from distribution
    exclude_package_data={
        "": ["tests/*", "test_*"],
    },
)