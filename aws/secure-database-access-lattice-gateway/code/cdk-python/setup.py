"""
Setup configuration for Secure Database Access with VPC Lattice CDK Application

This setup.py file configures the Python package for the CDK application
that deploys secure cross-account database access using AWS VPC Lattice
Resource Gateway.
"""

from setuptools import setup, find_packages

# Read version from VERSION file or default
try:
    with open("VERSION", "r") as f:
        version = f.read().strip()
except FileNotFoundError:
    version = "1.0.0"

# Read long description from README
try:
    with open("README.md", "r", encoding="utf-8") as f:
        long_description = f.read()
except FileNotFoundError:
    long_description = "Secure Database Access with VPC Lattice Resource Gateway CDK Application"

setup(
    name="secure-database-access-vpclattice",
    version=version,
    description="CDK application for secure cross-account database access with VPC Lattice",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS Solutions Architecture Team",
    author_email="aws-solutions@amazon.com",
    url="https://github.com/aws-samples/secure-database-access-vpclattice",
    
    # Package configuration
    packages=find_packages(exclude=["tests*"]),
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=[
        "aws-cdk-lib>=2.100.0",
        "constructs>=10.0.0",
        "boto3>=1.28.0",
    ],
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.7.0",
            "flake8>=6.0.0",
            "mypy>=1.5.0",
            "boto3-stubs[essential]>=1.28.0",
            "types-requests>=2.31.0",
        ]
    },
    
    # Package classifiers
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP",
        "Topic :: Database",
        "Topic :: Security",
    ],
    
    # Package metadata
    keywords="aws cdk vpc-lattice database security cross-account rds networking",
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/secure-database-access-vpclattice/issues",
        "Source": "https://github.com/aws-samples/secure-database-access-vpclattice",
        "Documentation": "https://docs.aws.amazon.com/vpc-lattice/",
    },
    
    # Entry points for CLI tools (if needed)
    entry_points={
        "console_scripts": [
            "deploy-secure-db=app:main",
        ],
    },
    
    # Include additional files
    include_package_data=True,
    package_data={
        "": ["*.json", "*.yaml", "*.yml", "*.md", "*.txt"],
    },
    
    # Zip safety
    zip_safe=False,
)