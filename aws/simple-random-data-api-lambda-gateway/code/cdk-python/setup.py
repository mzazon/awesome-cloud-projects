"""
Setup configuration for Simple Random Data API CDK application.

This setup.py file configures the Python package for the CDK application
that creates a serverless REST API using AWS Lambda and API Gateway.
"""

import setuptools

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setuptools.setup(
    name="simple-random-data-api-cdk",
    version="1.0.0",
    author="AWS CDK Generator",
    author_email="cdk@example.com",
    description="CDK Python application for Simple Random Data API with Lambda and API Gateway",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws/aws-cdk",
    project_urls={
        "Bug Tracker": "https://github.com/aws/aws-cdk/issues",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
    },
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: JavaScript",
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
        "aws-cdk-lib==2.167.1",
        "constructs>=10.0.0,<11.0.0",
    ],
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "black>=22.0.0",
            "flake8>=4.0.0",
            "mypy>=1.0.0",
            "boto3>=1.35.0",
            "types-boto3>=1.0.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "cdk-synth=app:main",
        ],
    },
    keywords="aws cdk lambda api-gateway serverless python random-data",
    zip_safe=False,
)