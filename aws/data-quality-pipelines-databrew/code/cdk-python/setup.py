"""
Setup configuration for AWS CDK Python Data Quality Pipeline application.

This setup file configures the Python package for the automated data quality
pipeline using AWS Glue DataBrew and EventBridge.
"""

from setuptools import setup, find_packages
import os

# Read version from VERSION file or use default
version = "1.0.0"
if os.path.exists("VERSION"):
    with open("VERSION", "r") as f:
        version = f.read().strip()

# Read long description from README file
long_description = ""
if os.path.exists("README.md"):
    with open("README.md", "r", encoding="utf-8") as f:
        long_description = f.read()

# Read requirements from requirements.txt
requirements = []
if os.path.exists("requirements.txt"):
    with open("requirements.txt", "r") as f:
        requirements = [
            line.strip() for line in f.readlines() 
            if line.strip() and not line.startswith("#")
        ]

# Development requirements
dev_requirements = [
    "pytest>=7.4.0,<8.0.0",
    "pytest-cov>=4.1.0,<5.0.0",
    "black>=23.7.0,<24.0.0",
    "flake8>=6.0.0,<7.0.0",
    "mypy>=1.5.0,<2.0.0",
    "bandit>=1.7.5,<2.0.0",
    "safety>=2.3.0,<3.0.0",
]

# Documentation requirements
docs_requirements = [
    "sphinx>=7.1.0,<8.0.0",
    "sphinx-rtd-theme>=1.3.0,<2.0.0",
]

setup(
    name="data-quality-pipeline-cdk",
    version=version,
    description="AWS CDK Python application for automated data quality pipeline",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS CDK Generator",
    author_email="aws-cdk-generator@example.com",
    url="https://github.com/aws-samples/data-quality-pipeline-cdk",
    license="MIT",
    
    # Package configuration
    packages=find_packages(exclude=["tests", "tests.*"]),
    include_package_data=True,
    zip_safe=False,
    
    # Python version requirements
    python_requires=">=3.8",
    
    # Package dependencies
    install_requires=requirements,
    extras_require={
        "dev": dev_requirements,
        "docs": docs_requirements,
        "all": dev_requirements + docs_requirements,
    },
    
    # Entry points for command-line tools
    entry_points={
        "console_scripts": [
            "data-quality-pipeline=app:main",
        ],
    },
    
    # Package metadata
    classifiers=[
        "Development Status :: 5 - Production/Stable",
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
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Utilities",
        "Typing :: Typed",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "databrew",
        "glue",
        "eventbridge",
        "data-quality",
        "pipeline",
        "automation",
        "analytics",
        "etl",
        "lambda",
        "s3",
        "sns",
    ],
    
    # Package metadata
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/data-quality-pipeline-cdk/issues",
        "Source": "https://github.com/aws-samples/data-quality-pipeline-cdk",
        "Documentation": "https://github.com/aws-samples/data-quality-pipeline-cdk/blob/main/README.md",
    },
    
    # Additional package data
    package_data={
        "": ["*.md", "*.txt", "*.yaml", "*.yml", "*.json"],
    },
)