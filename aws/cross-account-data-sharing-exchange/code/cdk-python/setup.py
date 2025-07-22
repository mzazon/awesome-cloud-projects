"""
Setup configuration for AWS CDK Python Data Exchange application.

This setup.py file configures the Python package for the cross-account
data sharing solution using AWS Data Exchange, S3, IAM, and Lambda.
"""

import setuptools

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setuptools.setup(
    name="cross-account-data-sharing-data-exchange",
    version="1.0.0",
    author="AWS Solutions",
    author_email="aws-solutions@amazon.com",
    description="CDK Python application for Cross-Account Data Sharing with Data Exchange",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/cross-account-data-sharing-data-exchange",
    project_urls={
        "Bug Tracker": "https://github.com/aws-samples/cross-account-data-sharing-data-exchange/issues",
        "Documentation": "https://docs.aws.amazon.com/data-exchange/",
        "Source Code": "https://github.com/aws-samples/cross-account-data-sharing-data-exchange",
    },
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
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: System :: Systems Administration",
        "Typing :: Typed",
    ],
    packages=setuptools.find_packages(exclude=["tests*"]),
    python_requires=">=3.8",
    install_requires=[
        "aws-cdk-lib>=2.110.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.26.0",
    ],
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "boto3-stubs[dataexchange,s3,iam,lambda,events,logs,cloudwatch]>=1.26.0",
            "types-setuptools>=65.0.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.2.0",
            "myst-parser>=0.18.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "deploy-data-exchange=app:main",
        ],
    },
    include_package_data=True,
    zip_safe=False,
    keywords=[
        "aws",
        "cdk",
        "data-exchange",
        "cross-account",
        "data-sharing",
        "s3",
        "lambda",
        "iam",
        "analytics",
        "infrastructure-as-code",
    ],
)