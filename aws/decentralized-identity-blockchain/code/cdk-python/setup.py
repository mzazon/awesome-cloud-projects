"""
Setup configuration for Decentralized Identity Management CDK Python Application

This setup.py file configures the Python package for the CDK application that
deploys infrastructure for decentralized identity management using blockchain
technology on AWS.
"""

import os
from setuptools import setup, find_packages

# Read the README file for long description
def read_readme():
    """Read README.md file for package description."""
    readme_path = os.path.join(os.path.dirname(__file__), "README.md")
    if os.path.exists(readme_path):
        with open(readme_path, "r", encoding="utf-8") as fh:
            return fh.read()
    return "CDK Python application for Decentralized Identity Management with Blockchain"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements.txt file for package dependencies."""
    requirements_path = os.path.join(os.path.dirname(__file__), "requirements.txt")
    requirements = []
    if os.path.exists(requirements_path):
        with open(requirements_path, "r", encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                # Skip comments and empty lines
                if line and not line.startswith("#"):
                    requirements.append(line)
    return requirements

setup(
    name="decentralized-identity-management-cdk",
    version="1.0.0",
    description="CDK Python application for Decentralized Identity Management with Blockchain",
    long_description=read_readme(),
    long_description_content_type="text/markdown",
    author="AWS Solutions Architect",
    author_email="solutions@example.com",
    url="https://github.com/aws-samples/decentralized-identity-management",
    
    # Package configuration
    packages=find_packages(exclude=["tests", "tests.*"]),
    package_dir={"": "."},
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=read_requirements(),
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.9.0",
            "flake8>=6.1.0",
            "mypy>=1.6.0",
            "bandit>=1.7.5",
            "safety>=2.3.5",
        ],
        "docs": [
            "sphinx>=7.2.0",
            "sphinx-rtd-theme>=1.3.0",
        ],
    },
    
    # Entry points for command-line scripts
    entry_points={
        "console_scripts": [
            "deploy-identity-infrastructure=app:main",
        ],
    },
    
    # Package metadata
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP :: WSGI :: Application",
        "Topic :: Security :: Cryptography",
        "Topic :: Office/Business :: Financial",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "blockchain",
        "identity",
        "decentralized",
        "hyperledger",
        "fabric",
        "qldb",
        "lambda",
        "apigateway",
        "dynamodb",
        "security",
        "cryptography",
        "did",
        "verifiable-credentials",
    ],
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws-samples/decentralized-identity-management",
        "Bug Reports": "https://github.com/aws-samples/decentralized-identity-management/issues",
        "AWS CDK": "https://aws.amazon.com/cdk/",
        "AWS Managed Blockchain": "https://aws.amazon.com/managed-blockchain/",
        "Amazon QLDB": "https://aws.amazon.com/qldb/",
    },
    
    # Include additional files in the package
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.yaml", "*.yml", "*.json"],
    },
    
    # Zip safety
    zip_safe=False,
    
    # License
    license="MIT",
    
    # Platform compatibility
    platforms=["any"],
    
    # Maintainer information
    maintainer="AWS Solutions Team",
    maintainer_email="aws-solutions@amazon.com",
    
    # Download URL (if hosting releases)
    download_url="https://github.com/aws-samples/decentralized-identity-management/archive/v1.0.0.tar.gz",
)