#!/usr/bin/env python3
"""
Setup script for AWS Application Discovery Service CDK Python application
"""

import os
from setuptools import setup, find_packages

# Read the contents of README file
this_directory = os.path.abspath(os.path.dirname(__file__))
with open(os.path.join(this_directory, "README.md"), encoding="utf-8") as f:
    long_description = f.read()

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file"""
    requirements = []
    with open("requirements.txt", "r") as req_file:
        for line in req_file:
            line = line.strip()
            if line and not line.startswith("#"):
                requirements.append(line)
    return requirements

setup(
    name="application-discovery-service-cdk",
    version="1.0.0",
    description="AWS CDK Python application for Application Discovery Service infrastructure",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS Solutions",
    author_email="aws-solutions@amazon.com",
    url="https://github.com/aws-samples/application-discovery-service-cdk",
    license="Apache-2.0",
    
    # Package configuration
    packages=find_packages(exclude=["tests", "tests.*"]),
    include_package_data=True,
    zip_safe=False,
    
    # Dependencies
    install_requires=read_requirements(),
    
    # Python version requirement
    python_requires=">=3.9",
    
    # Entry points
    entry_points={
        "console_scripts": [
            "app=app:main",
        ],
    },
    
    # Package classifiers
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
        "Typing :: Typed",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "application-discovery",
        "migration",
        "assessment",
        "infrastructure",
        "cloud",
        "devops",
    ],
    
    # Additional metadata
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/application-discovery-service-cdk/issues",
        "Source": "https://github.com/aws-samples/application-discovery-service-cdk",
        "Documentation": "https://docs.aws.amazon.com/application-discovery/",
    },
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.5.0",
            "pre-commit>=3.4.0",
        ],
        "test": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "pytest-xdist>=3.3.0",
            "moto>=4.2.0",
        ],
    },
    
    # Configuration for package tools
    options={
        "egg_info": {
            "tag_build": "",
            "tag_date": False,
        },
        "bdist_wheel": {
            "universal": False,
        },
    },
)