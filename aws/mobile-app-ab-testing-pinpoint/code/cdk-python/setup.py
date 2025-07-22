#!/usr/bin/env python3
"""
Setup configuration for Amazon Pinpoint A/B Testing CDK Python Application

This setup file configures the Python package for the CDK application that
deploys infrastructure for implementing A/B testing with Amazon Pinpoint.
"""

import os
import re
from typing import List, Dict, Any
from setuptools import setup, find_packages


def get_version() -> str:
    """Get version from package metadata"""
    version_file = os.path.join(os.path.dirname(__file__), "app.py")
    if os.path.exists(version_file):
        with open(version_file, "r") as f:
            content = f.read()
            # Look for version in comments or docstrings
            version_match = re.search(r'version["\']?\s*[:=]\s*["\']([^"\']+)["\']', content)
            if version_match:
                return version_match.group(1)
    return "1.0.0"


def get_requirements() -> List[str]:
    """Read requirements from requirements.txt"""
    requirements_file = os.path.join(os.path.dirname(__file__), "requirements.txt")
    if os.path.exists(requirements_file):
        with open(requirements_file, "r") as f:
            # Filter out comments and empty lines
            return [
                line.strip()
                for line in f.readlines()
                if line.strip() and not line.startswith("#")
            ]
    return [
        "aws-cdk-lib>=2.118.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.34.0",
    ]


def get_long_description() -> str:
    """Get long description from README if available"""
    readme_file = os.path.join(os.path.dirname(__file__), "README.md")
    if os.path.exists(readme_file):
        with open(readme_file, "r", encoding="utf-8") as f:
            return f.read()
    return """
    Amazon Pinpoint A/B Testing CDK Python Application
    
    This CDK application deploys the complete infrastructure for implementing 
    A/B testing for mobile apps using Amazon Pinpoint, including:
    
    - Pinpoint project with A/B testing capabilities
    - S3 bucket for analytics export
    - Kinesis stream for real-time event processing
    - Lambda functions for automated analysis
    - CloudWatch dashboard for monitoring
    - IAM roles and policies with least privilege access
    
    The application follows AWS best practices for security, scalability,
    and cost optimization.
    """


# Package metadata
PACKAGE_NAME = "pinpoint-ab-testing-cdk"
PACKAGE_VERSION = get_version()

# Package configuration
package_config: Dict[str, Any] = {
    "name": PACKAGE_NAME,
    "version": PACKAGE_VERSION,
    "description": "AWS CDK Python application for Amazon Pinpoint A/B Testing infrastructure",
    "long_description": get_long_description(),
    "long_description_content_type": "text/markdown",
    "author": "AWS Solutions Team",
    "author_email": "aws-solutions@amazon.com",
    "url": "https://github.com/aws-samples/pinpoint-ab-testing-cdk",
    "license": "Apache-2.0",
    "packages": find_packages(exclude=["tests", "tests.*"]),
    "py_modules": ["app"],
    "install_requires": get_requirements(),
    "extras_require": {
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "types-boto3>=1.0.0",
        ],
        "docs": [
            "sphinx>=6.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
        "analysis": [
            "numpy>=1.24.0",
            "scipy>=1.10.0",
            "pandas>=2.0.0",
        ],
    },
    "python_requires": ">=3.8",
    "classifiers": [
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
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
        "Topic :: Scientific/Engineering :: Information Analysis",
        "Operating System :: OS Independent",
    ],
    "keywords": [
        "aws",
        "cdk",
        "pinpoint",
        "a/b testing",
        "mobile apps",
        "analytics",
        "engagement",
        "conversion optimization",
        "infrastructure as code",
        "cloud",
    ],
    "project_urls": {
        "Bug Reports": "https://github.com/aws-samples/pinpoint-ab-testing-cdk/issues",
        "Source": "https://github.com/aws-samples/pinpoint-ab-testing-cdk",
        "Documentation": "https://docs.aws.amazon.com/pinpoint/",
        "AWS CDK": "https://docs.aws.amazon.com/cdk/",
    },
    "entry_points": {
        "console_scripts": [
            "pinpoint-ab-testing-cdk=app:main",
        ],
    },
}

# Additional configuration for distribution
package_config.update({
    "zip_safe": False,
    "include_package_data": True,
    "package_data": {
        "": ["*.json", "*.yaml", "*.yml", "*.md", "*.txt"],
    },
    "exclude_package_data": {
        "": ["*.pyc", "__pycache__", "*.pyo", "*.pyd", ".git*"],
    },
})

# Setup configuration
if __name__ == "__main__":
    setup(**package_config)