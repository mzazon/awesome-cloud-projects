"""
Setup configuration for Serverless API Development CDK Python application.

This setup.py file configures the Python package for the CDK application,
including dependencies, metadata, and development tools configuration.
"""

import setuptools
from typing import List


def read_requirements(filename: str) -> List[str]:
    """
    Read requirements from requirements.txt file.
    
    Args:
        filename: Path to requirements file
        
    Returns:
        List of requirement strings
    """
    try:
        with open(filename, "r", encoding="utf-8") as file:
            requirements = []
            for line in file:
                line = line.strip()
                # Skip comments and empty lines
                if line and not line.startswith("#"):
                    # Remove inline comments
                    requirement = line.split("#")[0].strip()
                    if requirement:
                        requirements.append(requirement)
            return requirements
    except FileNotFoundError:
        return []


def read_long_description() -> str:
    """Read long description from README file."""
    try:
        with open("README.md", "r", encoding="utf-8") as file:
            return file.read()
    except FileNotFoundError:
        return "CDK Python application for Serverless API Development with API Gateway and Lambda"


# Read requirements
install_requires = read_requirements("requirements.txt")

# Filter out development dependencies for production install
production_requirements = [
    req for req in install_requires 
    if not any(dev_pkg in req.lower() for dev_pkg in ["pytest", "black", "flake8", "mypy", "types-"])
]

# Development dependencies
dev_requirements = [
    req for req in install_requires 
    if any(dev_pkg in req.lower() for dev_pkg in ["pytest", "black", "flake8", "mypy", "types-"])
]

setuptools.setup(
    name="serverless-api-cdk",
    version="1.0.0",
    description="CDK Python application for Serverless API Development with API Gateway and Lambda",
    long_description=read_long_description(),
    long_description_content_type="text/markdown",
    author="AWS CDK Developer",
    author_email="developer@example.com",
    
    # Package information
    packages=setuptools.find_packages(),
    python_requires=">=3.9",
    
    # Dependencies
    install_requires=production_requirements,
    extras_require={
        "dev": dev_requirements,
        "test": [
            "pytest>=7.1.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",  # AWS service mocking for tests
        ]
    },
    
    # Classifiers
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Distributed Computing",
        "Topic :: Internet :: WWW/HTTP :: HTTP Servers",
    ],
    
    # Keywords
    keywords="aws cdk serverless api lambda dynamodb api-gateway",
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Source": "https://github.com/aws/aws-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
    },
    
    # Entry points
    entry_points={
        "console_scripts": [
            "deploy-serverless-api=app:main",
        ],
    },
    
    # Include additional files
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # Zip safe
    zip_safe=False,
)