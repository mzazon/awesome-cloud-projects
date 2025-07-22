"""
Setup configuration for AWS CDK Python RDS Disaster Recovery application.

This setup.py file configures the Python package for the RDS disaster recovery
CDK application, including dependencies, metadata, and installation requirements.
"""

import os
from setuptools import setup, find_packages

# Read the README file for the long description
def read_readme():
    """Read the README.md file for package description."""
    readme_path = os.path.join(os.path.dirname(__file__), "README.md")
    if os.path.exists(readme_path):
        with open(readme_path, "r", encoding="utf-8") as f:
            return f.read()
    return "AWS CDK Python application for RDS disaster recovery implementation"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file."""
    requirements_path = os.path.join(os.path.dirname(__file__), "requirements.txt")
    requirements = []
    if os.path.exists(requirements_path):
        with open(requirements_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                # Skip comments and empty lines
                if line and not line.startswith("#"):
                    requirements.append(line)
    return requirements

setup(
    name="rds-disaster-recovery-cdk",
    version="1.0.0",
    description="AWS CDK Python application for implementing RDS Disaster Recovery Solutions",
    long_description=read_readme(),
    long_description_content_type="text/markdown",
    
    # Author information
    author="AWS Recipe Generator",
    author_email="aws-recipes@example.com",
    
    # Package information
    packages=find_packages(exclude=["tests*"]),
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=read_requirements(),
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.1.0",
            "pytest-cov>=4.0.0",
            "pytest-mock>=3.10.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=0.991",
            "moto>=4.2.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
    },
    
    # Package metadata
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
        "Topic :: Database",
        "Topic :: System :: Recovery Tools",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "rds",
        "disaster-recovery",
        "database",
        "cloudformation",
        "infrastructure-as-code",
        "cloud",
        "monitoring",
        "automation",
    ],
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
    },
    
    # Entry points for command-line scripts
    entry_points={
        "console_scripts": [
            "rds-dr-deploy=app:main",
        ],
    },
    
    # Include additional files
    include_package_data=True,
    package_data={
        "": ["*.json", "*.yaml", "*.yml", "*.md", "*.txt"],
    },
    
    # Zip safety
    zip_safe=False,
    
    # License
    license="MIT",
    
    # Minimum Python version check
    python_requires=">=3.8",
)