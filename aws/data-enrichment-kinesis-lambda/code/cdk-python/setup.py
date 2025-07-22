"""
Setup configuration for the Data Enrichment CDK Python application.

This setup file configures the Python package for the streaming data enrichment
pipeline CDK application, including dependencies, metadata, and development tools.
"""

import setuptools
from typing import List


def read_requirements() -> List[str]:
    """
    Read requirements from requirements.txt file.
    
    Returns:
        List of package requirements
    """
    try:
        with open("requirements.txt", "r", encoding="utf-8") as file:
            requirements = [
                line.strip() 
                for line in file.readlines() 
                if line.strip() and not line.startswith("#")
            ]
        return requirements
    except FileNotFoundError:
        return []


def read_long_description() -> str:
    """
    Read the long description from README.md if it exists.
    
    Returns:
        Long description text or empty string
    """
    try:
        with open("README.md", "r", encoding="utf-8") as file:
            return file.read()
    except FileNotFoundError:
        return "Streaming data enrichment pipeline using AWS CDK Python"


setuptools.setup(
    name="data-enrichment-cdk",
    version="1.0.0",
    
    # Package metadata
    description="AWS CDK Python application for streaming data enrichment with Kinesis and Lambda",
    long_description=read_long_description(),
    long_description_content_type="text/markdown",
    
    # Author information
    author="AWS CDK Developer",
    author_email="developer@example.com",
    
    # Package configuration
    packages=setuptools.find_packages(),
    py_modules=["app"],
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=read_requirements(),
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=8.0.0",
            "mypy>=1.0.0",
            "black>=24.0.0",
            "flake8>=7.0.0",
            "isort>=5.0.0",
        ],
        "test": [
            "pytest>=8.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",  # For mocking AWS services in tests
        ]
    },
    
    # Package classifiers
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
        "Framework :: AWS CDK",
        "Environment :: Console",
        "Operating System :: OS Independent",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws", "cdk", "kinesis", "lambda", "dynamodb", "s3",
        "streaming", "data-enrichment", "real-time", "analytics",
        "serverless", "cloud", "infrastructure", "python"
    ],
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "Tracker": "https://github.com/aws/aws-cdk/issues",
    },
    
    # Entry points for command-line tools
    entry_points={
        "console_scripts": [
            "data-enrichment-deploy=app:main",
        ],
    },
    
    # Include additional files in package
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # Zip safety
    zip_safe=False,
)