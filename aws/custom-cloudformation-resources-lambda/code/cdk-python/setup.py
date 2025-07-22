"""
Setup configuration for Custom CloudFormation Resources CDK Python Application

This setup.py file configures the Python package for the CDK application that demonstrates
Lambda-backed custom CloudFormation resources. It includes all necessary dependencies,
metadata, and configuration for development and deployment.

Author: AWS CDK Team
Version: 1.0
License: MIT
"""

import setuptools
import os

# Read the README file for long description
def read_long_description():
    """Read the README.md file for the long description."""
    try:
        with open("README.md", "r", encoding="utf-8") as fh:
            return fh.read()
    except FileNotFoundError:
        return "CDK Python application for demonstrating Lambda-backed custom CloudFormation resources"

# Read version from environment or use default
def get_version():
    """Get version from environment variable or use default."""
    return os.environ.get("PACKAGE_VERSION", "1.0.0")

# Define package requirements
install_requires = [
    "aws-cdk-lib==2.114.1",
    "constructs>=10.0.0,<11.0.0",
    "boto3>=1.26.0",
    "botocore>=1.29.0",
]

# Development dependencies
dev_requires = [
    "pytest>=7.0.0",
    "pytest-cov>=4.0.0",
    "black>=22.0.0",
    "flake8>=5.0.0",
    "mypy>=1.0.0",
    "boto3-stubs[essential]>=1.26.0",
    "types-requests>=2.28.0",
    "bandit>=1.7.0",
    "safety>=2.0.0",
    "autopep8>=1.7.0",
    "isort>=5.10.0",
]

# Documentation dependencies
docs_requires = [
    "sphinx>=5.0.0",
    "sphinx-rtd-theme>=1.0.0",
    "myst-parser>=0.18.0",
]

# Testing dependencies
test_requires = [
    "pytest>=7.0.0",
    "pytest-cov>=4.0.0",
    "moto>=4.0.0",  # For mocking AWS services
    "pytest-mock>=3.8.0",
    "coverage>=6.0.0",
]

setuptools.setup(
    name="custom-cloudformation-resources-cdk",
    version=get_version(),
    author="AWS CDK Team",
    author_email="aws-cdk-team@amazon.com",
    description="CDK Python application for Lambda-backed custom CloudFormation resources",
    long_description=read_long_description(),
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/custom-cloudformation-resources-cdk",
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws-samples/custom-cloudformation-resources-cdk",
        "Bug Reports": "https://github.com/aws-samples/custom-cloudformation-resources-cdk/issues",
    },
    packages=setuptools.find_packages(exclude=["tests", "tests.*"]),
    include_package_data=True,
    classifiers=[
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
        "Topic :: Utilities",
        "Typing :: Typed",
    ],
    keywords=[
        "aws",
        "cdk",
        "cloudformation",
        "lambda",
        "custom-resources",
        "infrastructure-as-code",
        "serverless",
        "devops",
    ],
    python_requires=">=3.8",
    install_requires=install_requires,
    extras_require={
        "dev": dev_requires,
        "docs": docs_requires,
        "test": test_requires,
        "all": dev_requires + docs_requires + test_requires,
    },
    entry_points={
        "console_scripts": [
            "custom-resource-cdk=app:main",
        ],
    },
    package_data={
        "": ["*.md", "*.txt", "*.yaml", "*.yml"],
    },
    zip_safe=False,
    # Additional metadata for PyPI
    license="MIT",
    platforms=["any"],
    # Security and maintenance
    options={
        "bdist_wheel": {
            "universal": False,  # This package is Python 3 only
        },
    },
    # CDK-specific metadata
    cdk_version="2.114.1",
    # Quality assurance settings
    setup_requires=[
        "setuptools>=65.0.0",
        "wheel>=0.37.0",
    ],
    # Test configuration
    test_suite="tests",
    tests_require=test_requires,
    # Documentation configuration
    command_options={
        "build_sphinx": {
            "project": ("setup.py", "Custom CloudFormation Resources CDK"),
            "version": ("setup.py", get_version()),
            "release": ("setup.py", get_version()),
            "source_dir": ("setup.py", "docs"),
        }
    },
)