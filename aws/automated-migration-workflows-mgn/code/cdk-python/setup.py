"""
Setup configuration for Automated Application Migration Workflows CDK Python Application

This setup.py file configures the Python package for the CDK application that
deploys automated application migration workflows using AWS Application Migration
Service (MGN) and Migration Hub Orchestrator.
"""

from setuptools import setup, find_packages

# Read the contents of the README file
from pathlib import Path
this_directory = Path(__file__).parent
long_description = (this_directory / "README.md").read_text() if (this_directory / "README.md").exists() else ""

# Read requirements from requirements.txt
requirements_path = this_directory / "requirements.txt"
if requirements_path.exists():
    with open(requirements_path, "r", encoding="utf-8") as f:
        requirements = [
            line.strip() 
            for line in f.readlines() 
            if line.strip() and not line.startswith("#") and not line.startswith("-")
        ]
else:
    requirements = [
        "aws-cdk-lib>=2.120.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.26.0",
    ]

setup(
    name="migration-workflow-cdk",
    version="1.0.0",
    description="CDK Python application for automated application migration workflows",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS CDK Team",
    author_email="aws-cdk-dev@amazon.com",
    url="https://github.com/aws/aws-cdk",
    
    # Package configuration
    packages=find_packages(exclude=["tests", "tests.*"]),
    package_dir={"": "."},
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=requirements,
    
    # Optional dependencies for development and testing
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "bandit>=1.7.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
        "type-checking": [
            "boto3-stubs[essential]>=1.26.0",
            "mypy>=1.0.0",
        ],
    },
    
    # Entry points
    entry_points={
        "console_scripts": [
            "migration-workflow-cdk=app:main",
        ],
    },
    
    # Package classifiers
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: Apache Software License",
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
    
    # Package metadata
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "migration",
        "mgn",
        "application-migration-service",
        "migration-hub-orchestrator",
        "infrastructure-as-code",
        "devops",
        "automation",
    ],
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "Tracker": "https://github.com/aws/aws-cdk/issues",
    },
    
    # Include package data
    include_package_data=True,
    
    # Package data files
    package_data={
        "": ["*.json", "*.yaml", "*.yml", "*.md", "*.txt"],
    },
    
    # Zip safety
    zip_safe=False,
    
    # License
    license="Apache-2.0",
    
    # Platform compatibility
    platforms=["any"],
)