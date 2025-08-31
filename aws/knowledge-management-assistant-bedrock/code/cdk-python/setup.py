"""
Setup configuration for Knowledge Management Assistant CDK Application

This setup.py file configures the Python package for the CDK application
that deploys a complete knowledge management solution using Amazon Bedrock.

Author: CDK Generator v1.3
Recipe: Knowledge Management Assistant with Bedrock Agents
"""

from setuptools import setup, find_packages
import os

# Read the README file for long description
readme_path = os.path.join(os.path.dirname(__file__), "README.md")
long_description = ""
if os.path.exists(readme_path):
    with open(readme_path, "r", encoding="utf-8") as fh:
        long_description = fh.read()

# Read requirements from requirements.txt
requirements_path = os.path.join(os.path.dirname(__file__), "requirements.txt")
requirements = []
if os.path.exists(requirements_path):
    with open(requirements_path, "r", encoding="utf-8") as fh:
        requirements = [
            line.strip() 
            for line in fh.readlines() 
            if line.strip() and not line.startswith("#")
        ]

setup(
    name="knowledge-management-assistant-bedrock",
    version="1.0.0",
    description="Knowledge Management Assistant with Amazon Bedrock Agents CDK Application",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    # Author and contact information
    author="AWS CDK Generator",
    author_email="support@aws.amazon.com",
    url="https://github.com/aws/aws-cdk",
    
    # Package discovery and classification
    packages=find_packages(exclude=["tests*"]),
    include_package_data=True,
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=requirements,
    
    # Optional dependencies for development
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "mypy>=1.0.0",
            "flake8>=6.0.0",
            "pylint>=2.15.0",
        ],
        "security": [
            "safety>=2.0.0",
            "bandit>=1.7.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
    },
    
    # Entry points for command-line tools
    entry_points={
        "console_scripts": [
            "deploy-knowledge-assistant=app:main",
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
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Utilities",
        "Framework :: AWS CDK",
        "Framework :: AWS CDK :: 2",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "bedrock",
        "knowledge-management",
        "ai",
        "machine-learning",
        "enterprise",
        "serverless",
        "api-gateway",
        "lambda",
        "s3",
        "opensearch",
        "rag",
        "conversational-ai",
        "infrastructure-as-code",
    ],
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "Tracker": "https://github.com/aws/aws-cdk/issues",
        "AWS Bedrock": "https://docs.aws.amazon.com/bedrock/",
        "AWS CDK": "https://aws.amazon.com/cdk/",
    },
    
    # License specification
    license="MIT",
    
    # Additional package data
    package_data={
        "": [
            "*.txt",
            "*.md",
            "*.json",
            "*.yaml",
            "*.yml",
        ],
    },
    
    # Exclude development and testing files from distribution
    exclude_package_data={
        "": [
            "tests/*",
            "*.pyc",
            "__pycache__/*",
            "*.pyo",
            "*.pyd",
            ".git/*",
            ".pytest_cache/*",
            ".mypy_cache/*",
            "cdk.out/*",
        ],
    },
    
    # Zip safety (important for some deployment scenarios)
    zip_safe=False,
)