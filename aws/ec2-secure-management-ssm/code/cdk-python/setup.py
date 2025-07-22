#!/usr/bin/env python3
"""
Setup configuration for the Secure Systems Manager CDK Python application.

This setup.py file defines the package configuration and dependencies
for the CDK application that demonstrates secure EC2 instance management
using AWS Systems Manager.

Author: Recipe Generator v1.3
Last Updated: 2025-07-12
"""

import setuptools
from pathlib import Path

# Read the README file for long description
readme_path = Path(__file__).parent / "README.md"
long_description = readme_path.read_text(encoding="utf-8") if readme_path.exists() else ""

# Read requirements from requirements.txt
requirements_path = Path(__file__).parent / "requirements.txt"
if requirements_path.exists():
    with open(requirements_path, encoding="utf-8") as f:
        requirements = [
            line.strip() 
            for line in f 
            if line.strip() and not line.startswith("#")
        ]
else:
    requirements = [
        "aws-cdk-lib>=2.100.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.26.0",
        "botocore>=1.29.0",
    ]

setuptools.setup(
    name="secure-systems-manager-cdk",
    version="1.0.0",
    
    description="CDK Python application for secure EC2 instance management with AWS Systems Manager",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS Recipe Generator",
    author_email="recipes@example.com",
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: System :: Networking",
    ],
    
    install_requires=requirements,
    
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pylint>=2.15.0",
            "black>=22.0.0",
            "mypy>=1.0.0",
            "bandit>=1.7.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
    },
    
    entry_points={
        "console_scripts": [
            "deploy-secure-ssm=app:main",
        ],
    },
    
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    include_package_data=True,
    zip_safe=False,
    
    keywords=[
        "aws",
        "cdk",
        "systems-manager",
        "ec2",
        "security",
        "infrastructure",
        "cloud",
        "session-manager",
        "run-command",
    ],
    
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/systems-manager/",
        "Source": "https://github.com/aws-samples/aws-cdk-examples",
        "Bug Reports": "https://github.com/aws-samples/aws-cdk-examples/issues",
        "AWS CDK": "https://aws.amazon.com/cdk/",
        "AWS Systems Manager": "https://aws.amazon.com/systems-manager/",
    },
)