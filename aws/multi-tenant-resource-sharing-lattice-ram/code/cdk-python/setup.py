"""
Setup configuration for Multi-Tenant Resource Sharing CDK Python application.

This setup.py file configures the Python package for the CDK application that
implements multi-tenant resource sharing using Amazon VPC Lattice and AWS RAM.
"""

import os
from setuptools import setup, find_packages

# Read the README file for long description
def read_file(filename: str) -> str:
    """Read file contents."""
    try:
        with open(filename, 'r', encoding='utf-8') as f:
            return f.read()
    except FileNotFoundError:
        return ""

# Read requirements from requirements.txt
def read_requirements(filename: str = 'requirements.txt') -> list:
    """Read requirements from requirements file."""
    try:
        with open(filename, 'r', encoding='utf-8') as f:
            return [
                line.strip() 
                for line in f 
                if line.strip() and not line.startswith('#')
            ]
    except FileNotFoundError:
        return []

# Package metadata
PACKAGE_NAME = "multi-tenant-lattice-ram"
VERSION = "1.0.0"
DESCRIPTION = "Multi-Tenant Resource Sharing with VPC Lattice and AWS RAM"
LONG_DESCRIPTION = read_file("README.md") or DESCRIPTION

AUTHOR = "AWS Solutions Architect"
AUTHOR_EMAIL = "solutions@example.com"
URL = "https://github.com/aws-samples/multi-tenant-lattice-ram"

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
    "Programming Language :: Python :: 3.12",
    "Topic :: Software Development :: Libraries :: Python Modules",
    "Topic :: System :: Systems Administration",
    "Topic :: Internet :: WWW/HTTP",
    "Topic :: Software Development :: Libraries :: Application Frameworks",
    "Typing :: Typed",
]

# Keywords for package discovery
KEYWORDS = [
    "aws",
    "cdk",
    "cloud",
    "infrastructure",
    "vpc-lattice",
    "ram",
    "multi-tenant",
    "resource-sharing",
    "networking",
    "security",
    "database",
    "rds",
    "iam",
    "cloudtrail",
    "audit",
    "microservices",
    "service-mesh"
]

setup(
    name=PACKAGE_NAME,
    version=VERSION,
    description=DESCRIPTION,
    long_description=LONG_DESCRIPTION,
    long_description_content_type="text/markdown",
    author=AUTHOR,
    author_email=AUTHOR_EMAIL,
    url=URL,
    
    # Package configuration
    packages=find_packages(exclude=["tests*", "docs*"]),
    include_package_data=True,
    zip_safe=False,
    
    # Python version requirement
    python_requires=PYTHON_REQUIRES,
    
    # Dependencies
    install_requires=read_requirements(),
    
    # Optional dependencies for development
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "pre-commit>=3.0.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",
            "boto3-stubs[essential]>=1.26.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
            "sphinxcontrib-napoleon>=0.7",
        ],
    },
    
    # Entry points for CLI tools (if any)
    entry_points={
        "console_scripts": [
            "deploy-multi-tenant-lattice=app:main",
        ],
    },
    
    # Package metadata
    classifiers=CLASSIFIERS,
    keywords=" ".join(KEYWORDS),
    license="MIT",
    
    # Project URLs
    project_urls={
        "Documentation": f"{URL}/docs",
        "Source": URL,
        "Tracker": f"{URL}/issues",
        "Repository": URL,
        "Changelog": f"{URL}/CHANGELOG.md",
    },
    
    # Package data
    package_data={
        PACKAGE_NAME: [
            "*.yaml",
            "*.yml",
            "*.json",
            "*.txt",
            "*.md",
        ],
    },
)