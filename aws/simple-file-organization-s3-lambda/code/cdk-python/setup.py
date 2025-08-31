"""
Setup configuration for Simple File Organization CDK Python application.

This setup file configures the Python package for the AWS CDK application
that implements automated file organization using S3 and Lambda services.
"""

from setuptools import setup, find_packages

# Read version from VERSION file or use default
try:
    with open("VERSION", "r", encoding="utf-8") as version_file:
        version = version_file.read().strip()
except FileNotFoundError:
    version = "1.0.0"

# Read long description from README if available
try:
    with open("README.md", "r", encoding="utf-8") as readme_file:
        long_description = readme_file.read()
except FileNotFoundError:
    long_description = """
    AWS CDK Python application for automated file organization using S3 and Lambda.
    
    This application creates an event-driven system that automatically organizes
    uploaded files by type into structured folder hierarchies within an S3 bucket.
    """

# Define package metadata
setup(
    name="simple-file-organization-cdk",
    version=version,
    description="AWS CDK application for automated file organization with S3 and Lambda",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS CDK Team",
    author_email="cdk-team@example.com",
    url="https://github.com/aws-samples/simple-file-organization-cdk",
    
    # Package configuration
    packages=find_packages(exclude=["tests", "tests.*"]),
    include_package_data=True,
    zip_safe=False,
    
    # Python version requirements
    python_requires=">=3.8",
    
    # Core dependencies
    install_requires=[
        "aws-cdk-lib>=2.169.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "aws-solutions-constructs.aws-s3-lambda>=2.79.0",
        "cdk-nag>=2.31.0",
        "boto3>=1.35.0",
        "typing-extensions>=4.0.0",
    ],
    
    # Optional dependencies for development and enhanced features
    extras_require={
        "dev": [
            "pytest>=8.0.0",
            "pytest-cov>=5.0.0",
            "black>=24.0.0",
            "flake8>=7.0.0",
            "mypy>=1.11.0",
            "moto[s3,lambda]>=5.0.0",
        ],
        "powertools": [
            "aws-lambda-powertools[all]>=3.2.0",
        ],
        "docs": [
            "sphinx>=8.0.0",
            "sphinx-rtd-theme>=3.0.0",
        ],
        "all": [
            "pytest>=8.0.0",
            "pytest-cov>=5.0.0",
            "black>=24.0.0",
            "flake8>=7.0.0",
            "mypy>=1.11.0",
            "moto[s3,lambda]>=5.0.0",
            "aws-lambda-powertools[all]>=3.2.0",
            "sphinx>=8.0.0",
            "sphinx-rtd-theme>=3.0.0",
        ]
    },
    
    # Package classification
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
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
        "Topic :: Internet :: WWW/HTTP",
        "Topic :: Utilities",
        "Framework :: AWS CDK",
        "Framework :: AWS CDK :: 2",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws", "cdk", "s3", "lambda", "serverless", "file-organization",
        "automation", "event-driven", "cloud", "infrastructure-as-code"
    ],
    
    # Entry points for command line scripts
    entry_points={
        "console_scripts": [
            "deploy-file-organizer=app:main",
        ],
    },
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source Code": "https://github.com/aws-samples/simple-file-organization-cdk",
        "Bug Reports": "https://github.com/aws-samples/simple-file-organization-cdk/issues",
        "AWS CDK": "https://aws.amazon.com/cdk/",
        "AWS Solutions Constructs": "https://docs.aws.amazon.com/solutions/latest/constructs/",
    },
    
    # Additional metadata
    license="Apache-2.0",
    platforms=["any"],
    
    # Package data files
    package_data={
        "": ["*.md", "*.txt", "*.yml", "*.yaml", "*.json"],
    },
)