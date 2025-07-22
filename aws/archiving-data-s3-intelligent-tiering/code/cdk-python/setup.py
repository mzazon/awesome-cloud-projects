#!/usr/bin/env python3
"""
Setup configuration for Sustainable Data Archiving CDK Python application.

This setup.py file configures the Python package for the CDK application
that implements sustainable data archiving with S3 Intelligent-Tiering.
"""

from setuptools import setup, find_packages


# Read long description from README if it exists
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "Sustainable Data Archiving Solution with S3 Intelligent-Tiering using AWS CDK"

# Read requirements from requirements.txt
with open("requirements.txt", "r", encoding="utf-8") as fh:
    requirements = [
        line.strip() 
        for line in fh 
        if line.strip() and not line.startswith("#")
    ]

setup(
    name="sustainable-archive-cdk",
    version="1.0.0",
    description="AWS CDK Python application for sustainable data archiving with S3 Intelligent-Tiering",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS Solutions",
    author_email="aws-solutions@amazon.com",
    url="https://github.com/aws-samples/sustainable-data-archiving",
    
    # Package configuration
    packages=find_packages(),
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=requirements,
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "pytest-cov>=4.0.0",
            "pytest-mock>=3.10.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
        "test": [
            "moto>=4.0.0",
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "pytest-mock>=3.10.0",
        ]
    },
    
    # Entry point for the CDK application
    entry_points={
        "console_scripts": [
            "sustainable-archive=app:main",
        ],
    },
    
    # Package metadata
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Archiving",
        "Topic :: System :: Systems Administration",
        "Topic :: Utilities",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "s3",
        "intelligent-tiering",
        "sustainability",
        "carbon-footprint",
        "data-archiving",
        "cost-optimization",
        "storage-lifecycle",
        "cloud-native"
    ],
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/sustainable-data-archiving/issues",
        "Source": "https://github.com/aws-samples/sustainable-data-archiving",
        "Documentation": "https://aws-samples.github.io/sustainable-data-archiving/",
        "AWS CDK": "https://aws.amazon.com/cdk/",
        "S3 Intelligent-Tiering": "https://aws.amazon.com/s3/storage-classes/intelligent-tiering/",
    },
    
    # Include package data
    include_package_data=True,
    zip_safe=False,
    
    # License
    license="Apache License 2.0",
)