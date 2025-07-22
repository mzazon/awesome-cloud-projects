"""
Setup configuration for Lambda Deployment Patterns CDK Python application.

This setup file configures the Python package for the CDK application
demonstrating Lambda deployment patterns with blue-green and canary releases.
"""

from setuptools import setup, find_packages

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setup(
    name="lambda-deployment-patterns-cdk",
    version="1.0.0",
    author="AWS CDK Team",
    author_email="aws-cdk-team@amazon.com",
    description="CDK Python application for Lambda deployment patterns with blue-green and canary releases",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws/aws-cdk",
    packages=find_packages(),
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
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Typing :: Typed",
    ],
    python_requires=">=3.8",
    install_requires=[
        "aws-cdk-lib>=2.118.0",
        "constructs>=10.0.0,<11.0.0",
    ],
    extras_require={
        "dev": [
            "mypy>=1.7.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "pytest>=7.0.0",
            "boto3>=1.34.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "lambda-deployment-patterns-cdk=app:main",
        ],
    },
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
    },
    keywords=[
        "aws",
        "cdk",
        "lambda",
        "deployment",
        "blue-green",
        "canary",
        "serverless",
        "infrastructure-as-code",
    ],
    zip_safe=False,
    include_package_data=True,
)