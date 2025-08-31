"""
AWS CDK Python Package Setup for Traffic Analytics Solution

This setup.py file configures the Python package for the VPC Lattice and OpenSearch
traffic analytics CDK application. It defines the package metadata, dependencies,
and installation requirements.

Author: AWS CDK Python Generator
Version: 1.0
"""

import setuptools

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setuptools.setup(
    name="traffic-analytics-vpc-lattice-opensearch",
    version="1.0.0",
    author="AWS Solutions Team",
    author_email="aws-solutions@amazon.com",
    description="CDK Python application for traffic analytics with VPC Lattice and OpenSearch",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/aws-cdk-examples",
    project_urls={
        "Bug Tracker": "https://github.com/aws-samples/aws-cdk-examples/issues",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws-samples/aws-cdk-examples",
    },
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9", 
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Code Generators",
        "Topic :: Utilities",
        "Typing :: Typed",
    ],
    package_dir={"": "."},
    packages=setuptools.find_packages(where="."),
    python_requires=">=3.8",
    install_requires=[
        "aws-cdk-lib>=2.130.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.34.0",
        "botocore>=1.34.0",
    ],
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.0.0",
            "flake8>=6.0.0", 
            "mypy>=1.5.0",
            "types-setuptools>=68.0.0",
        ],
        "testing": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "moto>=4.2.0",  # For mocking AWS services in tests
        ],
    },
    entry_points={
        "console_scripts": [
            "traffic-analytics=app:main",
        ],
    },
    keywords=[
        "aws",
        "cdk", 
        "cloud-development-kit",
        "infrastructure-as-code",
        "vpc-lattice",
        "opensearch",
        "traffic-analytics",
        "service-mesh",
        "observability",
        "streaming-data",
        "kinesis",
        "lambda",
        "microservices"
    ],
    zip_safe=False,
    include_package_data=True,
)