#!/usr/bin/env python3
"""
Setup configuration for the video processing workflows CDK Python application.

This setup.py file configures the Python package for the CDK application that
creates an event-driven video processing pipeline using S3, Lambda, and MediaConvert.
"""

import os
from setuptools import setup, find_packages

# Read the README file for the long description
def read_readme():
    """Read the README.md file for the long description."""
    readme_path = os.path.join(os.path.dirname(__file__), "README.md")
    if os.path.exists(readme_path):
        with open(readme_path, "r", encoding="utf-8") as f:
            return f.read()
    return "CDK Python application for video processing workflows"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file."""
    requirements_path = os.path.join(os.path.dirname(__file__), "requirements.txt")
    requirements = []
    if os.path.exists(requirements_path):
        with open(requirements_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                # Skip empty lines and comments
                if line and not line.startswith("#"):
                    requirements.append(line)
    return requirements

setup(
    name="video-processing-workflows-cdk",
    version="1.0.0",
    description="CDK Python application for video processing workflows with S3, Lambda, and MediaConvert",
    long_description=read_readme(),
    long_description_content_type="text/markdown",
    author="AWS CDK Team",
    author_email="aws-cdk-team@amazon.com",
    url="https://github.com/aws/aws-cdk",
    license="Apache-2.0",
    
    # Package configuration
    packages=find_packages(exclude=["tests*"]),
    include_package_data=True,
    zip_safe=False,
    
    # Python version requirements
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
            "isort>=5.0.0",
        ],
    },
    
    # Entry points
    entry_points={
        "console_scripts": [
            "video-processing-cdk=app:main",
        ],
    },
    
    # Package classifiers
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Code Generators",
        "Topic :: Utilities",
        "Typing :: Typed",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "video-processing",
        "lambda",
        "s3",
        "mediaconvert",
        "serverless",
        "event-driven",
    ],
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "Tracker": "https://github.com/aws/aws-cdk/issues",
    },
    
    # Package metadata
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # Exclude development files from distribution
    exclude_package_data={
        "": ["*.pyc", "*.pyo", "*~", "__pycache__/*"],
    },
)