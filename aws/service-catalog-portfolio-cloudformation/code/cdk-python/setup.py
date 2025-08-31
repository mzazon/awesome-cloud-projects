"""
Setup configuration for AWS Service Catalog Portfolio CDK Python application.

This setup file configures the Python package for the Service Catalog portfolio
implementation, including dependencies, metadata, and package structure.
"""

from setuptools import setup, find_packages
import pathlib

# Get the long description from the README file
here = pathlib.Path(__file__).parent.resolve()
long_description = ""

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file."""
    with open("requirements.txt", "r") as f:
        return [line.strip() for line in f if line.strip() and not line.startswith("#")]

setup(
    name="service-catalog-portfolio-cdk",
    version="1.0.0",
    description="AWS Service Catalog Portfolio with CloudFormation Templates - CDK Python Implementation",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS Infrastructure Team",
    author_email="infrastructure@company.com",
    url="https://github.com/company/service-catalog-portfolio",
    
    # Package configuration
    packages=find_packages(exclude=["tests", "tests.*"]),
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=read_requirements(),
    
    # Optional dependencies for development
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",  # For mocking AWS services in tests
        ],
    },
    
    # Entry points for command-line scripts
    entry_points={
        "console_scripts": [
            "deploy-portfolio=app:main",
        ],
    },
    
    # Package metadata
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: System Administrators",
        "Intended Audience :: Developers",
        "Topic :: System :: Systems Administration",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Operating System :: OS Independent",
    ],
    
    # Keywords for package discovery
    keywords="aws cdk service-catalog cloudformation infrastructure governance",
    
    # Include additional files in the package
    include_package_data=True,
    package_data={
        "": ["*.yaml", "*.yml", "*.json", "*.md"],
    },
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/company/service-catalog-portfolio/issues",
        "Source": "https://github.com/company/service-catalog-portfolio",
        "Documentation": "https://docs.company.com/service-catalog-portfolio",
    },
    
    # Platform and environment compatibility
    platforms=["any"],
    zip_safe=False,
)