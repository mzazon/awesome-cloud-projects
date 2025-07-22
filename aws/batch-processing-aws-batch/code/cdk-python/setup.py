"""
Setup configuration for AWS Batch Processing Workloads CDK Application

This setup.py file configures the Python package for the AWS CDK application
that creates batch processing infrastructure on AWS.
"""

import setuptools
from pathlib import Path

# Read the README file for the long description
this_directory = Path(__file__).parent
long_description = ""
readme_path = this_directory / "README.md"
if readme_path.exists():
    long_description = readme_path.read_text(encoding="utf-8")

# Read requirements from requirements.txt
requirements_path = this_directory / "requirements.txt"
install_requires = []
if requirements_path.exists():
    with open(requirements_path, "r", encoding="utf-8") as f:
        install_requires = [
            line.strip() 
            for line in f.readlines() 
            if line.strip() and not line.startswith("#")
        ]

setuptools.setup(
    name="aws-batch-processing-cdk",
    version="1.2.0",
    description="AWS CDK v2 application for batch processing workloads with AWS Batch",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    # Author information
    author="AWS CDK Generator",
    author_email="",
    
    # Package information  
    packages=setuptools.find_packages(),
    python_requires=">=3.9",
    install_requires=install_requires,
    
    # Entry points for CLI commands
    entry_points={
        "console_scripts": [
            "batch-processing-cdk=app:main",
        ],
    },
    
    # Package classification
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration", 
        "Topic :: System :: Distributed Computing",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Operating System :: OS Independent",
        "Framework :: AWS CDK",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "batch",
        "cdk",
        "cdk-v2",
        "infrastructure",
        "containers",
        "processing", 
        "scale",
        "compute",
        "spot-instances",
        "ecr",
        "cloudwatch"
    ],
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Source": "https://github.com/aws/aws-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "AWS Batch": "https://docs.aws.amazon.com/batch/",
    },
    
    # Include package data
    include_package_data=True,
    zip_safe=False,
    
    # Additional metadata
    platforms=["any"],
    license="MIT",
    
    # Optional dependencies for development
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.0.0", 
            "mypy>=1.8.0",
            "black>=24.0.0",
            "pylint>=3.0.0",
            "pre-commit>=3.6.0",
            "bandit>=1.7.5"
        ],
        "test": [
            "moto[batch,ec2,ecr,iam,logs]>=4.2.0",
            "pytest>=7.4.0",
            "pytest-cov>=4.0.0"
        ],
        "docs": [
            "sphinx>=7.1.0",
            "sphinx-rtd-theme>=2.0.0", 
            "sphinx-autodoc-typehints>=1.25.0"
        ]
    }
)