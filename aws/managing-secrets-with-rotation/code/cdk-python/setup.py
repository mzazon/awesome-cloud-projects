#!/usr/bin/env python3
"""
Setup configuration for AWS Secrets Manager CDK application
"""

import setuptools

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setuptools.setup(
    name="secrets-manager-cdk",
    version="1.0.0",
    author="AWS Recipe Generator",
    author_email="example@example.com",
    description="AWS CDK application for Secrets Manager recipe implementation",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/example/secrets-manager-cdk",
    packages=setuptools.find_packages(),
    
    classifiers=[
        "Development Status :: 4 - Beta",
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
        "Topic :: Security",
    ],
    
    python_requires=">=3.8",
    
    install_requires=[
        "aws-cdk-lib>=2.100.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.26.0",
        "botocore>=1.29.0",
        "typing-extensions>=4.0.0",
    ],
    
    extras_require={
        "dev": [
            "black>=23.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
        ],
    },
    
    entry_points={
        "console_scripts": [
            "secrets-manager-cdk=app:main",
        ],
    },
    
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/example/secrets-manager-cdk",
        "Tracker": "https://github.com/example/secrets-manager-cdk/issues",
    },
)