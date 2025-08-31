#!/usr/bin/env python3
"""
Setup configuration for the Timezone Converter CDK Python application.

This setup.py file configures the Python package for the AWS CDK application
that creates a serverless timezone converter API using Lambda and API Gateway.
It defines package metadata, dependencies, and installation requirements.
"""

import setuptools

# Read long description from README if it exists
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "Simple timezone converter with AWS Lambda and API Gateway using CDK Python"

# Read requirements from requirements.txt
def parse_requirements(filename: str) -> list:
    """Parse requirements from requirements.txt file."""
    try:
        with open(filename, 'r', encoding='utf-8') as f:
            lines = f.readlines()
        
        requirements = []
        for line in lines:
            line = line.strip()
            # Skip empty lines and comments
            if line and not line.startswith('#'):
                requirements.append(line)
        return requirements
    except FileNotFoundError:
        # Fallback to minimal requirements if file doesn't exist
        return [
            "aws-cdk-lib>=2.167.0,<3.0.0",
            "constructs>=10.0.0,<11.0.0",
        ]

setuptools.setup(
    name="timezone-converter-cdk",
    version="1.0.0",
    author="AWS CDK Python Generator",
    author_email="admin@example.com",
    description="Simple timezone converter with AWS Lambda and API Gateway",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/aws-cdk-examples",
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/aws-cdk-examples/issues",
        "Source": "https://github.com/aws-samples/aws-cdk-examples",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
    },
    packages=setuptools.find_packages(),
    install_requires=parse_requirements("requirements.txt"),
    python_requires=">=3.8",
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: Internet :: WWW/HTTP :: HTTP Servers",
        "Topic :: System :: Systems Administration",
    ],
    keywords="aws cdk lambda apigateway timezone serverless python",
    entry_points={
        "console_scripts": [
            "cdk-timezone-converter=app:main",
        ],
    },
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "types-boto3>=1.0.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
    },
    zip_safe=False,
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
)