#!/usr/bin/env python3
"""
Setup configuration for Natural Language Processing Pipelines with Amazon Comprehend CDK application.

This setup.py file configures the Python package for the CDK application,
including dependencies, metadata, and entry points for deployment.

Author: AWS CDK Team
Version: 1.0
License: MIT
"""

import os
from typing import List

from setuptools import setup, find_packages


def read_requirements(filename: str) -> List[str]:
    """
    Read requirements from requirements.txt file.
    
    Args:
        filename: Path to requirements file
        
    Returns:
        List of requirement strings
    """
    requirements_path = os.path.join(os.path.dirname(__file__), filename)
    with open(requirements_path, 'r', encoding='utf-8') as f:
        requirements = []
        for line in f:
            line = line.strip()
            # Skip comments and empty lines
            if line and not line.startswith('#'):
                requirements.append(line)
        return requirements


def read_long_description() -> str:
    """
    Read the long description from README file if it exists.
    
    Returns:
        Long description string or empty string if README not found
    """
    readme_path = os.path.join(os.path.dirname(__file__), 'README.md')
    if os.path.exists(readme_path):
        with open(readme_path, 'r', encoding='utf-8') as f:
            return f.read()
    return """
    Natural Language Processing Pipelines with Amazon Comprehend
    
    This CDK application deploys a complete NLP pipeline using Amazon Comprehend
    for real-time and batch text analysis, including sentiment analysis,
    entity recognition, and key phrase extraction.
    """


# Package metadata
PACKAGE_NAME = "comprehend-nlp-pipeline"
VERSION = "1.0.0"
DESCRIPTION = "CDK application for NLP pipelines using Amazon Comprehend"
AUTHOR = "AWS CDK Team"
AUTHOR_EMAIL = "aws-cdk-team@example.com"
URL = "https://github.com/aws-samples/comprehend-nlp-pipeline"
LICENSE = "MIT"

# Python version requirement
PYTHON_REQUIRES = ">=3.8"

# Package classifiers for PyPI
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
    "Topic :: Scientific/Engineering :: Artificial Intelligence",
    "Topic :: Text Processing :: Linguistic",
]

# Keywords for package discovery
KEYWORDS = [
    "aws",
    "cdk",
    "comprehend",
    "nlp",
    "natural-language-processing",
    "sentiment-analysis",
    "entity-recognition",
    "text-analysis",
    "machine-learning",
    "serverless",
    "lambda",
    "s3",
]

# Entry points for command-line scripts
ENTRY_POINTS = {
    "console_scripts": [
        "deploy-nlp-pipeline=app:main",
    ],
}

# Additional package data to include
PACKAGE_DATA = {
    "": [
        "*.md",
        "*.txt",
        "*.json",
        "*.yaml",
        "*.yml",
    ],
}

# Setup configuration
setup(
    name=PACKAGE_NAME,
    version=VERSION,
    description=DESCRIPTION,
    long_description=read_long_description(),
    long_description_content_type="text/markdown",
    author=AUTHOR,
    author_email=AUTHOR_EMAIL,
    url=URL,
    license=LICENSE,
    classifiers=CLASSIFIERS,
    keywords=" ".join(KEYWORDS),
    python_requires=PYTHON_REQUIRES,
    
    # Package discovery
    packages=find_packages(exclude=["tests", "tests.*", "docs", "docs.*"]),
    package_data=PACKAGE_DATA,
    include_package_data=True,
    
    # Dependencies
    install_requires=read_requirements("requirements.txt"),
    
    # Optional dependencies for development
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.7.0",
            "flake8>=6.0.0",
            "isort>=5.12.0",
            "mypy>=1.5.0",
        ],
        "docs": [
            "sphinx>=7.1.0",
            "sphinx-rtd-theme>=1.3.0",
        ],
        "test": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "moto>=4.2.0",  # AWS service mocking for tests
        ],
    },
    
    # Entry points
    entry_points=ENTRY_POINTS,
    
    # Zip safety
    zip_safe=False,
    
    # Project URLs for additional information
    project_urls={
        "Documentation": f"{URL}/blob/main/README.md",
        "Source": URL,
        "Tracker": f"{URL}/issues",
        "Funding": "https://github.com/sponsors/aws",
    },
    
    # Additional metadata
    platforms=["any"],
    
    # CDK-specific metadata
    options={
        "build_scripts": {
            "executable": "/usr/bin/env python3",
        },
    },
)