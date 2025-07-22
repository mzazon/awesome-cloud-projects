"""
Setup configuration for Multi-Region VPC Connectivity with Transit Gateway CDK application.

This setup.py file defines the package configuration and dependencies
for the CDK Python application that creates multi-region VPC connectivity
using AWS Transit Gateway.
"""

from setuptools import setup, find_packages

# Read the README file for the long description
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "Multi-Region VPC Connectivity with AWS Transit Gateway CDK Application"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file."""
    try:
        with open("requirements.txt", "r", encoding="utf-8") as f:
            requirements = []
            for line in f:
                line = line.strip()
                # Skip comments and empty lines
                if line and not line.startswith("#"):
                    requirements.append(line)
            return requirements
    except FileNotFoundError:
        return [
            "aws-cdk-lib>=2.120.0,<3.0.0",
            "constructs>=10.3.0,<11.0.0"
        ]

setup(
    name="multi-region-vpc-connectivity-transit-gateway",
    version="1.0.0",
    author="AWS Cloud Recipes",
    author_email="recipes@example.com",
    description="CDK Python application for multi-region VPC connectivity using Transit Gateway",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/cloud-recipes",
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/cloud-recipes/issues",
        "Source": "https://github.com/aws-samples/cloud-recipes",
        "Documentation": "https://github.com/aws-samples/cloud-recipes/blob/main/README.md"
    },
    packages=find_packages(exclude=["tests", "tests.*"]),
    classifiers=[
        "Development Status :: 4 - Beta",
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
        "Topic :: System :: Networking",
        "Topic :: System :: Systems Administration",
        "Typing :: Typed"
    ],
    python_requires=">=3.8",
    install_requires=read_requirements(),
    extras_require={
        "dev": [
            "pytest>=7.4.0,<8.0.0",
            "pytest-cov>=4.1.0,<5.0.0",
            "black>=23.7.0,<24.0.0",
            "flake8>=6.0.0,<7.0.0",
            "mypy>=1.5.0,<2.0.0",
            "safety>=2.3.0,<3.0.0",
            "bandit>=1.7.0,<2.0.0"
        ],
        "docs": [
            "sphinx>=7.1.0,<8.0.0",
            "sphinx-rtd-theme>=1.3.0,<2.0.0"
        ],
        "type-checking": [
            "boto3-stubs[ec2,cloudwatch]>=1.34.0,<2.0.0"
        ]
    },
    entry_points={
        "console_scripts": [
            "deploy-multi-region-tgw=app:main"
        ]
    },
    keywords=[
        "aws", "cdk", "transit-gateway", "vpc", "networking", 
        "multi-region", "infrastructure", "cloud", "python"
    ],
    zip_safe=False,
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"]
    }
)