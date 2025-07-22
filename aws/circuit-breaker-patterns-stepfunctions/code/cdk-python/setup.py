#!/usr/bin/env python3
"""
Setup configuration for Circuit Breaker Patterns CDK Application

This setup.py file configures the Python package for the Circuit Breaker implementation
using AWS CDK. It includes all necessary dependencies and metadata for proper
installation and development.

Author: AWS CDK Generator
Version: 1.0
"""

import os
from typing import List
from setuptools import setup, find_packages

# Read the contents of README file for long description
def read_file(filename: str) -> str:
    """Read and return the contents of a file."""
    try:
        with open(os.path.join(os.path.dirname(__file__), filename), encoding='utf-8') as f:
            return f.read()
    except FileNotFoundError:
        return ""

# Read requirements from requirements.txt
def read_requirements(filename: str = "requirements.txt") -> List[str]:
    """Read and parse requirements from requirements.txt file."""
    try:
        with open(filename, 'r', encoding='utf-8') as f:
            requirements = []
            for line in f:
                line = line.strip()
                # Skip empty lines and comments
                if line and not line.startswith('#'):
                    # Remove inline comments
                    requirement = line.split('#')[0].strip()
                    if requirement:
                        requirements.append(requirement)
            return requirements
    except FileNotFoundError:
        return [
            "aws-cdk-lib>=2.100.0,<3.0.0",
            "constructs>=10.0.0,<11.0.0",
            "boto3>=1.26.0"
        ]

# Package metadata
PACKAGE_NAME = "circuit-breaker-patterns-cdk"
VERSION = "1.0.0"
DESCRIPTION = "AWS CDK implementation of Circuit Breaker patterns with Step Functions"
LONG_DESCRIPTION = read_file("README.md") or DESCRIPTION
AUTHOR = "AWS Solutions"
AUTHOR_EMAIL = "aws-solutions@amazon.com"
URL = "https://github.com/aws-samples/circuit-breaker-patterns-step-functions"
LICENSE = "MIT-0"

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
    "Topic :: Software Development :: Libraries :: Python Modules",
    "Topic :: System :: Distributed Computing",
    "Topic :: System :: Monitoring",
    "Topic :: System :: Systems Administration",
    "Typing :: Typed",
]

# Keywords for discoverability
KEYWORDS = [
    "aws",
    "cdk",
    "cloud",
    "circuit-breaker",
    "step-functions",
    "lambda",
    "dynamodb",
    "cloudwatch",
    "fault-tolerance",
    "resilience",
    "microservices",
    "distributed-systems",
    "infrastructure-as-code",
    "serverless"
]

# Development dependencies
DEV_REQUIREMENTS = [
    "pytest>=7.4.0",
    "pytest-cov>=4.1.0",
    "black>=23.0.0",
    "flake8>=6.0.0",
    "mypy>=1.5.0",
    "isort>=5.12.0",
    "bandit>=1.7.5",
    "safety>=2.3.0",
    "moto[all]>=4.2.0",
]

# Documentation dependencies
DOC_REQUIREMENTS = [
    "sphinx>=7.1.0",
    "sphinx-rtd-theme>=1.3.0",
    "sphinx-autodoc-typehints>=1.24.0",
]

# Testing dependencies
TEST_REQUIREMENTS = [
    "pytest>=7.4.0",
    "pytest-cov>=4.1.0",
    "pytest-mock>=3.11.0",
    "moto[all]>=4.2.0",
    "localstack>=2.2.0",
]

# Entry points for command-line tools
ENTRY_POINTS = {
    "console_scripts": [
        "circuit-breaker-deploy=app:main",
    ],
}

# Setup configuration
setup(
    name=PACKAGE_NAME,
    version=VERSION,
    description=DESCRIPTION,
    long_description=LONG_DESCRIPTION,
    long_description_content_type="text/markdown",
    author=AUTHOR,
    author_email=AUTHOR_EMAIL,
    url=URL,
    license=LICENSE,
    
    # Package discovery
    packages=find_packages(exclude=["tests*", "docs*"]),
    package_data={
        "": ["*.json", "*.yaml", "*.yml", "*.md", "*.txt"],
    },
    include_package_data=True,
    
    # Dependencies
    install_requires=read_requirements(),
    extras_require={
        "dev": DEV_REQUIREMENTS,
        "docs": DOC_REQUIREMENTS,
        "test": TEST_REQUIREMENTS,
        "all": DEV_REQUIREMENTS + DOC_REQUIREMENTS + TEST_REQUIREMENTS,
    },
    
    # Python version requirements
    python_requires=">=3.8",
    
    # Classification and discovery
    classifiers=CLASSIFIERS,
    keywords=" ".join(KEYWORDS),
    
    # Entry points
    entry_points=ENTRY_POINTS,
    
    # Project URLs
    project_urls={
        "Documentation": f"{URL}/blob/main/README.md",
        "Source Code": URL,
        "Bug Reports": f"{URL}/issues",
        "Feature Requests": f"{URL}/issues",
    },
    
    # Options
    zip_safe=False,
    
    # Additional metadata
    platforms=["any"],
    
    # Custom commands
    cmdclass={},
    
    # Build requirements
    setup_requires=[
        "setuptools>=45",
        "wheel>=0.37.0",
    ],
    
    # Options for different tools
    options={
        "bdist_wheel": {
            "universal": False,  # This package is not universal (Python 3 only)
        },
        "egg_info": {
            "tag_build": "",
            "tag_date": False,
        },
    },
)

# Additional setup for development mode
if __name__ == "__main__":
    import sys
    
    # Print helpful information
    print(f"Setting up {PACKAGE_NAME} v{VERSION}")
    print(f"Python version: {sys.version}")
    print(f"Platform: {sys.platform}")
    
    # Verify Python version
    if sys.version_info < (3, 8):
        print("Error: Python 3.8 or higher is required")
        sys.exit(1)
    
    print("Setup complete! You can now use:")
    print("  pip install -e .           # Install in development mode")
    print("  pip install -e .[dev]      # Install with development dependencies")
    print("  pip install -e .[test]     # Install with testing dependencies")
    print("  pip install -e .[all]      # Install with all dependencies")
    print()
    print("For CDK deployment:")
    print("  cdk bootstrap              # Bootstrap CDK (first time only)")
    print("  cdk synth                  # Synthesize CloudFormation template")
    print("  cdk deploy                 # Deploy the stack")
    print("  cdk destroy                # Clean up resources")