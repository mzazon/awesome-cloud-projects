"""
Setup configuration for High-Availability PostgreSQL Clusters CDK Application.

This setup.py file defines the package metadata and dependencies for the CDK
application that creates production-grade PostgreSQL clusters on AWS RDS.
"""

import setuptools


with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()


setuptools.setup(
    name="postgresql-ha-cdk",
    version="1.0.0",
    author="AWS Solutions Architect",
    author_email="admin@example.com",
    description="CDK application for High-Availability PostgreSQL clusters with Amazon RDS",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/postgresql-ha-cdk",
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
        "Topic :: Database",
        "Topic :: Internet :: WWW/HTTP",
        "Framework :: AWS CDK",
    ],
    package_dir={"": "."},
    packages=setuptools.find_packages(where="."),
    python_requires=">=3.8",
    install_requires=[
        "aws-cdk-lib==2.161.1",
        "constructs>=10.0.0,<11.0.0",
        "typing-extensions>=4.0.0",
        "boto3>=1.34.0",
        "botocore>=1.34.0",
    ],
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "postgresql-ha-cdk=app:main",
        ],
    },
    keywords=[
        "aws",
        "cdk",
        "postgresql",
        "rds",
        "high-availability",
        "database",
        "multi-az",
        "disaster-recovery",
        "infrastructure-as-code",
    ],
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/postgresql-ha-cdk/issues",
        "Source": "https://github.com/aws-samples/postgresql-ha-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "AWS RDS": "https://aws.amazon.com/rds/",
        "PostgreSQL": "https://www.postgresql.org/",
    },
)