"""
Setup configuration for the Automated Cost Governance CDK Python application.

This setup.py file defines the package configuration, dependencies, and metadata
for the CDK application that implements automated cost governance using AWS Config
and Lambda remediation functions.
"""

import os
from setuptools import setup, find_packages

# Read the contents of requirements.txt
def read_requirements() -> list:
    """Read and return the requirements from requirements.txt file"""
    requirements_path = os.path.join(os.path.dirname(__file__), "requirements.txt")
    
    if not os.path.exists(requirements_path):
        return []
    
    with open(requirements_path, "r", encoding="utf-8") as f:
        requirements = []
        for line in f:
            line = line.strip()
            # Skip empty lines and comments
            if line and not line.startswith("#"):
                requirements.append(line)
        return requirements

# Read the README file for long description
def read_readme() -> str:
    """Read and return the README content"""
    readme_path = os.path.join(os.path.dirname(__file__), "..", "README.md")
    
    if os.path.exists(readme_path):
        with open(readme_path, "r", encoding="utf-8") as f:
            return f.read()
    return "Automated Cost Governance CDK Python Application"

setup(
    name="automated-cost-governance-cdk",
    version="1.0.0",
    author="AWS Cloud Recipes",
    author_email="recipes@example.com",
    description="CDK Python application for implementing automated cost governance",
    long_description=read_readme(),
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/cloud-recipes",
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/cloud-recipes/issues",
        "Source": "https://github.com/aws-samples/cloud-recipes",
        "Documentation": "https://github.com/aws-samples/cloud-recipes/tree/main/aws/automated-cost-governance-aws-config-lambda-remediation",
    },
    
    # Package configuration
    packages=find_packages(exclude=["tests*"]),
    include_package_data=True,
    
    # Dependencies
    install_requires=read_requirements(),
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Classification metadata
    classifiers=[
        "Development Status :: 4 - Beta",
        "Environment :: Console",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP",
        "Topic :: Utilities",
        "Typing :: Typed",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "cost-optimization",
        "governance",
        "automation",
        "lambda",
        "config",
        "finops",
    ],
    
    # Entry points for command-line tools (if needed)
    entry_points={
        "console_scripts": [
            # Add any command-line tools here if needed
            # "cost-governance=cost_governance.cli:main",
        ],
    },
    
    # Additional options
    zip_safe=False,
    
    # Test configuration
    test_suite="tests",
    
    # Package data
    package_data={
        "": ["*.md", "*.txt", "*.yaml", "*.yml", "*.json"],
    },
    
    # Additional metadata
    platforms=["any"],
    license="MIT",
    
    # Development dependencies (extras)
    extras_require={
        "dev": [
            "pytest>=7.2.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "pre-commit>=3.0.0",
        ],
        "nag": [
            "cdk-nag>=2.28.0",
        ],
        "docs": [
            "sphinx>=6.0.0",
            "sphinx-rtd-theme>=1.2.0",
        ],
    },
    
    # Options for setup tools
    options={
        "build_scripts": {
            "executable": "/usr/bin/env python3",
        },
    },
)