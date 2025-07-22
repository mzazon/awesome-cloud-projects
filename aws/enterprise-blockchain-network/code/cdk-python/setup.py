"""
Setup configuration for Hyperledger Fabric CDK Python Application

This setup.py file configures the Python package for the CDK application
that deploys Hyperledger Fabric blockchain infrastructure on Amazon Managed Blockchain.
"""

import setuptools
from pathlib import Path

# Read the README file for the long description
this_directory = Path(__file__).parent
long_description = (this_directory / "README.md").read_text() if (this_directory / "README.md").exists() else ""

# Read requirements from requirements.txt
requirements_path = this_directory / "requirements.txt"
install_requires = []
if requirements_path.exists():
    with open(requirements_path, "r") as f:
        install_requires = [
            line.strip() for line in f
            if line.strip() and not line.startswith("#") and not line.startswith("-")
        ]

setuptools.setup(
    name="hyperledger-fabric-cdk",
    version="1.0.0",
    description="CDK Python application for Hyperledger Fabric on Amazon Managed Blockchain",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    # Author information
    author="AWS CDK Developer",
    author_email="developer@example.com",
    
    # Project URLs
    url="https://github.com/your-org/hyperledger-fabric-cdk",
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/managed-blockchain/",
        "Source": "https://github.com/your-org/hyperledger-fabric-cdk",
        "Bug Tracker": "https://github.com/your-org/hyperledger-fabric-cdk/issues",
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
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
        "Topic :: Office/Business :: Financial",
        "Topic :: Security :: Cryptography",
    ],
    
    # Package discovery
    packages=setuptools.find_packages(exclude=["tests", "tests.*"]),
    
    # Python version requirements
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=install_requires,
    
    # Optional dependencies for development
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "mypy>=1.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
            "safety>=2.0.0",
            "bandit>=1.7.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
            "sphinxcontrib-mermaid>=0.7.0",
        ],
    },
    
    # Entry points for command-line interfaces
    entry_points={
        "console_scripts": [
            "hyperledger-fabric-deploy=app:main",
        ],
    },
    
    # Include additional files
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # Licensing
    license="Apache-2.0",
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "blockchain",
        "hyperledger-fabric",
        "managed-blockchain",
        "infrastructure-as-code",
        "cloud-development-kit",
        "amazon-web-services",
        "distributed-ledger",
        "smart-contracts",
        "chaincode",
    ],
    
    # Zip safe configuration
    zip_safe=False,
    
    # Platform support
    platforms=["any"],
    
    # Additional metadata
    maintainer="AWS CDK Developer",
    maintainer_email="developer@example.com",
)