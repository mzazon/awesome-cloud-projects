"""
Setup configuration for QLDB Financial Ledger CDK Application

This setup.py file configures the Python package for the CDK application
that deploys an ACID-compliant distributed database using Amazon QLDB.
"""

from setuptools import setup, find_packages

# Read the README file for long description
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "CDK application for deploying ACID-compliant distributed databases with Amazon QLDB"

# Read requirements from requirements.txt
try:
    with open("requirements.txt", "r", encoding="utf-8") as fh:
        requirements = [line.strip() for line in fh if line.strip() and not line.startswith("#")]
except FileNotFoundError:
    requirements = [
        "aws-cdk-lib>=2.156.0,<3.0.0",
        "constructs>=10.3.0,<11.0.0",
        "typing-extensions>=4.8.0",
    ]

setup(
    name="qldb-financial-ledger-cdk",
    version="1.0.0",
    author="AWS CDK Generator",
    author_email="aws-cdk-generator@example.com",
    description="CDK application for building ACID-compliant distributed databases with Amazon QLDB",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/qldb-financial-ledger",
    packages=find_packages(),
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: Financial and Insurance Industry",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: Database :: Database Engines/Servers",
        "Topic :: Office/Business :: Financial",
        "Topic :: Security :: Cryptography",
        "Topic :: System :: Distributed Computing",
    ],
    python_requires=">=3.8",
    install_requires=requirements,
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.9.0",
            "flake8>=6.1.0",
            "mypy>=1.6.0",
        ],
        "docs": [
            "sphinx>=7.2.0",
            "sphinx-rtd-theme>=1.3.0",
        ],
        "qldb": [
            "amazon-ion>=0.9.0",
            "pyqldb>=3.2.0",
            "boto3>=1.35.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "qldb-ledger-deploy=app:main",
        ],
    },
    include_package_data=True,
    zip_safe=False,
    keywords=[
        "aws",
        "cdk",
        "qldb",
        "ledger",
        "database",
        "acid",
        "cryptographic",
        "financial",
        "compliance",
        "audit",
        "blockchain",
        "immutable",
        "distributed",
    ],
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/qldb-financial-ledger/issues",
        "Source": "https://github.com/aws-samples/qldb-financial-ledger",
        "Documentation": "https://docs.aws.amazon.com/qldb/",
        "AWS CDK": "https://aws.amazon.com/cdk/",
        "Amazon QLDB": "https://aws.amazon.com/qldb/",
    },
)