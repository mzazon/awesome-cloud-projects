#!/usr/bin/env python3
"""
Setup configuration for the SageMaker ML Endpoints CDK Python application.

This setup.py file configures the Python package for the AWS CDK application
that deploys machine learning models using Amazon SageMaker endpoints.
"""

import os
from typing import List

import setuptools


def read_requirements(filename: str) -> List[str]:
    """Read requirements from a file and return as a list."""
    requirements_path = os.path.join(os.path.dirname(__file__), filename)
    with open(requirements_path, "r", encoding="utf-8") as f:
        requirements = []
        for line in f:
            line = line.strip()
            # Skip comments and empty lines
            if line and not line.startswith("#"):
                # Remove inline comments
                if "#" in line:
                    line = line.split("#")[0].strip()
                requirements.append(line)
        return requirements


def read_long_description() -> str:
    """Read the long description from README.md if it exists."""
    readme_path = os.path.join(os.path.dirname(__file__), "README.md")
    if os.path.exists(readme_path):
        with open(readme_path, "r", encoding="utf-8") as f:
            return f.read()
    return "AWS CDK Python application for deploying ML models with Amazon SageMaker Endpoints"


# Package metadata
NAME = "sagemaker-ml-endpoints-cdk"
VERSION = "1.0.0"
DESCRIPTION = "AWS CDK Python application for deploying ML models with Amazon SageMaker Endpoints"
AUTHOR = "AWS Solutions Team"
AUTHOR_EMAIL = "aws-solutions@amazon.com"
URL = "https://github.com/aws-samples/sagemaker-ml-endpoints-cdk"
LICENSE = "MIT-0"

# Python version requirements
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
    "Programming Language :: Python :: 3.12",
    "Topic :: Software Development :: Libraries :: Python Modules",
    "Topic :: System :: Systems Administration",
    "Topic :: Utilities",
    "Typing :: Typed",
]

# Keywords for package discovery
KEYWORDS = [
    "aws",
    "cdk",
    "sagemaker",
    "machine-learning",
    "ml",
    "endpoints",
    "inference",
    "mlops",
    "auto-scaling",
    "cloudformation",
    "infrastructure-as-code",
]

setuptools.setup(
    name=NAME,
    version=VERSION,
    description=DESCRIPTION,
    long_description=read_long_description(),
    long_description_content_type="text/markdown",
    author=AUTHOR,
    author_email=AUTHOR_EMAIL,
    url=URL,
    license=LICENSE,
    python_requires=PYTHON_REQUIRES,
    classifiers=CLASSIFIERS,
    keywords=" ".join(KEYWORDS),
    
    # Package discovery
    packages=setuptools.find_packages(exclude=["tests", "tests.*"]),
    
    # Include additional files
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # Dependencies
    install_requires=read_requirements("requirements.txt"),
    
    # Optional dependencies for development
    extras_require={
        "dev": [
            "black>=23.12.0",
            "flake8>=6.1.0",
            "mypy>=1.8.0",
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "sphinx>=7.2.0",
            "sphinx-rtd-theme>=2.0.0",
        ],
        "test": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "moto>=4.2.0",  # AWS service mocking for tests
            "boto3-stubs[sagemaker,s3,ecr,iam]>=1.34.0",
        ],
        "docs": [
            "sphinx>=7.2.0",
            "sphinx-rtd-theme>=2.0.0",
            "sphinx-autodoc-typehints>=1.25.0",
        ],
    },
    
    # Entry points for command-line scripts
    entry_points={
        "console_scripts": [
            "deploy-sagemaker-endpoint=app:main",
        ],
    },
    
    # Project URLs
    project_urls={
        "Bug Reports": f"{URL}/issues",
        "Source": URL,
        "Documentation": f"{URL}/blob/main/README.md",
    },
    
    # Additional metadata
    zip_safe=False,
    
    # Minimum setuptools version
    setup_requires=["setuptools>=61.0"],
)