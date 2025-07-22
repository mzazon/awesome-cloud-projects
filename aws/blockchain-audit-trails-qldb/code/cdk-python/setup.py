"""
Setup configuration for Blockchain Audit Trails Compliance CDK Python application.

This file defines the package metadata and dependencies for the CDK application
that creates a comprehensive blockchain-based audit trail system using Amazon QLDB
and supporting AWS services for regulatory compliance.
"""

from setuptools import setup, find_packages

# Read the contents of README file
from pathlib import Path
this_directory = Path(__file__).parent
long_description = (this_directory / "README.md").read_text() if (this_directory / "README.md").exists() else ""

setup(
    name="blockchain-audit-trails-compliance-cdk",
    version="1.0.0",
    description="CDK Python application for Blockchain Audit Trails Compliance with Amazon QLDB and CloudTrail",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS Recipe Generator",
    author_email="aws-recipes@example.com",
    url="https://github.com/aws-samples/blockchain-audit-trails-compliance",
    
    # Package configuration
    packages=find_packages(exclude=["tests*"]),
    include_package_data=True,
    zip_safe=False,
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=[
        "aws-cdk-lib==2.116.0",
        "constructs>=10.0.0,<11.0.0",
        "typing-extensions>=4.0.0",
        "boto3>=1.34.0",
        "botocore>=1.34.0",
        "python-dateutil>=2.8.0",
        "cryptography>=41.0.0",
    ],
    
    # Development dependencies
    extras_require={
        "dev": [
            "mypy>=1.0.0",
            "black>=22.0.0",
            "flake8>=4.0.0",
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "bandit>=1.7.0",
            "safety>=2.0.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",  # For mocking AWS services in tests
        ],
    },
    
    # Package classifiers
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "Intended Audience :: Financial and Insurance Industry",
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
        "Topic :: Office/Business :: Financial",
        "Topic :: Security",
        "Topic :: Database",
        "Typing :: Typed",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "blockchain",
        "audit",
        "compliance",
        "qldb",
        "cloudtrail",
        "immutable",
        "ledger",
        "regulatory",
        "sox",
        "pci-dss",
        "hipaa",
        "fintech",
        "infrastructure-as-code",
        "cloud-formation",
        "governance",
        "security",
        "monitoring",
        "eventbridge",
        "lambda",
        "s3",
        "athena",
        "kinesis",
        "firehose",
    ],
    
    # Entry points for command-line tools (if any)
    entry_points={
        "console_scripts": [
            # Add any command-line scripts here if needed
            # "audit-trail-deploy=app:main",
        ],
    },
    
    # Project URLs
    project_urls={
        "Documentation": "https://github.com/aws-samples/blockchain-audit-trails-compliance/blob/main/README.md",
        "Source": "https://github.com/aws-samples/blockchain-audit-trails-compliance",
        "Tracker": "https://github.com/aws-samples/blockchain-audit-trails-compliance/issues",
        "AWS CDK": "https://aws.amazon.com/cdk/",
        "Amazon QLDB": "https://aws.amazon.com/qldb/",
    },
    
    # Package data and manifest
    package_data={
        "": ["*.txt", "*.md", "*.json", "*.yaml", "*.yml"],
    },
    
    # Metadata for package managers
    metadata={
        "License-File": "LICENSE",
        "Requires-Dist": [
            "aws-cdk-lib (==2.116.0)",
            "constructs (>=10.0.0,<11.0.0)",
        ],
    },
)