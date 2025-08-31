"""
Setup configuration for Enterprise Oracle Database Connectivity CDK Application.

This package provides Infrastructure as Code (IaC) using AWS CDK Python for
implementing Oracle Database@AWS integration with VPC Lattice, S3, and Redshift.

Recipe: enterprise-oracle-connectivity-lattice-s3
Author: AWS CDK Generator
Version: 1.0
"""

import os
from typing import List

from setuptools import setup, find_packages


def read_requirements(filename: str) -> List[str]:
    """Read requirements from requirements.txt file."""
    requirements_path = os.path.join(os.path.dirname(__file__), filename)
    with open(requirements_path, 'r', encoding='utf-8') as f:
        requirements = []
        for line in f:
            line = line.strip()
            # Skip comments and empty lines
            if line and not line.startswith('#'):
                # Remove inline comments
                requirement = line.split('#')[0].strip()
                if requirement:
                    requirements.append(requirement)
        return requirements


def read_long_description() -> str:
    """Read the long description from README.md if it exists."""
    readme_path = os.path.join(os.path.dirname(__file__), "README.md")
    if os.path.exists(readme_path):
        with open(readme_path, 'r', encoding='utf-8') as f:
            return f.read()
    return """
    Enterprise Oracle Database Connectivity with VPC Lattice and S3
    
    This CDK Python application deploys infrastructure for integrating Oracle Database@AWS
    with AWS services using VPC Lattice resource gateways for secure cross-network connectivity,
    automated S3 backup, and Zero-ETL analytics with Redshift.
    
    Features:
    - S3 bucket with enterprise-grade backup lifecycle policies
    - Amazon Redshift cluster for analytics with encryption
    - IAM roles with least-privilege access
    - CloudWatch monitoring and dashboards
    - KMS encryption for sensitive data
    - Secrets Manager for credential management
    """


# Package metadata
PACKAGE_NAME = "enterprise-oracle-connectivity"
VERSION = "1.0.0"
DESCRIPTION = "Enterprise Oracle Database Connectivity with VPC Lattice and S3"
AUTHOR = "AWS CDK Generator"
AUTHOR_EMAIL = "aws-cdk@example.com"
URL = "https://github.com/aws-samples/aws-cdk-examples"

# Python version requirement
PYTHON_REQUIRES = ">=3.8"

# Package classifiers
CLASSIFIERS = [
    "Development Status :: 5 - Production/Stable",
    "Intended Audience :: Developers",
    "Intended Audience :: System Administrators",
    "License :: OSI Approved :: MIT License",
    "Programming Language :: Python :: 3",
    "Programming Language :: Python :: 3.8",
    "Programming Language :: Python :: 3.9",
    "Programming Language :: Python :: 3.10",
    "Programming Language :: Python :: 3.11",
    "Programming Language :: Python :: 3.12",
    "Topic :: Software Development :: Libraries :: Python Modules",
    "Topic :: System :: Systems Administration",
    "Topic :: Utilities",
    "Operating System :: OS Independent",
]

# Keywords for package discovery
KEYWORDS = [
    "aws",
    "cdk",
    "oracle",
    "database",
    "vpc-lattice",
    "s3",
    "redshift",
    "analytics",
    "enterprise",
    "infrastructure",
    "cloud",
    "iac"
]

setup(
    name=PACKAGE_NAME,
    version=VERSION,
    description=DESCRIPTION,
    long_description=read_long_description(),
    long_description_content_type="text/markdown",
    author=AUTHOR,
    author_email=AUTHOR_EMAIL,
    url=URL,
    packages=find_packages(exclude=["tests", "tests.*"]),
    include_package_data=True,
    python_requires=PYTHON_REQUIRES,
    install_requires=read_requirements("requirements.txt"),
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.7.0",
            "flake8>=6.0.0",
            "mypy>=1.5.0",
            "isort>=5.12.0",
            "bandit>=1.7.5",
            "safety>=3.0.0",
        ],
        "docs": [
            "sphinx>=7.1.0",
            "sphinx-rtd-theme>=1.3.0",
        ],
        "testing": [
            "moto[all]>=4.2.0",
            "boto3-stubs[essential]>=1.34.0",
        ]
    },
    classifiers=CLASSIFIERS,
    keywords=" ".join(KEYWORDS),
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws-samples/aws-cdk-examples",
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "AWS CDK": "https://aws.amazon.com/cdk/",
        "Oracle Database@AWS": "https://aws.amazon.com/rds/oracle/",
        "VPC Lattice": "https://aws.amazon.com/vpc/lattice/",
    },
    entry_points={
        "console_scripts": [
            f"{PACKAGE_NAME}=app:app",
        ],
    },
    zip_safe=False,
    
    # Additional metadata
    license="MIT",
    platforms=["any"],
    
    # Package data and resources
    package_data={
        PACKAGE_NAME: [
            "*.md",
            "*.txt",
            "*.json",
            "*.yaml",
            "*.yml"
        ],
    },
    
    # Manifest template for including additional files
    data_files=[
        (".", ["requirements.txt"]),
    ],
)