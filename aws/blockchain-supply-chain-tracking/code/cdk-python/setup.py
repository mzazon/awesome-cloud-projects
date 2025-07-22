"""
Setup configuration for the blockchain-based supply chain tracking CDK application.

This setup.py file defines the package configuration, dependencies, and metadata
for the CDK Python application that deploys a comprehensive supply chain tracking
solution using Amazon Managed Blockchain and related AWS services.
"""

from setuptools import setup, find_packages

# Read the README file for long description
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "Blockchain-based supply chain tracking system using AWS CDK"

# Define package metadata
PACKAGE_NAME = "supply-chain-blockchain-cdk"
VERSION = "1.0.0"
DESCRIPTION = "CDK application for blockchain-based supply chain tracking systems"
AUTHOR = "AWS CDK Developer"
AUTHOR_EMAIL = "developer@example.com"
URL = "https://github.com/aws-samples/supply-chain-blockchain-cdk"

# Define package requirements
REQUIREMENTS = [
    "aws-cdk-lib==2.114.1",
    "constructs>=10.0.0,<11.0.0",
    "typing-extensions>=4.0.0",
]

# Define development requirements
DEV_REQUIREMENTS = [
    "pytest>=7.0.0",
    "pytest-cov>=4.0.0",
    "black>=22.0.0",
    "flake8>=5.0.0",
    "mypy>=1.0.0",
    "sphinx>=5.0.0",
    "sphinx-rtd-theme>=1.0.0",
]

# Python version requirement
PYTHON_REQUIRES = ">=3.8"

# Package classifiers
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
    "Topic :: Software Development :: Libraries :: Python Modules",
    "Topic :: System :: Systems Administration",
    "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
    "Typing :: Typed",
]

# Define entry points for CLI commands
ENTRY_POINTS = {
    "console_scripts": [
        "supply-chain-cdk=app:main",
    ],
}

setup(
    name=PACKAGE_NAME,
    version=VERSION,
    description=DESCRIPTION,
    long_description=long_description,
    long_description_content_type="text/markdown",
    author=AUTHOR,
    author_email=AUTHOR_EMAIL,
    url=URL,
    packages=find_packages(exclude=["tests", "tests.*"]),
    include_package_data=True,
    install_requires=REQUIREMENTS,
    extras_require={
        "dev": DEV_REQUIREMENTS,
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
    },
    python_requires=PYTHON_REQUIRES,
    classifiers=CLASSIFIERS,
    entry_points=ENTRY_POINTS,
    keywords="aws cdk blockchain supply-chain iot lambda dynamodb eventbridge",
    project_urls={
        "Bug Reports": f"{URL}/issues",
        "Source": URL,
        "Documentation": f"{URL}/docs",
    },
    zip_safe=False,
)