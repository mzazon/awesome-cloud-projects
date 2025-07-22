#!/usr/bin/env python3
"""
Setup configuration for the Streaming ETL CDK Python application.

This setup.py file configures the Python package for the CDK application
that implements streaming ETL with Kinesis Data Firehose transformations.
"""

import setuptools
from pathlib import Path

# Read the README file for the long description
readme_path = Path(__file__).parent / "README.md"
long_description = readme_path.read_text(encoding="utf-8") if readme_path.exists() else ""

# Read requirements from requirements.txt
requirements_path = Path(__file__).parent / "requirements.txt"
if requirements_path.exists():
    with open(requirements_path, "r", encoding="utf-8") as f:
        requirements = [
            line.strip()
            for line in f
            if line.strip() and not line.startswith("#") and not line.startswith("-")
        ]
else:
    requirements = [
        "aws-cdk-lib>=2.113.0",
        "constructs>=10.0.0,<11.0.0",
    ]

setuptools.setup(
    # Package metadata
    name="streaming-etl-cdk",
    version="1.0.0",
    author="AWS CDK Developer",
    author_email="developer@example.com",
    description="CDK Python application for streaming ETL with Kinesis Data Firehose transformations",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/your-org/streaming-etl-cdk",
    
    # Package configuration
    packages=setuptools.find_packages(where=".", exclude=["tests*"]),
    package_dir={"": "."},
    
    # Python version requirements
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=requirements,
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=0.991",
            "boto3-stubs[essential]>=1.26.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
    },
    
    # Package classifiers
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: Software Development :: Code Generators",
        "Topic :: Utilities",
        "Topic :: System :: Systems Administration",
    ],
    
    # Entry points for CLI tools (if needed)
    entry_points={
        "console_scripts": [
            "streaming-etl-deploy=app:main",
        ],
    },
    
    # Include additional files
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/your-org/streaming-etl-cdk",
        "Tracker": "https://github.com/your-org/streaming-etl-cdk/issues",
        "CDK Documentation": "https://docs.aws.amazon.com/cdk/v2/guide/",
        "Kinesis Data Firehose": "https://docs.aws.amazon.com/firehose/",
        "AWS Lambda": "https://docs.aws.amazon.com/lambda/",
    },
    
    # License
    license="Apache-2.0",
    
    # Keywords for discoverability
    keywords=[
        "aws",
        "cdk",
        "kinesis",
        "firehose",
        "lambda",
        "s3",
        "streaming",
        "etl",
        "data-processing",
        "serverless",
        "analytics",
        "parquet",
        "cloudformation",
        "infrastructure-as-code",
    ],
    
    # Zip safety
    zip_safe=False,
    
    # Platform requirements
    platforms=["any"],
)