"""
Setup configuration for VMware Cloud Migration CDK Python application.

This setup.py file configures the Python package for the VMware Cloud Migration
CDK application, including all dependencies and metadata.
"""

from setuptools import setup, find_packages

# Read the contents of README file
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "VMware Cloud Migration CDK Python Application"

setup(
    name="vmware-cloud-migration-cdk",
    version="1.0.0",
    author="Cloud Engineering Team",
    author_email="cloud-engineering@company.com",
    description="AWS CDK Python application for VMware Cloud Migration infrastructure",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/company/vmware-cloud-migration-cdk",
    packages=find_packages(),
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content"
    ],
    python_requires=">=3.8",
    install_requires=[
        "aws-cdk-lib>=2.100.0,<3.0.0",
        "constructs>=10.3.0,<11.0.0",
        "boto3>=1.28.0",
        "botocore>=1.31.0"
    ],
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.7.0",
            "flake8>=6.0.0",
            "mypy>=1.5.0",
            "types-boto3>=1.0.0"
        ],
        "docs": [
            "sphinx>=7.1.0",
            "sphinx-rtd-theme>=1.3.0"
        ]
    },
    entry_points={
        "console_scripts": [
            "vmware-migration-cdk=app:main",
        ],
    },
    keywords=[
        "aws",
        "cdk",
        "vmware",
        "migration",
        "cloud",
        "infrastructure",
        "infrastructure-as-code",
        "vmware-cloud-on-aws",
        "hcx",
        "hybrid-cloud"
    ],
    project_urls={
        "Bug Reports": "https://github.com/company/vmware-cloud-migration-cdk/issues",
        "Source": "https://github.com/company/vmware-cloud-migration-cdk",
        "Documentation": "https://docs.company.com/vmware-cloud-migration-cdk"
    },
    include_package_data=True,
    zip_safe=False,
)