"""
Setup configuration for Amazon Managed Blockchain CDK Python application.

This setup.py file configures the Python package for the CDK application
that deploys private blockchain networks with Amazon Managed Blockchain.
"""

from setuptools import setup, find_packages
import os

# Read the README file for long description
readme_path = os.path.join(os.path.dirname(__file__), "README.md")
long_description = ""
if os.path.exists(readme_path):
    with open(readme_path, "r", encoding="utf-8") as fh:
        long_description = fh.read()

# Read requirements from requirements.txt
requirements_path = os.path.join(os.path.dirname(__file__), "requirements.txt")
install_requires = []
if os.path.exists(requirements_path):
    with open(requirements_path, "r", encoding="utf-8") as fh:
        install_requires = [
            line.strip() 
            for line in fh 
            if line.strip() and not line.startswith("#")
        ]

setup(
    name="managed-blockchain-cdk",
    version="1.0.0",
    description="AWS CDK Python application for Amazon Managed Blockchain private networks",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS Solutions",
    author_email="aws-solutions@amazon.com",
    url="https://github.com/aws-samples/managed-blockchain-cdk",
    license="MIT-0",
    
    # Package configuration
    packages=find_packages(exclude=["tests*"]),
    python_requires=">=3.8",
    install_requires=install_requires,
    
    # Entry points for CLI commands
    entry_points={
        "console_scripts": [
            "blockchain-deploy=app:main",
        ],
    },
    
    # Package classifiers
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP",
        "Topic :: Security :: Cryptography",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "blockchain",
        "hyperledger-fabric",
        "managed-blockchain",
        "distributed-ledger",
        "smart-contracts",
        "infrastructure-as-code",
        "cloudformation",
    ],
    
    # Additional metadata
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/managed-blockchain/",
        "Source": "https://github.com/aws-samples/managed-blockchain-cdk",
        "Bug Reports": "https://github.com/aws-samples/managed-blockchain-cdk/issues",
        "AWS CDK": "https://aws.amazon.com/cdk/",
        "AWS Managed Blockchain": "https://aws.amazon.com/managed-blockchain/",
    },
    
    # Include additional files in the package
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # Development dependencies (optional)
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "pre-commit>=3.0.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.2.0",
            "myst-parser>=1.0.0",
        ],
    },
    
    # Zip safe configuration
    zip_safe=False,
)