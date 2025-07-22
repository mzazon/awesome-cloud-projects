"""
Setup script for AWS CDK Python Database Migration Application.

This setup.py file configures the Python package for the AWS DMS migration solution,
including dependencies, metadata, and installation requirements.
"""

from setuptools import setup, find_packages
import os

# Read the README file for long description
def read_readme() -> str:
    """Read README.md file for package description."""
    readme_path = os.path.join(os.path.dirname(__file__), "README.md")
    if os.path.exists(readme_path):
        with open(readme_path, "r", encoding="utf-8") as f:
            return f.read()
    return "AWS CDK Python application for database migration with AWS DMS"

# Read requirements from requirements.txt
def read_requirements() -> list:
    """Read requirements.txt file for package dependencies."""
    requirements_path = os.path.join(os.path.dirname(__file__), "requirements.txt")
    requirements = []
    if os.path.exists(requirements_path):
        with open(requirements_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                # Skip comments and empty lines
                if line and not line.startswith("#"):
                    # Remove inline comments
                    requirement = line.split("#")[0].strip()
                    if requirement:
                        requirements.append(requirement)
    return requirements

setup(
    name="aws-dms-migration-cdk",
    version="1.0.0",
    description="AWS CDK Python application for database migration with AWS DMS",
    long_description=read_readme(),
    long_description_content_type="text/markdown",
    author="AWS Solutions",
    author_email="aws-solutions@amazon.com",
    url="https://github.com/aws-samples/aws-cdk-database-migration",
    
    # Package configuration
    packages=find_packages(exclude=["tests*"]),
    include_package_data=True,
    zip_safe=False,
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=read_requirements(),
    
    # Optional dependencies for development
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "isort>=5.0.0",
            "mypy>=1.0.0",
            "bandit>=1.7.0",
            "safety>=2.0.0"
        ],
        "testing": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0"
        ]
    },
    
    # Entry points for command-line scripts
    entry_points={
        "console_scripts": [
            "deploy-dms-migration=app:main",
        ],
    },
    
    # Package classifiers
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Database",
        "Topic :: Internet :: WWW/HTTP",
        "Typing :: Typed"
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "database",
        "migration",
        "dms",
        "cloud",
        "infrastructure",
        "devops",
        "automation"
    ],
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/dms/",
        "Source": "https://github.com/aws-samples/aws-cdk-database-migration",
        "Bug Reports": "https://github.com/aws-samples/aws-cdk-database-migration/issues",
        "AWS DMS": "https://aws.amazon.com/dms/",
        "AWS CDK": "https://aws.amazon.com/cdk/"
    },
    
    # Package metadata
    license="Apache-2.0",
    platforms=["any"],
    
    # Test suite configuration
    test_suite="tests",
    
    # Additional package data
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"]
    }
)