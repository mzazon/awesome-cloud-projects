"""
Setup configuration for the Hybrid Cloud Storage CDK Python application.

This package deploys AWS Storage Gateway infrastructure for hybrid cloud storage
solutions, enabling seamless integration between on-premises environments and
AWS cloud storage services.
"""

from setuptools import setup, find_packages

# Read long description from README if available
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = """
    AWS CDK Python application for deploying hybrid cloud storage solutions
    using AWS Storage Gateway, S3, and supporting infrastructure.
    """

setup(
    name="hybrid-cloud-storage-cdk",
    version="1.0.0",
    author="AWS Recipes",
    author_email="aws-recipes@example.com",
    description="CDK Python app for AWS Storage Gateway hybrid cloud storage",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-recipes/hybrid-cloud-storage",
    packages=find_packages(exclude=["tests*"]),
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
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP :: HTTP Servers",
        "Topic :: System :: Archiving :: Backup",
    ],
    python_requires=">=3.8",
    install_requires=[
        "aws-cdk-lib>=2.170.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
    ],
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "boto3>=1.35.0",
            "moto>=4.0.0",
            "black>=22.0.0",
            "flake8>=4.0.0",
            "mypy>=0.991",
            "types-boto3>=1.0.0",
        ],
        "testing": [
            "pytest>=7.0.0",
            "moto>=4.0.0",
            "boto3>=1.35.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "deploy-storage-gateway=app:main",
        ],
    },
    keywords=[
        "aws",
        "cdk",
        "storage-gateway",
        "hybrid-cloud",
        "s3",
        "infrastructure",
        "infrastructure-as-code",
        "cloud",
        "storage",
        "file-gateway",
    ],
    project_urls={
        "Bug Reports": "https://github.com/aws-recipes/hybrid-cloud-storage/issues",
        "Source": "https://github.com/aws-recipes/hybrid-cloud-storage",
        "Documentation": "https://docs.aws.amazon.com/storagegateway/",
    },
)