"""
Setup configuration for Operational Analytics with Amazon Redshift Spectrum CDK application.

This setup.py file configures the Python package for the CDK application,
including dependencies, metadata, and development requirements.
"""

import setuptools
from setuptools import find_packages

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setuptools.setup(
    name="operational-analytics-redshift-spectrum",
    version="1.0.0",
    author="AWS Solutions Architecture",
    author_email="solutions-architecture@amazon.com",
    description="CDK application for operational analytics with Amazon Redshift Spectrum",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/operational-analytics-redshift-spectrum",
    project_urls={
        "Bug Tracker": "https://github.com/aws-samples/operational-analytics-redshift-spectrum/issues",
        "Documentation": "https://docs.aws.amazon.com/redshift/latest/dg/c-using-spectrum.html",
        "Source": "https://github.com/aws-samples/operational-analytics-redshift-spectrum",
    },
    classifiers=[
        "Development Status :: 5 - Production/Stable",
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
        "Topic :: Utilities",
    ],
    package_dir={"": "."},
    packages=find_packages(where="."),
    python_requires=">=3.8",
    install_requires=[
        "aws-cdk-lib>=2.100.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.26.0",
        "botocore>=1.29.0",
        "typing-extensions>=4.4.0",
    ],
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "moto>=4.0.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "deploy-analytics=app:main",
        ],
    },
    keywords=[
        "aws",
        "cdk",
        "redshift",
        "spectrum",
        "analytics",
        "data-lake",
        "glue",
        "s3",
        "operational-analytics",
        "infrastructure-as-code",
    ],
    zip_safe=False,
)