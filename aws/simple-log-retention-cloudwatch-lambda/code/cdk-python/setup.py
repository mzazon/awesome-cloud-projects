"""
Setup configuration for Simple Log Retention Management CDK Application

This setup.py file configures the Python package for the CDK application,
including dependencies, metadata, and development tools configuration.
"""

import setuptools
from pathlib import Path

# Read the README file for long description
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "AWS CDK Application for Simple Log Retention Management with CloudWatch and Lambda"

# Read requirements from requirements.txt
def read_requirements() -> list:
    """Read requirements from requirements.txt file"""
    try:
        with open("requirements.txt", "r", encoding="utf-8") as fh:
            requirements = []
            for line in fh:
                line = line.strip()
                if line and not line.startswith("#"):
                    # Remove version constraints for setup.py
                    package = line.split(">=")[0].split("==")[0].split("[")[0]
                    requirements.append(package)
            return requirements
    except FileNotFoundError:
        return [
            "aws-cdk-lib",
            "constructs",
            "boto3",
            "botocore"
        ]

setuptools.setup(
    name="simple-log-retention-management",
    version="1.0.0",
    
    author="AWS CDK Recipe",
    author_email="cdk-recipes@example.com",
    
    description="AWS CDK application for automated CloudWatch Logs retention management",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    url="https://github.com/aws-samples/cdk-recipes",
    
    project_urls={
        "Bug Tracker": "https://github.com/aws-samples/cdk-recipes/issues",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source Code": "https://github.com/aws-samples/cdk-recipes",
    },
    
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
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
        "Topic :: System :: Logging",
    ],
    
    packages=setuptools.find_packages(),
    
    python_requires=">=3.8",
    
    install_requires=read_requirements(),
    
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "mypy>=1.0.0",
            "flake8>=5.0.0",
            "boto3-stubs[logs,events,iam,lambda]>=1.35.0"
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",  # For mocking AWS services in tests
        ]
    },
    
    keywords=[
        "aws",
        "cdk", 
        "cloudwatch",
        "lambda",
        "logs",
        "retention",
        "cost-optimization",
        "governance",
        "automation"
    ],
    
    entry_points={
        "console_scripts": [
            "cdk-log-retention=app:main",
        ],
    },
    
    # Package metadata
    zip_safe=False,
    include_package_data=True,
    
    # Additional metadata
    platforms=["any"],
    
    # License information
    license="MIT",
    license_files=["LICENSE"],
)