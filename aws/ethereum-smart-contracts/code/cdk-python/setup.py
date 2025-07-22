"""
Setup configuration for Ethereum Smart Contracts CDK Application.

This setup.py file configures the Python package for the CDK application
that creates infrastructure for Ethereum smart contracts using AWS Managed Blockchain.
"""

from setuptools import setup, find_packages

# Read the contents of README file
def read_readme():
    try:
        with open("README.md", "r", encoding="utf-8") as fh:
            return fh.read()
    except FileNotFoundError:
        return "CDK application for Ethereum Smart Contracts with AWS Managed Blockchain"

# Read requirements from requirements.txt
def read_requirements():
    try:
        with open("requirements.txt", "r", encoding="utf-8") as fh:
            return [line.strip() for line in fh if line.strip() and not line.startswith("#")]
    except FileNotFoundError:
        return [
            "aws-cdk-lib==2.166.0",
            "constructs>=10.0.0,<11.0.0",
            "typing-extensions>=4.0.0",
        ]

setup(
    name="ethereum-smart-contracts-cdk",
    version="1.0.0",
    description="CDK application for Ethereum Smart Contracts with AWS Managed Blockchain",
    long_description=read_readme(),
    long_description_content_type="text/markdown",
    
    # Author information
    author="AWS CDK Team",
    author_email="aws-cdk-team@amazon.com",
    
    # Project URLs
    url="https://github.com/aws/aws-cdk",
    project_urls={
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Source": "https://github.com/aws/aws-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
    },
    
    # Package configuration
    packages=find_packages(exclude=["tests", "tests.*"]),
    include_package_data=True,
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=read_requirements(),
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "pre-commit>=3.0.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",
            "boto3>=1.26.0",
            "requests>=2.28.0",
        ],
    },
    
    # Package classification
    classifiers=[
        "Development Status :: 4 - Beta",
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
        "Topic :: System :: Distributed Computing",
        "Topic :: Office/Business :: Financial",
        "Topic :: Security :: Cryptography",
        "Typing :: Typed",
    ],
    
    # Keywords for PyPI
    keywords="aws cdk ethereum blockchain smart-contracts infrastructure-as-code",
    
    # License
    license="Apache-2.0",
    
    # Entry points for CLI tools
    entry_points={
        "console_scripts": [
            "ethereum-cdk=app:main",
        ],
    },
    
    # Additional metadata
    zip_safe=False,
    platforms=["any"],
    
    # Data files to include
    package_data={
        "": [
            "*.md",
            "*.txt",
            "*.json",
            "*.yaml",
            "*.yml",
        ],
    },
)