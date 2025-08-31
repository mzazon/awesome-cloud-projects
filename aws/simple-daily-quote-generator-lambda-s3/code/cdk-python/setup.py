"""
Setup configuration for Daily Quote Generator CDK Python application.

This setup.py file configures the Python package for the CDK application,
including dependencies, metadata, and development requirements.
"""

import setuptools
from typing import List


def get_requirements() -> List[str]:
    """
    Read requirements from requirements.txt file.
    
    Returns:
        List[str]: List of package requirements
    """
    with open("requirements.txt", "r", encoding="utf-8") as fh:
        requirements = []
        for line in fh:
            line = line.strip()
            # Skip comments and empty lines
            if line and not line.startswith("#"):
                requirements.append(line)
        return requirements


def get_long_description() -> str:
    """
    Read long description from README.md if it exists.
    
    Returns:
        str: Long description for the package
    """
    try:
        with open("README.md", "r", encoding="utf-8") as fh:
            return fh.read()
    except FileNotFoundError:
        return "Simple Daily Quote Generator using AWS Lambda and S3"


setuptools.setup(
    name="daily-quote-generator-cdk",
    version="1.0.0",
    
    # Package metadata
    author="AWS CDK Developer",
    author_email="developer@example.com",
    description="CDK Python application for Simple Daily Quote Generator",
    long_description=get_long_description(),
    long_description_content_type="text/markdown",
    url="https://github.com/example/daily-quote-generator",
    
    # Package configuration
    packages=setuptools.find_packages(),
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Typing :: Typed",
    ],
    
    # Python version requirements
    python_requires=">=3.9",
    
    # Dependencies
    install_requires=get_requirements(),
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=8.0.0",
            "pytest-cov>=6.0.0",
            "mypy>=1.13.0",
            "black>=24.0.0",
            "flake8>=7.0.0",
            "pre-commit>=3.0.0",
        ],
        "test": [
            "pytest>=8.0.0",
            "pytest-cov>=6.0.0",
            "moto>=5.0.0",  # For mocking AWS services in tests
        ],
    },
    
    # Entry points for CLI commands
    entry_points={
        "console_scripts": [
            "deploy-quote-generator=app:main",
        ],
    },
    
    # Include package data
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/example/daily-quote-generator/issues",
        "Source": "https://github.com/example/daily-quote-generator",
        "Documentation": "https://github.com/example/daily-quote-generator/blob/main/README.md",
    },
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "lambda",
        "s3",
        "serverless",
        "quotes",
        "api",
        "python",
        "infrastructure-as-code",
    ],
    
    # License
    license="Apache-2.0",
    
    # Package compatibility
    zip_safe=False,
)