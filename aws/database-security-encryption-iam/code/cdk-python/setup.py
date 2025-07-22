"""
Setup configuration for Database Security CDK Python application.

This package provides Infrastructure as Code (IaC) for implementing
database security with encryption and IAM authentication using AWS CDK.
"""

from setuptools import setup, find_packages

# Read long description from README
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "Database Security with Encryption and IAM Authentication CDK Application"

# Read requirements from requirements.txt
try:
    with open("requirements.txt", "r", encoding="utf-8") as fh:
        requirements = [line.strip() for line in fh if line.strip() and not line.startswith("#")]
except FileNotFoundError:
    requirements = [
        "aws-cdk-lib>=2.167.1",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.34.0",
    ]

setup(
    name="database-security-cdk",
    version="1.0.0",
    description="AWS CDK application for implementing database security with encryption and IAM authentication",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS CDK Team",
    author_email="cdk-team@example.com",
    url="https://github.com/aws/aws-cdk",
    packages=find_packages(),
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Database",
        "Topic :: Security",
        "Topic :: Security :: Cryptography",
    ],
    python_requires=">=3.8",
    install_requires=requirements,
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "boto3-stubs[rds,ec2,kms,iam,logs,cloudwatch,secretsmanager]>=1.34.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto[rds,ec2,kms,iam,logs,cloudwatch,secretsmanager]>=4.0.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "database-security-cdk=app:main",
        ],
    },
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "database",
        "security",
        "encryption",
        "rds",
        "postgresql",
        "iam",
        "authentication",
        "kms",
        "cloudwatch",
        "monitoring",
    ],
    project_urls={
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Source": "https://github.com/aws/aws-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "AWS CDK": "https://aws.amazon.com/cdk/",
    },
    zip_safe=False,
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
)