"""
Setup configuration for the multi-architecture container build CDK application.

This setup.py file defines the package configuration and dependencies for the
CDK Python application that deploys multi-architecture container build infrastructure.
"""

from setuptools import setup, find_packages

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setup(
    name="multi-arch-container-cdk",
    version="1.0.0",
    author="AWS CDK Team",
    author_email="aws-cdk@amazon.com",
    description="CDK application for multi-architecture container builds with CodeBuild and ECR",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws/aws-cdk",
    packages=find_packages(),
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Topic :: Software Development :: Build Tools",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
    ],
    python_requires=">=3.8",
    install_requires=[
        "aws-cdk-lib>=2.161.1",
        "constructs>=10.0.0,<11.0.0",
    ],
    extras_require={
        "dev": [
            "mypy>=1.11.2",
            "pytest>=8.3.2",
            "pytest-cov>=5.0.0",
            "black>=24.8.0",
            "flake8>=7.1.1",
            "isort>=5.13.2",
            "boto3-stubs[essential]>=1.35.36",
        ],
    },
    entry_points={
        "console_scripts": [
            "multi-arch-container-cdk=app:main",
        ],
    },
    project_urls={
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Source": "https://github.com/aws/aws-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
    },
)