"""
Setup configuration for Progressive Web App CDK Python application.

This setup file configures the Python package for the CDK application that
deploys Progressive Web Apps using AWS Amplify hosting with CloudFront,
custom domains, and comprehensive monitoring.
"""

import io
import os
import re
from typing import Dict, List

from setuptools import find_packages, setup


def read_file(filename: str) -> str:
    """Read file contents safely."""
    here = os.path.abspath(os.path.dirname(__file__))
    with io.open(os.path.join(here, filename), encoding='utf-8') as f:
        return f.read()


def get_version() -> str:
    """Extract version from app.py without importing it."""
    content = read_file('app.py')
    version_match = re.search(r"__version__ = ['\"]([^'\"]*)['\"]", content)
    if version_match:
        return version_match.group(1)
    return "1.0.0"


def get_requirements() -> List[str]:
    """Parse requirements.txt file."""
    try:
        content = read_file('requirements.txt')
        requirements = []
        for line in content.strip().split('\n'):
            line = line.strip()
            # Skip comments and empty lines
            if line and not line.startswith('#'):
                requirements.append(line)
        return requirements
    except FileNotFoundError:
        return [
            "aws-cdk-lib>=2.110.0,<3.0.0",
            "constructs>=10.3.0,<11.0.0",
        ]


# Package metadata
PACKAGE_INFO: Dict[str, str] = {
    "name": "progressive-web-app-cdk",
    "version": get_version(),
    "description": "AWS CDK Python application for deploying Progressive Web Apps with Amplify Hosting",
    "long_description": read_file("README.md") if os.path.exists("README.md") else "",
    "long_description_content_type": "text/markdown",
    "author": "AWS CDK Team",
    "author_email": "aws-cdk@amazon.com",
    "url": "https://github.com/aws/aws-cdk",
    "license": "Apache-2.0",
}

# Classifiers for PyPI
CLASSIFIERS: List[str] = [
    "Development Status :: 5 - Production/Stable",
    "Intended Audience :: Developers",
    "License :: OSI Approved :: Apache Software License",
    "Operating System :: OS Independent",
    "Programming Language :: Python :: 3",
    "Programming Language :: Python :: 3.8",
    "Programming Language :: Python :: 3.9",
    "Programming Language :: Python :: 3.10",
    "Programming Language :: Python :: 3.11",
    "Programming Language :: Python :: 3.12",
    "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
    "Topic :: Software Development :: Libraries :: Application Frameworks",
    "Topic :: System :: Installation/Setup",
    "Typing :: Typed",
]

# Keywords for discoverability
KEYWORDS: List[str] = [
    "aws",
    "cdk",
    "cloud",
    "infrastructure",
    "progressive-web-app",
    "pwa",
    "amplify",
    "cloudfront",
    "hosting",
    "cicd",
    "ssl",
    "certificate",
    "domain",
    "monitoring",
    "serverless",
]

# Development dependencies for testing and linting
EXTRAS_REQUIRE: Dict[str, List[str]] = {
    "dev": [
        "pytest>=7.4.0",
        "pytest-cov>=4.1.0",
        "black>=23.7.0",
        "flake8>=6.0.0",
        "mypy>=1.5.0",
        "bandit>=1.7.5",
        "isort>=5.12.0",
        "autopep8>=2.0.4",
        "safety>=2.3.0",
    ],
    "docs": [
        "sphinx>=7.1.0",
        "sphinx-rtd-theme>=1.3.0",
    ],
    "test": [
        "pytest>=7.4.0",
        "pytest-cov>=4.1.0",
        "moto>=4.2.0",
        "boto3-stubs[amplify,cloudformation,route53,certificatemanager]>=1.28.0",
    ],
}

# Project URLs for additional links
PROJECT_URLS: Dict[str, str] = {
    "Documentation": "https://docs.aws.amazon.com/cdk/",
    "Source": "https://github.com/aws/aws-cdk",
    "Tracker": "https://github.com/aws/aws-cdk/issues",
    "Changelog": "https://github.com/aws/aws-cdk/releases",
}

# Entry points for command-line interfaces
ENTRY_POINTS: Dict[str, List[str]] = {
    "console_scripts": [
        "pwa-cdk=app:main",
    ],
}

# Package data to include
PACKAGE_DATA: Dict[str, List[str]] = {
    "": ["*.md", "*.txt", "*.json", "*.yml", "*.yaml"],
}

# Setup configuration
setup(
    # Basic package information
    name=PACKAGE_INFO["name"],
    version=PACKAGE_INFO["version"],
    description=PACKAGE_INFO["description"],
    long_description=PACKAGE_INFO["long_description"],
    long_description_content_type=PACKAGE_INFO["long_description_content_type"],
    
    # Author information
    author=PACKAGE_INFO["author"],
    author_email=PACKAGE_INFO["author_email"],
    url=PACKAGE_INFO["url"],
    project_urls=PROJECT_URLS,
    
    # License
    license=PACKAGE_INFO["license"],
    
    # Package discovery and inclusion
    packages=find_packages(exclude=["tests", "tests.*"]),
    package_data=PACKAGE_DATA,
    include_package_data=True,
    
    # Dependencies
    install_requires=get_requirements(),
    extras_require=EXTRAS_REQUIRE,
    
    # Python version requirements
    python_requires=">=3.8",
    
    # PyPI metadata
    classifiers=CLASSIFIERS,
    keywords=" ".join(KEYWORDS),
    
    # Entry points
    entry_points=ENTRY_POINTS,
    
    # Zip safety
    zip_safe=False,
    
    # Additional metadata
    platforms=["any"],
    
    # CLI options
    options={
        "bdist_wheel": {
            "universal": False,
        },
    },
)