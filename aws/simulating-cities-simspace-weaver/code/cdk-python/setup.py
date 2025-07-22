"""
Smart City Digital Twins with SimSpace Weaver and IoT - CDK Python Package Setup

This setup.py configures the Python package for the CDK application that deploys
a comprehensive smart city digital twin solution using AWS services.

Author: AWS CDK Generator
Version: 1.0
"""

import os
from setuptools import setup, find_packages

# Read the contents of README file
def read_readme():
    """Read README.md file if it exists."""
    readme_path = os.path.join(os.path.dirname(__file__), "README.md")
    if os.path.exists(readme_path):
        with open(readme_path, "r", encoding="utf-8") as f:
            return f.read()
    return "Smart City Digital Twins with SimSpace Weaver and IoT - CDK Python Application"

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
    name="smart-city-digital-twins-cdk",
    version="1.0.0",
    description="AWS CDK application for Smart City Digital Twins with SimSpace Weaver and IoT",
    long_description=read_readme(),
    long_description_content_type="text/markdown",
    
    # Author information
    author="AWS CDK Generator",
    author_email="aws-recipes@example.com",
    
    # Package information
    python_requires=">=3.8",
    packages=find_packages(exclude=["tests*", "docs*"]),
    include_package_data=True,
    
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
            "boto3-stubs[essential]>=1.34.0"
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.2.0",
            "aws-cdk.assertions>=2.0.0"
        ]
    },
    
    # Entry points for CLI
    entry_points={
        "console_scripts": [
            "smart-city-cdk=app:main",
        ],
    },
    
    # Classifiers for PyPI
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Framework :: AWS CDK",
        "Topic :: System :: Systems Administration",
        "Topic :: Scientific/Engineering :: Information Analysis",
    ],
    
    # Keywords for search
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "iot",
        "smart-city",
        "digital-twins",
        "simulation",
        "urban-planning",
        "simspace-weaver",
        "dynamodb",
        "lambda"
    ],
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "Tracker": "https://github.com/aws/aws-cdk/issues",
    },
    
    # Package data
    package_data={
        "": ["*.md", "*.txt", "*.yaml", "*.yml", "*.json"],
    },
    
    # ZIP safe
    zip_safe=False,
)