"""
Setup configuration for Serverless Real-Time Analytics CDK Application

This setup.py file configures the Python package for the CDK application
that deploys a serverless real-time analytics pipeline using Kinesis,
Lambda, and DynamoDB.
"""

from setuptools import setup, find_packages
import os

# Read the README file for the long description
def read_readme():
    """Read the README.md file if it exists."""
    readme_path = os.path.join(os.path.dirname(__file__), "README.md")
    if os.path.exists(readme_path):
        with open(readme_path, "r", encoding="utf-8") as f:
            return f.read()
    return "Serverless Real-Time Analytics CDK Application"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file."""
    requirements_path = os.path.join(os.path.dirname(__file__), "requirements.txt")
    requirements = []
    
    if os.path.exists(requirements_path):
        with open(requirements_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                # Skip comments and empty lines
                if line and not line.startswith("#"):
                    requirements.append(line)
    
    return requirements

setup(
    name="serverless-realtime-analytics-cdk",
    version="1.0.0",
    description="AWS CDK application for deploying a serverless real-time analytics pipeline",
    long_description=read_readme(),
    long_description_content_type="text/markdown",
    author="AWS CDK Python Generator",
    author_email="developer@example.com",
    url="https://github.com/aws/aws-cdk",
    
    # Package discovery
    packages=find_packages(exclude=["tests*"]),
    
    # Python version requirement
    python_requires=">=3.7",
    
    # Dependencies
    install_requires=read_requirements(),
    
    # Package classification
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.7",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Utilities",
    ],
    
    # Keywords for package discovery
    keywords="aws cdk kinesis lambda dynamodb analytics serverless real-time",
    
    # Entry points for console scripts
    entry_points={
        "console_scripts": [
            "deploy-analytics=app:main",
        ],
    },
    
    # Additional package data
    package_data={
        "": ["*.md", "*.txt", "*.yaml", "*.yml", "*.json"],
    },
    
    # Include additional files specified in MANIFEST.in
    include_package_data=True,
    
    # Zip safety
    zip_safe=False,
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "boto3-stubs[essential]>=1.28.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",
        ],
    },
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "Tracker": "https://github.com/aws/aws-cdk/issues",
    },
)