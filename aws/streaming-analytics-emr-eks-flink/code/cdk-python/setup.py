"""
Setup configuration for Flink Streaming Analytics CDK Application

This setup.py file configures the Python package for the real-time streaming
analytics platform using AWS CDK. It includes all necessary dependencies,
development tools, and package metadata.

Author: AWS CDK Generator
Version: 1.0.0
"""

from setuptools import setup, find_packages
import os

# Read the README file for long description
def read_readme():
    """Read README.md file for long description"""
    readme_path = os.path.join(os.path.dirname(__file__), "README.md")
    if os.path.exists(readme_path):
        with open(readme_path, "r", encoding="utf-8") as fh:
            return fh.read()
    return "Real-time streaming analytics platform with EMR on EKS and Apache Flink"

# Read requirements from requirements.txt
def read_requirements():
    """Read and parse requirements.txt file"""
    requirements_path = os.path.join(os.path.dirname(__file__), "requirements.txt")
    requirements = []
    
    if os.path.exists(requirements_path):
        with open(requirements_path, "r", encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                # Skip comments and empty lines
                if line and not line.startswith("#"):
                    requirements.append(line)
    
    return requirements

# Package metadata
setup(
    name="flink-streaming-analytics-cdk",
    version="1.0.0",
    description="AWS CDK application for real-time streaming analytics with EMR on EKS and Apache Flink",
    long_description=read_readme(),
    long_description_content_type="text/markdown",
    author="AWS CDK Generator",
    author_email="data-engineering@company.com",
    url="https://github.com/company/flink-streaming-analytics",
    
    # Package discovery
    packages=find_packages(exclude=["tests", "tests.*"]),
    
    # Include non-Python files
    include_package_data=True,
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=read_requirements(),
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.7.0",
            "flake8>=6.0.0",
            "mypy>=1.5.0",
            "bandit>=1.7.5",
            "safety>=2.3.0",
            "pip-audit>=2.6.0",
        ],
        "docs": [
            "sphinx>=7.1.0",
            "sphinx-rtd-theme>=1.3.0",
        ],
        "test": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "moto>=4.2.0",
            "boto3-stubs[essential]",
        ]
    },
    
    # Package classifiers
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Operating System :: OS Independent",
        "Framework :: AWS CDK",
        "Framework :: AWS CDK :: 2",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "streaming",
        "analytics",
        "flink",
        "emr",
        "eks",
        "kinesis",
        "real-time",
        "data-engineering",
        "infrastructure-as-code"
    ],
    
    # Entry points for command-line scripts
    entry_points={
        "console_scripts": [
            "deploy-flink-analytics=app:main",
        ],
    },
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/company/flink-streaming-analytics/issues",
        "Source": "https://github.com/company/flink-streaming-analytics",
        "Documentation": "https://docs.company.com/flink-streaming-analytics",
    },
    
    # Package data
    package_data={
        "": ["*.yaml", "*.yml", "*.json", "*.md", "*.txt"],
    },
    
    # Zip safety
    zip_safe=False,
    
    # Additional metadata
    platforms=["any"],
    license="Apache License 2.0",
    
    # Test configuration
    test_suite="tests",
)