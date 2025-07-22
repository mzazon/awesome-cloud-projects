"""
AWS CDK Python package setup for Hybrid Identity Management.

This package contains the CDK Python application for deploying
a complete hybrid identity management solution using AWS Directory Service,
Amazon WorkSpaces, and Amazon RDS SQL Server.
"""

from setuptools import setup, find_packages

# Read version from file
VERSION = "1.0.0"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file."""
    try:
        with open("requirements.txt", "r", encoding="utf-8") as req_file:
            return [
                line.strip() 
                for line in req_file 
                if line.strip() and not line.startswith("#")
            ]
    except FileNotFoundError:
        return [
            "aws-cdk-lib>=2.100.0,<3.0.0",
            "constructs>=10.3.0,<11.0.0"
        ]

# Read long description from README if available
def read_long_description():
    """Read long description from README file."""
    try:
        with open("README.md", "r", encoding="utf-8") as readme_file:
            return readme_file.read()
    except FileNotFoundError:
        return "AWS CDK Python application for Hybrid Identity Management with Directory Service"

setup(
    name="hybrid-identity-management-cdk",
    version=VERSION,
    description="AWS CDK Python application for Hybrid Identity Management with Directory Service",
    long_description=read_long_description(),
    long_description_content_type="text/markdown",
    
    author="AWS CDK Generator",
    author_email="cloud-team@company.com",
    url="https://github.com/company/hybrid-identity-management-cdk",
    
    # Package discovery
    packages=find_packages(exclude=["tests*", "*.tests", "*.tests.*"]),
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=read_requirements(),
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.7.0",
            "flake8>=6.0.0",
            "mypy>=1.5.0",
            "types-setuptools>=68.0.0",
            "boto3-stubs[essential]>=1.28.0"
        ]
    },
    
    # Package classification
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP :: Site Management",
        "Environment :: Console"
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "identity",
        "directory-service",
        "workspaces",
        "rds",
        "active-directory",
        "hybrid-cloud",
        "authentication",
        "security"
    ],
    
    # Entry points
    entry_points={
        "console_scripts": [
            "hybrid-identity-deploy=app:main",
        ],
    },
    
    # Package data
    include_package_data=True,
    zip_safe=False,
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/company/hybrid-identity-management-cdk/issues",
        "Documentation": "https://github.com/company/hybrid-identity-management-cdk/wiki",
        "Source": "https://github.com/company/hybrid-identity-management-cdk",
    },
    
    # License
    license="Apache-2.0",
    
    # Minimum CDK version compatibility
    data_files=[
        ("", ["requirements.txt"]),
    ],
)