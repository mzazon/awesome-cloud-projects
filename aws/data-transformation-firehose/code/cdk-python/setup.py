"""
Setup configuration for Real-Time Data Transformation with Kinesis Firehose CDK Python package.

This setup.py file defines the package configuration for the CDK Python application
that deploys a complete streaming data processing pipeline using Amazon Kinesis Data Firehose.
"""

from setuptools import setup, find_packages

# Read the contents of README file
from pathlib import Path
this_directory = Path(__file__).parent
long_description = (this_directory / "README.md").read_text() if (this_directory / "README.md").exists() else ""

# Package metadata
PACKAGE_NAME = "real-time-data-transformation-firehose"
VERSION = "1.0.0"
DESCRIPTION = "CDK Python application for Real-Time Data Transformation with Kinesis Data Firehose"
AUTHOR = "AWS Solutions Architecture Team"
AUTHOR_EMAIL = "solutions-architecture@amazon.com"
URL = "https://github.com/aws-samples/real-time-data-transformation-firehose"

# Package requirements
INSTALL_REQUIRES = [
    "aws-cdk-lib>=2.100.0,<3.0.0",
    "constructs>=10.0.0,<11.0.0",
]

# Development requirements
DEV_REQUIRES = [
    "pytest>=7.0.0",
    "pytest-cov>=4.0.0",
    "black>=23.0.0",
    "flake8>=5.0.0",
    "mypy>=1.0.0",
    "sphinx>=5.0.0",
    "sphinx-rtd-theme>=1.0.0",
    "types-requests>=2.28.0",
    "boto3-stubs[essential]>=1.26.0",
]

# Classifiers for PyPI
CLASSIFIERS = [
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
    "Topic :: Software Development :: Libraries :: Python Modules",
    "Topic :: System :: Systems Administration",
    "Topic :: Utilities",
]

# Keywords for PyPI
KEYWORDS = [
    "aws",
    "cdk",
    "kinesis",
    "firehose",
    "lambda",
    "s3",
    "cloudwatch",
    "sns",
    "data-processing",
    "streaming",
    "real-time",
    "analytics",
    "serverless",
    "infrastructure-as-code",
]

setup(
    name=PACKAGE_NAME,
    version=VERSION,
    description=DESCRIPTION,
    long_description=long_description,
    long_description_content_type="text/markdown",
    author=AUTHOR,
    author_email=AUTHOR_EMAIL,
    url=URL,
    packages=find_packages(exclude=["tests", "tests.*"]),
    include_package_data=True,
    python_requires=">=3.8",
    install_requires=INSTALL_REQUIRES,
    extras_require={
        "dev": DEV_REQUIRES,
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
    },
    classifiers=CLASSIFIERS,
    keywords=" ".join(KEYWORDS),
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws-samples/real-time-data-transformation-firehose",
        "Tracker": "https://github.com/aws-samples/real-time-data-transformation-firehose/issues",
    },
    entry_points={
        "console_scripts": [
            "deploy-firehose-pipeline=app:main",
        ],
    },
    zip_safe=False,
)