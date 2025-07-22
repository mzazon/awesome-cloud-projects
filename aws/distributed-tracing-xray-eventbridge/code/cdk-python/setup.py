"""
Setup configuration for the distributed tracing CDK Python application.

This setup.py file configures the Python package for the CDK application
and ensures all required dependencies are properly installed.
"""

from setuptools import setup, find_packages

# Read version from a file or set directly
VERSION = "1.0.0"

# Read the long description from README if it exists
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "CDK Python application for implementing Distributed Tracing with X-Ray"

setup(
    name="distributed-tracing-cdk",
    version=VERSION,
    description="AWS CDK Python application for Distributed Tracing with X-Ray",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS Recipe Generator",
    author_email="recipes@example.com",
    python_requires=">=3.8",
    packages=find_packages(),
    install_requires=[
        "aws-cdk-lib>=2.110.0,<3.0.0",
        "constructs>=10.3.0,<11.0.0",
        "aws-xray-sdk>=2.12.0",
        "boto3>=1.28.0"
    ],
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "black>=23.9.0",
            "flake8>=6.1.0",
            "mypy>=1.6.0",
            "boto3-stubs[essential]>=1.28.0"
        ]
    },
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: System :: Systems Administration",
        "Typing :: Typed"
    ],
    keywords="aws cdk python lambda eventbridge xray tracing microservices",
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/recipes/issues",
        "Source": "https://github.com/aws-samples/recipes",
        "Documentation": "https://docs.aws.amazon.com/cdk/"
    }
)