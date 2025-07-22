"""
Setup configuration for Cross-Organization Data Sharing CDK Application

This setup.py file configures the Python package for the CDK application
that deploys a comprehensive cross-organization data sharing platform
using Amazon Managed Blockchain and supporting AWS services.
"""

from setuptools import setup, find_packages
import os

# Read the README file for long description
def read_readme():
    """Read the README.md file for the long description."""
    try:
        with open("README.md", "r", encoding="utf-8") as fh:
            return fh.read()
    except FileNotFoundError:
        return "Cross-Organization Data Sharing with Amazon Managed Blockchain CDK Application"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file."""
    try:
        with open("requirements.txt", "r", encoding="utf-8") as fh:
            requirements = []
            for line in fh:
                line = line.strip()
                # Skip comments and empty lines
                if line and not line.startswith("#"):
                    # Remove inline comments
                    if "#" in line:
                        line = line.split("#")[0].strip()
                    requirements.append(line)
            return requirements
    except FileNotFoundError:
        # Fallback requirements if file doesn't exist
        return [
            "aws-cdk-lib>=2.137.0",
            "constructs>=10.0.0,<11.0.0",
            "boto3>=1.34.0",
            "botocore>=1.34.0"
        ]

# Package metadata
PACKAGE_NAME = "cross-org-data-sharing-cdk"
VERSION = "1.0.0"
DESCRIPTION = "CDK application for cross-organization data sharing with Amazon Managed Blockchain"
AUTHOR = "AWS Solutions Architecture Team"
AUTHOR_EMAIL = "aws-solutions@amazon.com"
URL = "https://github.com/aws-samples/cross-org-blockchain-data-sharing"
LICENSE = "MIT-0"

# Python version requirement
PYTHON_REQUIRES = ">=3.8"

# Classifiers for PyPI
CLASSIFIERS = [
    "Development Status :: 4 - Beta",
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
    "Topic :: Internet :: WWW/HTTP",
    "Topic :: System :: Systems Administration",
    "Topic :: Security :: Cryptography",
    "Framework :: AWS CDK",
    "Framework :: AWS CDK :: 2"
]

# Keywords for discoverability
KEYWORDS = [
    "aws",
    "cdk",
    "blockchain",
    "hyperledger-fabric",
    "cross-organization",
    "data-sharing",
    "managed-blockchain",
    "lambda",
    "eventbridge",
    "compliance",
    "audit-trail",
    "infrastructure-as-code",
    "cloud-formation"
]

# Development status and additional metadata
PROJECT_URLS = {
    "Bug Reports": f"{URL}/issues",
    "Source": URL,
    "Documentation": f"{URL}/blob/main/README.md",
    "AWS CDK": "https://aws.amazon.com/cdk/",
    "Amazon Managed Blockchain": "https://aws.amazon.com/managed-blockchain/"
}

# Entry points for console scripts (if needed)
ENTRY_POINTS = {
    "console_scripts": [
        "cross-org-deploy=app:main",
    ],
}

# Additional data files to include
PACKAGE_DATA = {
    PACKAGE_NAME: [
        "*.json",
        "*.yaml",
        "*.yml",
        "cdk.json",
        "cdk.context.json"
    ]
}

# Setup configuration
setup(
    name=PACKAGE_NAME,
    version=VERSION,
    description=DESCRIPTION,
    long_description=read_readme(),
    long_description_content_type="text/markdown",
    author=AUTHOR,
    author_email=AUTHOR_EMAIL,
    url=URL,
    project_urls=PROJECT_URLS,
    license=LICENSE,
    
    # Package discovery and requirements
    packages=find_packages(exclude=["tests", "tests.*"]),
    package_data=PACKAGE_DATA,
    include_package_data=True,
    python_requires=PYTHON_REQUIRES,
    install_requires=read_requirements(),
    
    # Development dependencies (optional)
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.7.0",
            "flake8>=6.0.0",
            "mypy>=1.5.0",
            "bandit>=1.7.5",
            "safety>=2.3.5"
        ],
        "docs": [
            "sphinx>=7.1.0",
            "sphinx-rtd-theme>=1.3.0"
        ],
        "testing": [
            "moto>=4.2.0",
            "localstack-client>=2.0.0",
            "pytest-mock>=3.11.0"
        ]
    },
    
    # Package classification
    classifiers=CLASSIFIERS,
    keywords=", ".join(KEYWORDS),
    
    # Entry points
    entry_points=ENTRY_POINTS,
    
    # Additional metadata
    platforms=["any"],
    zip_safe=False,
    
    # Options for specific build tools
    options={
        "bdist_wheel": {
            "universal": False
        }
    }
)