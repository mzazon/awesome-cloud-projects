"""
Setup configuration for Analytics-Ready Data Storage with S3 Tables CDK Python application.

This setup file defines the package configuration, dependencies, and metadata
for the CDK Python application that creates analytics infrastructure using
Amazon S3 Tables with Apache Iceberg format.
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
        with open("requirements.txt", "r", encoding="utf-8") as f:
            requirements = []
            for line in f:
                line = line.strip()
                # Skip empty lines and comments
                if line and not line.startswith("#"):
                    # Remove inline comments
                    requirement = line.split("#")[0].strip()
                    if requirement:
                        requirements.append(requirement)
            return requirements
    except FileNotFoundError:
        # Fallback to minimal requirements if file doesn't exist
        return [
            "aws-cdk-lib>=2.150.0,<3.0.0",
            "constructs>=10.0.0,<12.0.0",
        ]


def read_long_description() -> str:
    """
    Read long description from README file.
    
    Returns:
        Long description text
    """
    try:
        with open("README.md", "r", encoding="utf-8") as f:
            return f.read()
    except FileNotFoundError:
        return """
        Analytics-Ready Data Storage with S3 Tables CDK Python Application
        
        This CDK application creates a complete analytics infrastructure using
        Amazon S3 Tables with Apache Iceberg format for optimized tabular data
        storage and querying capabilities.
        """


setuptools.setup(
    name="analytics-s3-tables-cdk",
    version="1.0.0",
    description="CDK Python application for Analytics-Ready Data Storage with S3 Tables",
    long_description=read_long_description(),
    long_description_content_type="text/markdown",
    author="AWS Recipes",
    author_email="aws-recipes@example.com",
    license="MIT",
    url="https://github.com/aws-recipes/analytics-ready-data-storage-s3-tables",
    
    # Package configuration
    packages=setuptools.find_packages(exclude=["tests", "tests.*"]),
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Package dependencies
    install_requires=read_requirements(),
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "isort>=5.12.0",
            "bandit>=1.7.0",
            "safety>=2.3.0",
        ],
        "docs": [
            "sphinx>=7.0.0",
            "sphinx-rtd-theme>=1.3.0",
        ],
        "testing": [
            "moto>=4.2.0",
            "boto3-stubs[essential]>=1.34.0",
        ],
    },
    
    # Entry points for CLI commands
    entry_points={
        "console_scripts": [
            "analytics-s3-tables-deploy=app:main",
        ],
    },
    
    # Package classifiers for PyPI
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
        "Topic :: Internet :: WWW/HTTP",
        "Framework :: AWS CDK",
        "Framework :: AWS CDK :: 2",
    ],
    
    # Keywords for discoverability
    keywords=[
        "aws",
        "cdk",
        "s3-tables",
        "analytics",
        "iceberg",
        "athena",
        "glue",
        "data-lake",
        "infrastructure-as-code",
        "cloud-computing",
    ],
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws-recipes/analytics-ready-data-storage-s3-tables",
        "Bug Reports": "https://github.com/aws-recipes/analytics-ready-data-storage-s3-tables/issues",
        "AWS S3 Tables": "https://aws.amazon.com/s3/features/tables/",
        "Apache Iceberg": "https://iceberg.apache.org/",
    },
    
    # Include additional files in the package
    include_package_data=True,
    package_data={
        "": [
            "*.md",
            "*.txt",
            "*.json",
            "*.yaml",
            "*.yml",
        ],
    },
    
    # Zip safe configuration
    zip_safe=False,
)