"""
Setup configuration for Cross-Account Database Sharing CDK Application.

This setup.py file configures the Python package for the CDK application
that implements secure cross-account database sharing using VPC Lattice
and RDS with AWS best practices.
"""

from setuptools import setup, find_packages

# Read the README file for long description
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "Cross-Account Database Sharing with VPC Lattice and RDS"

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
            "aws-cdk-lib>=2.120.0,<3.0.0",
            "constructs>=10.3.0,<11.0.0",
        ]

setup(
    name="cross-account-database-sharing-cdk",
    version="1.0.0",
    
    # Package metadata
    description="AWS CDK application for cross-account database sharing with VPC Lattice and RDS",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    # Author information
    author="AWS CDK Generator",
    author_email="aws-recipes@example.com",
    
    # Project URLs
    url="https://github.com/aws-samples/recipes",
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/recipes/issues",
        "Source": "https://github.com/aws-samples/recipes",
        "Documentation": "https://github.com/aws-samples/recipes/aws/cross-account-database-sharing-lattice-rds",
    },
    
    # Package discovery and dependencies
    packages=find_packages(where="."),
    package_dir={"": "."},
    install_requires=read_requirements(),
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.4.0,<8.0.0",
            "pytest-cov>=4.1.0,<5.0.0",
            "black>=23.7.0,<24.0.0",
            "flake8>=6.0.0,<7.0.0",
            "mypy>=1.5.0,<2.0.0",
            "bandit>=1.7.5,<2.0.0",
            "safety>=2.3.0,<3.0.0",
        ],
        "docs": [
            "sphinx>=7.1.0,<8.0.0",
            "sphinx-rtd-theme>=1.3.0,<2.0.0",
        ],
    },
    
    # Python version requirements
    python_requires=">=3.8,<4.0",
    
    # Package classification
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
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
        "Typing :: Typed",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "infrastructure",
        "cloud",
        "database",
        "rds",
        "vpc-lattice",
        "cross-account",
        "security",
        "networking",
        "mysql",
        "iac",
        "devops",
    ],
    
    # Entry points for command-line tools
    entry_points={
        "console_scripts": [
            "deploy-database-sharing=app:main",
        ],
    },
    
    # Include additional files in package
    include_package_data=True,
    package_data={
        "": [
            "*.md",
            "*.txt",
            "*.json",
            "*.yaml",
            "*.yml",
        ],
    },
    
    # Zip safety
    zip_safe=False,
    
    # License information
    license="MIT",
    
    # Platform compatibility
    platforms=["any"],
)