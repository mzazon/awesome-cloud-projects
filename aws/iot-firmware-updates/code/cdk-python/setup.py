#!/usr/bin/env python3
"""
Setup configuration for IoT Firmware Updates CDK Application

This setup.py file configures the Python package for the CDK application
that manages IoT firmware updates with device management jobs.
"""

from setuptools import setup, find_packages

# Read the README file for long description
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "CDK Python application for IoT firmware updates with device management jobs"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file."""
    try:
        with open("requirements.txt", "r", encoding="utf-8") as f:
            return [
                line.strip()
                for line in f
                if line.strip() and not line.startswith("#")
            ]
    except FileNotFoundError:
        return [
            "aws-cdk-lib>=2.167.0,<3.0.0",
            "constructs>=10.0.0,<11.0.0",
            "boto3>=1.34.0",
        ]

setup(
    name="iot-firmware-updates-cdk",
    version="1.0.0",
    description="CDK Python application for IoT firmware updates with device management jobs",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS CDK Recipe Generator",
    author_email="recipes@aws.com",
    url="https://github.com/aws-samples/aws-cdk-examples",
    
    # Package configuration
    packages=find_packages(exclude=["tests", "tests.*"]),
    include_package_data=True,
    zip_safe=False,
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=read_requirements(),
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "boto3-stubs[essential]>=1.34.0",
        ]
    },
    
    # Entry points for command-line scripts
    entry_points={
        "console_scripts": [
            "iot-firmware-updates=app:main",
        ],
    },
    
    # Classifiers for PyPI
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
    ],
    
    # Keywords for PyPI search
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "iot",
        "firmware",
        "device-management",
        "over-the-air",
        "ota",
        "jobs",
        "lambda",
        "s3",
        "signer",
    ],
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws-samples/aws-cdk-examples",
        "Bug Reports": "https://github.com/aws-samples/aws-cdk-examples/issues",
    },
    
    # Additional metadata
    license="Apache-2.0",
    platforms=["any"],
)