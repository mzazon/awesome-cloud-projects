#!/usr/bin/env python3
"""
Setup script for IoT Device Provisioning CDK Python Application

This setup script configures the Python package for the IoT Device Provisioning
and Certificate Management CDK application. It includes all necessary dependencies
and metadata for proper deployment and development.
"""

import os
from setuptools import setup, find_packages

# Read the README file for long description
def read_readme():
    """Read README.md file content"""
    readme_path = os.path.join(os.path.dirname(__file__), "README.md")
    if os.path.exists(readme_path):
        with open(readme_path, "r", encoding="utf-8") as f:
            return f.read()
    return "AWS CDK Python application for IoT Device Provisioning and Certificate Management"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements.txt file content"""
    requirements_path = os.path.join(os.path.dirname(__file__), "requirements.txt")
    requirements = []
    if os.path.exists(requirements_path):
        with open(requirements_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#"):
                    requirements.append(line)
    return requirements

# Package metadata
PACKAGE_NAME = "iot-device-provisioning-cdk"
VERSION = "1.0.0"
DESCRIPTION = "AWS CDK Python application for IoT Device Provisioning and Certificate Management"
AUTHOR = "AWS CDK Team"
AUTHOR_EMAIL = "aws-cdk-team@amazon.com"
LICENSE = "Apache-2.0"
URL = "https://github.com/aws/aws-cdk"

# Python version requirement
PYTHON_REQUIRES = ">=3.8"

# Classifiers for the package
CLASSIFIERS = [
    "Development Status :: 5 - Production/Stable",
    "Intended Audience :: Developers",
    "License :: OSI Approved :: Apache Software License",
    "Programming Language :: Python :: 3",
    "Programming Language :: Python :: 3.8",
    "Programming Language :: Python :: 3.9",
    "Programming Language :: Python :: 3.10",
    "Programming Language :: Python :: 3.11",
    "Programming Language :: Python :: 3.12",
    "Topic :: Software Development :: Libraries",
    "Topic :: System :: Systems Administration",
    "Topic :: Utilities",
    "Typing :: Typed",
]

# Keywords for package discovery
KEYWORDS = [
    "aws",
    "cdk",
    "cloud",
    "iot",
    "device-provisioning",
    "certificate-management",
    "infrastructure-as-code",
    "python",
    "boto3",
    "lambda",
    "dynamodb",
    "cloudformation",
]

# Long description content type
LONG_DESCRIPTION_CONTENT_TYPE = "text/markdown"

# Package configuration
setup(
    name=PACKAGE_NAME,
    version=VERSION,
    description=DESCRIPTION,
    long_description=read_readme(),
    long_description_content_type=LONG_DESCRIPTION_CONTENT_TYPE,
    author=AUTHOR,
    author_email=AUTHOR_EMAIL,
    license=LICENSE,
    url=URL,
    
    # Package discovery
    packages=find_packages(exclude=["tests", "tests.*"]),
    package_data={
        "": ["*.json", "*.yaml", "*.yml", "*.md"],
    },
    include_package_data=True,
    
    # Python version requirement
    python_requires=PYTHON_REQUIRES,
    
    # Dependencies
    install_requires=read_requirements(),
    
    # Optional dependencies for development
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.3.0",
            "flake8>=6.0.0",
            "mypy>=1.4.0",
            "pre-commit>=3.0.0",
        ],
        "test": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "moto>=4.2.0",
            "boto3-stubs[essential]>=1.34.0",
        ],
        "docs": [
            "sphinx>=7.0.0",
            "sphinx-rtd-theme>=1.3.0",
            "sphinx-autodoc-typehints>=1.23.0",
        ],
    },
    
    # Entry points for CLI commands
    entry_points={
        "console_scripts": [
            "iot-provisioning-cdk=app:main",
        ],
    },
    
    # Package metadata
    keywords=KEYWORDS,
    classifiers=CLASSIFIERS,
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "Tracker": "https://github.com/aws/aws-cdk/issues",
    },
    
    # Zip safety
    zip_safe=False,
    
    # Platform compatibility
    platforms=["any"],
    
    # Additional metadata
    maintainer=AUTHOR,
    maintainer_email=AUTHOR_EMAIL,
    download_url=f"https://github.com/aws/aws-cdk/archive/v{VERSION}.tar.gz",
    
    # Options for setup tools
    options={
        "build_scripts": {
            "executable": "/usr/bin/env python3",
        },
    },
)

# Print installation information
if __name__ == "__main__":
    print(f"Setting up {PACKAGE_NAME} v{VERSION}")
    print(f"Python requirement: {PYTHON_REQUIRES}")
    print(f"License: {LICENSE}")
    print(f"Author: {AUTHOR}")
    print("\nTo install this package, run:")
    print("  pip install -e .")
    print("\nTo install with development dependencies:")
    print("  pip install -e .[dev]")
    print("\nTo run tests:")
    print("  pytest")
    print("\nTo deploy the CDK application:")
    print("  cdk deploy")