"""
Setup configuration for AWS CLI Tutorial CDK Python Application

This setup.py file configures the Python package for the AWS CLI Setup and 
First Commands recipe CDK application. It defines package metadata, dependencies,
and entry points for the CDK application.
"""

import setuptools
from pathlib import Path

# Read the README file for long description
readme_path = Path(__file__).parent / "README.md"
long_description = readme_path.read_text(encoding="utf-8") if readme_path.exists() else ""

# Read requirements from requirements.txt
requirements_path = Path(__file__).parent / "requirements.txt"
if requirements_path.exists():
    with open(requirements_path, "r", encoding="utf-8") as f:
        requirements = [
            line.strip()
            for line in f
            if line.strip() and not line.startswith("#")
        ]
else:
    # Fallback requirements if file doesn't exist
    requirements = [
        "aws-cdk-lib>=2.172.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
    ]

setuptools.setup(
    name="aws-cli-tutorial-cdk",
    version="1.0.0",
    
    description="CDK Python application for AWS CLI Setup and First Commands tutorial",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS Recipes",
    author_email="recipes@example.com",
    
    url="https://github.com/aws-samples/recipes",
    project_urls={
        "Bug Tracker": "https://github.com/aws-samples/recipes/issues",
        "Documentation": "https://github.com/aws-samples/recipes",
        "Source Code": "https://github.com/aws-samples/recipes",
    },
    
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: Education",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Education",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Framework :: AWS CDK",
        "Framework :: AWS CDK :: 2",
    ],
    
    packages=setuptools.find_packages(exclude=["tests", "tests.*"]),
    
    python_requires=">=3.8",
    
    install_requires=requirements,
    
    extras_require={
        "dev": [
            "pytest>=7.0.0,<8.0.0",
            "pytest-cov>=4.0.0,<5.0.0",
            "black>=23.0.0,<24.0.0",
            "flake8>=5.0.0,<7.0.0",
            "mypy>=1.0.0,<2.0.0",
            "types-setuptools>=68.0.0",
            "boto3-stubs[s3,iam,sts]>=1.26.0",
        ],
        "docs": [
            "sphinx>=5.0.0,<8.0.0",
            "sphinx-rtd-theme>=1.0.0,<2.0.0",
        ],
    },
    
    entry_points={
        "console_scripts": [
            "aws-cli-tutorial-cdk=app:main",
        ],
    },
    
    # Package data and manifest
    include_package_data=True,
    zip_safe=False,
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "infrastructure",
        "cloud",
        "s3",
        "cli",
        "tutorial",
        "education",
        "iac",
        "cloudformation",
    ],
    
    # Minimum CDK version compatibility
    metadata={
        "cdk_version": "2.172.0",
        "aws_cdk_lib_version": "2.172.0",
        "constructs_version": "10.0.0",
    },
)