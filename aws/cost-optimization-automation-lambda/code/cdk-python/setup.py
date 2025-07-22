"""
Setup configuration for Cost Optimization Automation CDK Python application

This setup.py file defines the package configuration for the CDK application
that implements automated cost optimization using Lambda and Trusted Advisor APIs.
"""

from setuptools import setup, find_packages

# Read the contents of README file
from pathlib import Path
this_directory = Path(__file__).parent
long_description = (this_directory / "README.md").read_text() if (this_directory / "README.md").exists() else ""

setup(
    name="cost-optimization-automation-cdk",
    version="1.0.0",
    description="CDK Python application for automated cost optimization using Lambda and Trusted Advisor APIs",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS Cost Optimization Team",
    author_email="admin@example.com",
    url="https://github.com/your-org/cost-optimization-automation",
    
    # Package discovery
    packages=find_packages(where=".", exclude=["tests", "tests.*"]),
    package_dir={"": "."},
    
    # Python version requirement
    python_requires=">=3.9",
    
    # Package dependencies
    install_requires=[
        "aws-cdk-lib>=2.100.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.26.0",
        "botocore>=1.29.0",
    ],
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "aws-cli>=2.0.0",
            "python-dotenv>=1.0.0",
            "pydantic>=1.10.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",  # For mocking AWS services in tests
            "pytest-mock>=3.0.0",
        ],
    },
    
    # Entry points for CLI commands
    entry_points={
        "console_scripts": [
            "cost-optimization-deploy=app:main",
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
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Office/Business :: Financial",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "cost-optimization",
        "lambda",
        "trusted-advisor",
        "automation",
        "infrastructure",
        "cloud",
        "finops",
    ],
    
    # Include package data
    include_package_data=True,
    
    # Package data files
    package_data={
        "": [
            "*.json",
            "*.yaml",
            "*.yml",
            "*.md",
            "*.txt",
        ],
    },
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/your-org/cost-optimization-automation/issues",
        "Documentation": "https://github.com/your-org/cost-optimization-automation/wiki",
        "Source": "https://github.com/your-org/cost-optimization-automation",
        "Funding": "https://github.com/sponsors/your-org",
    },
    
    # License
    license="MIT",
    
    # Zip safety
    zip_safe=False,
)