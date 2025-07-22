"""
Setup script for Lake Formation Cross-Account Data Access CDK Python application.

This setup.py file configures the Python package for the CDK application that
implements secure cross-account data sharing using AWS Lake Formation.
"""

import setuptools

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setuptools.setup(
    name="lake-formation-cross-account-cdk",
    version="1.0.0",
    author="AWS CDK Generator",
    author_email="example@example.com",
    description="CDK Python application for Lake Formation cross-account data access",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/example/lake-formation-cross-account",
    packages=setuptools.find_packages(),
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Utilities",
    ],
    python_requires=">=3.9",
    install_requires=[
        "aws-cdk-lib==2.174.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.34.0",
        "botocore>=1.34.0",
        "pyyaml>=6.0.0",
        "python-dotenv>=1.0.0",
    ],
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "types-boto3>=1.0.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "lake-formation-cdk=app:main",
        ],
    },
    keywords=[
        "aws",
        "cdk",
        "lake-formation",
        "cross-account",
        "data-governance",
        "data-lake",
        "security",
        "infrastructure-as-code",
    ],
    project_urls={
        "Bug Reports": "https://github.com/example/lake-formation-cross-account/issues",
        "Source": "https://github.com/example/lake-formation-cross-account",
        "Documentation": "https://docs.aws.amazon.com/lake-formation/",
    },
)