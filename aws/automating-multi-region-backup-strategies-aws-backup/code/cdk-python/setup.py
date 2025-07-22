"""
Setup configuration for AWS CDK Python application.

This setup.py file defines the package configuration for the multi-region
backup strategies CDK application, including dependencies and metadata.
"""

from setuptools import setup, find_packages

# Read requirements from requirements.txt
with open("requirements.txt", "r", encoding="utf-8") as fh:
    requirements = [line.strip() for line in fh if line.strip() and not line.startswith("#")]

# Read README content for long description
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "AWS CDK Python application for automating multi-region backup strategies using AWS Backup"

setup(
    name="multi-region-backup-cdk",
    version="1.0.0",
    
    # Package metadata
    description="AWS CDK Python application for automating multi-region backup strategies using AWS Backup",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS Solutions Team",
    author_email="solutions@amazon.com",
    url="https://github.com/aws-solutions/multi-region-backup-strategies",
    
    # License and classifiers
    license="Apache-2.0",
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
        "Topic :: System :: Archiving :: Backup",
        "Topic :: System :: Systems Administration",
        "Topic :: Software Development :: Libraries :: Python Modules",
    ],
    
    # Python version requirements
    python_requires=">=3.8",
    
    # Package discovery
    packages=find_packages(exclude=["tests*"]),
    include_package_data=True,
    
    # Dependencies
    install_requires=[
        "aws-cdk-lib>=2.162.1,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "typing-extensions>=4.0.0",
        "boto3>=1.34.0",
        "botocore>=1.34.0",
    ],
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "python-dotenv>=1.0.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",  # For mocking AWS services in tests
        ],
    },
    
    # Entry points for CLI commands
    entry_points={
        "console_scripts": [
            "deploy-backup=app:MultiRegionBackupApp",
        ],
    },
    
    # Package data and manifest
    zip_safe=False,
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "backup",
        "multi-region",
        "disaster-recovery",
        "infrastructure-as-code",
        "cloud",
        "eventbridge",
        "lambda",
        "sns",
    ],
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws-solutions/multi-region-backup-strategies",
        "Bug Reports": "https://github.com/aws-solutions/multi-region-backup-strategies/issues",
        "AWS Backup Guide": "https://docs.aws.amazon.com/aws-backup/latest/devguide/",
        "CDK Python Documentation": "https://docs.aws.amazon.com/cdk/v2/guide/work-with-cdk-python.html",
    },
)