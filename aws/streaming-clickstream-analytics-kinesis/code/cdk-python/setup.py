#!/usr/bin/env python3
"""
Setup configuration for Real-time Clickstream Analytics CDK Application

This setup.py file configures the Python package for the real-time clickstream
analytics CDK application, enabling proper dependency management, installation,
and distribution of the infrastructure code.

Author: AWS CDK Team
Version: 1.0
License: MIT
"""

import pathlib
from setuptools import setup, find_packages

# Read the README file for long description
here = pathlib.Path(__file__).parent.resolve()
long_description = (here / "README.md").read_text(encoding="utf-8") if (here / "README.md").exists() else ""

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file."""
    requirements_file = here / "requirements.txt"
    if requirements_file.exists():
        with open(requirements_file, "r", encoding="utf-8") as f:
            return [
                line.strip() 
                for line in f 
                if line.strip() and not line.startswith("#")
            ]
    return []

setup(
    # Package metadata
    name="clickstream-analytics-cdk",
    version="1.0.0",
    description="Real-time clickstream analytics pipeline using AWS CDK",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    # Author information
    author="AWS CDK Team",
    author_email="aws-cdk-team@example.com",
    
    # Project URLs
    url="https://github.com/aws-samples/clickstream-analytics-cdk",
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/clickstream-analytics-cdk/issues",
        "Source": "https://github.com/aws-samples/clickstream-analytics-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
    },
    
    # Package configuration
    packages=find_packages(exclude=["tests", "tests.*"]),
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=read_requirements(),
    
    # Optional dependencies for development
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "bandit>=1.7.0",
            "safety>=2.0.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
    },
    
    # Package classification
    classifiers=[
        # Development status
        "Development Status :: 4 - Beta",
        
        # Intended audience
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        
        # Topic classification
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
        
        # License
        "License :: OSI Approved :: MIT License",
        
        # Python version support
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        
        # Operating system support
        "Operating System :: OS Independent",
        
        # Framework
        "Framework :: AWS CDK",
    ],
    
    # Keywords for discovery
    keywords="aws cdk kinesis lambda dynamodb analytics clickstream real-time serverless",
    
    # Entry points for command-line tools
    entry_points={
        "console_scripts": [
            "deploy-clickstream=app:main",
        ],
    },
    
    # Include additional files
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # Zip safety
    zip_safe=False,
    
    # Project metadata for PyPI
    license="MIT",
    platforms=["any"],
    
    # Additional metadata
    maintainer="AWS CDK Team",
    maintainer_email="aws-cdk-team@example.com",
    
    # Download URL
    download_url="https://github.com/aws-samples/clickstream-analytics-cdk/archive/v1.0.0.tar.gz",
)

# Installation instructions for developers:
#
# 1. Clone the repository:
#    git clone https://github.com/aws-samples/clickstream-analytics-cdk.git
#    cd clickstream-analytics-cdk
#
# 2. Create and activate virtual environment:
#    python -m venv .venv
#    source .venv/bin/activate  # On Windows: .venv\Scripts\activate
#
# 3. Install in development mode:
#    pip install -e .[dev]
#
# 4. Install CDK CLI (if not already installed):
#    npm install -g aws-cdk
#
# 5. Bootstrap CDK (first time only):
#    cdk bootstrap
#
# 6. Deploy the stack:
#    cdk deploy
#
# 7. Run tests:
#    pytest
#
# 8. Clean up:
#    cdk destroy