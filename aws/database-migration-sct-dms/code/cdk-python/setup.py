#!/usr/bin/env python3
"""
Setup configuration for Database Migration CDK Python Application.

This setup file defines the Python package configuration for the AWS CDK
application that creates infrastructure for database migration using AWS DMS
and Schema Conversion Tool.
"""

import os
from setuptools import setup, find_packages

# Read the contents of README file
current_directory = os.path.abspath(os.path.dirname(__file__))
with open(os.path.join(current_directory, "README.md"), encoding="utf-8") as f:
    long_description = f.read()

# Read requirements from requirements.txt
with open(os.path.join(current_directory, "requirements.txt"), encoding="utf-8") as f:
    requirements = [line.strip() for line in f if line.strip() and not line.startswith("#")]

setup(
    name="database-migration-cdk",
    version="1.0.0",
    description="AWS CDK Python application for database migration using DMS and Schema Conversion Tool",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS CDK Team",
    author_email="aws-cdk-team@amazon.com",
    url="https://github.com/aws/aws-cdk",
    license="Apache-2.0",
    
    # Package configuration
    packages=find_packages(exclude=["tests", "tests.*"]),
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=requirements,
    
    # Entry points for command line tools
    entry_points={
        "console_scripts": [
            "database-migration-cdk=app:main",
        ],
    },
    
    # Package classification
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Database",
        "Topic :: Database :: Database Engines/Servers",
        "Typing :: Typed",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "database",
        "migration",
        "dms",
        "schema-conversion",
        "postgresql",
        "oracle",
        "sql-server",
        "infrastructure",
        "infrastructure-as-code",
        "cloudformation",
    ],
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "Tracker": "https://github.com/aws/aws-cdk/issues",
        "DMS Documentation": "https://docs.aws.amazon.com/dms/",
        "Schema Conversion Tool": "https://docs.aws.amazon.com/SchemaConversionTool/",
    },
    
    # Include additional files
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # Additional metadata
    zip_safe=False,
    
    # Optional dependencies for development
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "mypy>=1.8.0",
            "black>=24.0.0",
            "flake8>=7.0.0",
            "pylint>=3.0.0",
            "pre-commit>=3.6.0",
        ],
        "docs": [
            "sphinx>=7.1.0",
            "sphinx-rtd-theme>=2.0.0",
            "myst-parser>=2.0.0",
        ],
    },
)