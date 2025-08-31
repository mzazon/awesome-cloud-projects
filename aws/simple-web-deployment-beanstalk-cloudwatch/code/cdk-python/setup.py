#!/usr/bin/env python3
"""
Setup configuration for Simple Web Application CDK Python project.

This setup.py file configures the Python package for the CDK application,
including dependencies, metadata, and development tools configuration.
"""

import os
from pathlib import Path
import setuptools


def read_requirements(filename: str) -> list[str]:
    """
    Read requirements from a requirements file.
    
    Args:
        filename: Name of the requirements file
        
    Returns:
        List of requirement strings
    """
    requirements_path = Path(__file__).parent / filename
    if not requirements_path.exists():
        return []
    
    with open(requirements_path, encoding="utf-8") as f:
        requirements = []
        for line in f:
            line = line.strip()
            # Skip comments and empty lines
            if line and not line.startswith("#"):
                # Remove inline comments
                requirement = line.split("#")[0].strip()
                if requirement:
                    requirements.append(requirement)
        return requirements


def read_long_description() -> str:
    """
    Read the long description from README file.
    
    Returns:
        Long description string
    """
    readme_path = Path(__file__).parent / "README.md"
    if readme_path.exists():
        with open(readme_path, encoding="utf-8") as f:
            return f.read()
    return "Simple Web Application CDK Python project"


# Read requirements
install_requires = read_requirements("requirements.txt")

# Filter out development dependencies for install_requires
dev_keywords = ["pytest", "black", "flake8", "mypy", "bandit", "sphinx", "safety", "isort", "autopep8"]
install_requires = [
    req for req in install_requires 
    if not any(keyword in req.lower() for keyword in dev_keywords)
]

# Development dependencies
dev_requires = read_requirements("requirements.txt")
dev_requires = [
    req for req in dev_requires 
    if any(keyword in req.lower() for keyword in dev_keywords)
]

setuptools.setup(
    name="simple-web-app-cdk",
    version="1.0.0",
    description="AWS CDK Python application for Simple Web Deployment with Elastic Beanstalk and CloudWatch",
    long_description=read_long_description(),
    long_description_content_type="text/markdown",
    author="AWS CDK Team",
    author_email="aws-cdk-team@example.com",
    license="MIT",
    url="https://github.com/aws-samples/simple-web-app-cdk",
    
    # Package configuration
    packages=setuptools.find_packages(exclude=["tests*"]),
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=install_requires,
    extras_require={
        "dev": dev_requires,
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.2.0",
        ],
        "security": [
            "bandit>=1.7.0",
            "safety>=2.3.0",
        ],
    },
    
    # Entry points
    entry_points={
        "console_scripts": [
            "simple-web-app-cdk=app:main",
        ],
    },
    
    # Classifiers for PyPI
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
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
        "Topic :: Internet :: WWW/HTTP :: WSGI :: Application",
        "Framework :: AWS CDK",
    ],
    
    # Keywords for discovery
    keywords=[
        "aws", "cdk", "cloud", "infrastructure", "elastic-beanstalk", 
        "cloudwatch", "monitoring", "web-application", "python", "flask"
    ],
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws-samples/simple-web-app-cdk",
        "Bug Reports": "https://github.com/aws-samples/simple-web-app-cdk/issues",
        "AWS CDK": "https://aws.amazon.com/cdk/",
        "AWS Elastic Beanstalk": "https://aws.amazon.com/elasticbeanstalk/",
        "AWS CloudWatch": "https://aws.amazon.com/cloudwatch/",
    },
    
    # Include package data
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.yaml", "*.yml", "*.json"],
    },
    
    # Zip safety
    zip_safe=False,
)