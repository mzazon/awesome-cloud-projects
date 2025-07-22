"""
Setup configuration for the Network Micro-Segmentation CDK Python application.

This setup.py file defines the package configuration, dependencies, and metadata
for the CDK application that implements network micro-segmentation with NACLs
and advanced security groups.
"""

from setuptools import setup, find_packages
import os

# Read the README file for the long description
def read_readme():
    """Read the README.md file for the long description."""
    readme_path = os.path.join(os.path.dirname(__file__), "README.md")
    if os.path.exists(readme_path):
        with open(readme_path, "r", encoding="utf-8") as f:
            return f.read()
    return "AWS CDK Python application for network micro-segmentation"

# Read requirements from requirements.txt
def read_requirements():
    """Read the requirements.txt file for dependencies."""
    requirements_path = os.path.join(os.path.dirname(__file__), "requirements.txt")
    if os.path.exists(requirements_path):
        with open(requirements_path, "r", encoding="utf-8") as f:
            return [
                line.strip() 
                for line in f.readlines() 
                if line.strip() and not line.startswith("#")
            ]
    return []

setup(
    name="network-micro-segmentation-cdk",
    version="1.0.0",
    description="AWS CDK Python application for network micro-segmentation with NACLs and advanced security groups",
    long_description=read_readme(),
    long_description_content_type="text/markdown",
    author="AWS Security Team",
    author_email="security@company.com",
    url="https://github.com/company/network-micro-segmentation-cdk",
    
    # Package discovery
    packages=find_packages(exclude=["tests", "tests.*"]),
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=read_requirements(),
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0,<8.0.0",
            "pytest-cov>=4.0.0,<5.0.0",
            "black>=22.0.0,<24.0.0",
            "flake8>=5.0.0,<7.0.0",
            "mypy>=1.0.0,<2.0.0",
            "pre-commit>=2.20.0,<4.0.0",
        ],
        "test": [
            "pytest>=7.0.0,<8.0.0",
            "pytest-cov>=4.0.0,<5.0.0",
            "moto>=4.0.0,<5.0.0",
            "boto3-stubs[ec2,logs,cloudwatch,iam]>=1.26.0,<2.0.0",
        ],
    },
    
    # Entry points for command-line scripts
    entry_points={
        "console_scripts": [
            "microseg-deploy=app:main",
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
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: System :: Networking",
        "Topic :: System :: Systems Administration",
        "Topic :: Security",
    ],
    
    # Keywords for PyPI search
    keywords=[
        "aws",
        "cdk",
        "network",
        "security",
        "micro-segmentation",
        "nacl",
        "security-groups",
        "vpc",
        "infrastructure",
        "cloud",
        "zero-trust",
    ],
    
    # Package data
    include_package_data=True,
    
    # Zip safety
    zip_safe=False,
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/company/network-micro-segmentation-cdk/issues",
        "Source": "https://github.com/company/network-micro-segmentation-cdk",
        "Documentation": "https://docs.company.com/network-micro-segmentation-cdk",
    },
)