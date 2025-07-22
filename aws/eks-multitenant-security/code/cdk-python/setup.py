"""
Setup configuration for EKS Multi-Tenant Security CDK Python application.

This setup.py file configures the Python package for the CDK application,
including dependencies, metadata, and installation requirements.
"""

from setuptools import setup, find_packages
import os

# Read the README file for long description
def read_readme():
    """Read README.md file for long description."""
    readme_path = os.path.join(os.path.dirname(__file__), "README.md")
    if os.path.exists(readme_path):
        with open(readme_path, "r", encoding="utf-8") as f:
            return f.read()
    return "CDK Python application for EKS Multi-Tenant Security"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file."""
    requirements_path = os.path.join(os.path.dirname(__file__), "requirements.txt")
    requirements = []
    if os.path.exists(requirements_path):
        with open(requirements_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                # Skip empty lines and comments
                if line and not line.startswith("#"):
                    requirements.append(line)
    return requirements

setup(
    name="eks-multi-tenant-security",
    version="1.0.0",
    description="CDK Python application for EKS Multi-Tenant Cluster Security with Namespace Isolation",
    long_description=read_readme(),
    long_description_content_type="text/markdown",
    author="AWS CDK Team",
    author_email="aws-cdk-team@amazon.com",
    url="https://github.com/aws/aws-cdk",
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "Tracker": "https://github.com/aws/aws-cdk/issues",
    },
    license="Apache-2.0",
    packages=find_packages(exclude=["tests", "tests.*"]),
    include_package_data=True,
    zip_safe=False,
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
        "Topic :: Internet :: WWW/HTTP",
        "Topic :: Security",
        "Typing :: Typed",
    ],
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "eks",
        "kubernetes",
        "multi-tenant",
        "security",
        "namespace",
        "isolation",
        "rbac",
        "iam",
        "network-policies",
        "resource-quotas",
    ],
    python_requires=">=3.8",
    install_requires=read_requirements(),
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "isort>=5.0.0",
            "mypy>=1.0.0",
            "types-boto3>=1.0.0",
            "safety>=2.0.0",
            "bandit>=1.7.0",
        ],
        "docs": [
            "Sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
        "testing": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",
            "boto3-stubs>=1.26.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "eks-multi-tenant-security=app:main",
        ],
    },
    package_data={
        "": [
            "*.json",
            "*.yaml",
            "*.yml",
            "*.md",
            "*.txt",
            "*.cfg",
            "*.ini",
        ],
    },
    data_files=[
        ("", ["requirements.txt"]),
    ],
    platforms=["any"],
    maintainer="AWS CDK Team",
    maintainer_email="aws-cdk-team@amazon.com",
    options={
        "build_scripts": {
            "executable": "/usr/bin/env python3",
        },
    },
    # CDK-specific configuration
    cdk_version="2.120.0",
    construct_version="10.3.0",
)

# Additional package configuration
__version__ = "1.0.0"
__author__ = "AWS CDK Team"
__email__ = "aws-cdk-team@amazon.com"
__license__ = "Apache-2.0"
__description__ = "CDK Python application for EKS Multi-Tenant Cluster Security"

# Package metadata for introspection
PACKAGE_INFO = {
    "name": "eks-multi-tenant-security",
    "version": __version__,
    "description": __description__,
    "author": __author__,
    "license": __license__,
    "python_requires": ">=3.8",
    "cdk_version": "2.120.0",
    "aws_services": [
        "eks",
        "ec2",
        "iam",
        "logs",
        "cloudformation",
    ],
    "kubernetes_features": [
        "namespaces",
        "rbac",
        "network-policies",
        "resource-quotas",
        "limit-ranges",
    ],
    "security_features": [
        "multi-tenancy",
        "namespace-isolation",
        "iam-rbac-integration",
        "network-segmentation",
        "resource-governance",
    ],
}