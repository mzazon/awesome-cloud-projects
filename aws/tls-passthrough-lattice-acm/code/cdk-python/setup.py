"""
Setup configuration for TLS Passthrough VPC Lattice CDK Application.

This setup script defines the package configuration for the CDK Python application
that implements end-to-end encryption using VPC Lattice TLS passthrough.
"""

from setuptools import setup, find_packages

# Read requirements from requirements.txt
with open("requirements.txt", "r", encoding="utf-8") as fh:
    requirements = [
        line.strip() 
        for line in fh 
        if line.strip() and not line.startswith("#")
    ]

# Read the README file if it exists
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "AWS CDK Application for TLS Passthrough with VPC Lattice"

setup(
    name="tls-passthrough-lattice-cdk",
    version="1.0.0",
    description="AWS CDK Application for TLS Passthrough with VPC Lattice, ACM, and Route 53",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS CDK Team",
    author_email="aws-cdk@amazon.com",
    url="https://github.com/aws/aws-cdk",
    license="Apache-2.0",
    
    # Package discovery
    packages=find_packages(where="."),
    package_dir={"": "."},
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=requirements,
    
    # Entry points for the CDK application
    entry_points={
        "console_scripts": [
            "tls-passthrough-lattice-cdk=app:main",
        ],
    },
    
    # Package classification
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
        "Topic :: Utilities",
        "Framework :: AWS CDK",
        "Framework :: AWS CDK :: 2",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "vpc-lattice",
        "tls",
        "passthrough",
        "encryption",
        "security",
        "microservices",
        "service-mesh",
        "certificate-manager",
        "route53",
        "end-to-end-encryption",
        "compliance",
        "zero-trust",
    ],
    
    # Include additional files
    include_package_data=True,
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Funding": "https://aws.amazon.com/",
    },
    
    # Additional metadata
    zip_safe=False,
    
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
        "security": [
            "cdk-nag>=2.28.0",
            "bandit>=1.7.0",
            "safety>=2.0.0",
        ],
        "docs": [
            "sphinx>=6.0.0",
            "sphinx-rtd-theme>=1.2.0",
            "myst-parser>=1.0.0",
        ],
    },
)