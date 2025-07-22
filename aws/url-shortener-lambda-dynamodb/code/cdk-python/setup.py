"""
Setup configuration for AWS CDK Python URL Shortener Application

This setup.py file configures the Python package for the URL shortener
CDK application, including dependencies, metadata, and installation
instructions.
"""

import setuptools

# Read the README file for the long description
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "AWS CDK Python application for deploying a serverless URL shortener service"

# Read requirements from requirements.txt
try:
    with open("requirements.txt", "r", encoding="utf-8") as fh:
        requirements = [line.strip() for line in fh if line.strip() and not line.startswith("#")]
except FileNotFoundError:
    requirements = [
        "aws-cdk-lib==2.164.1",
        "constructs>=10.0.0,<11.0.0",
    ]

setuptools.setup(
    name="url-shortener-cdk",
    version="1.0.0",
    
    # Package metadata
    author="AWS CDK Developer",
    author_email="developer@example.com",
    description="AWS CDK Python application for serverless URL shortener service",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/example/url-shortener-cdk",
    
    # Package configuration
    packages=setuptools.find_packages(),
    include_package_data=True,
    
    # Dependencies
    install_requires=requirements,
    
    # Python version requirement
    python_requires=">=3.7",
    
    # Package classifiers
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.7",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP :: HTTP Servers",
        "Typing :: Typed",
    ],
    
    # Additional metadata
    keywords="aws cdk python serverless url-shortener lambda dynamodb api-gateway",
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/example/url-shortener-cdk",
        "Bug Reports": "https://github.com/example/url-shortener-cdk/issues",
    },
    
    # Entry points for command-line scripts (if needed)
    entry_points={
        "console_scripts": [
            # Add any command-line scripts here if needed
        ],
    },
    
    # Additional package data
    package_data={
        "": ["*.md", "*.txt", "*.yaml", "*.yml", "*.json"],
    },
    
    # Development dependencies (optional)
    extras_require={
        "dev": [
            "pytest>=6.2.0,<8.0.0",
            "pytest-cov>=2.12.0,<5.0.0",
            "black>=21.0.0,<24.0.0",
            "flake8>=3.9.0,<7.0.0",
            "mypy>=0.910,<2.0.0",
        ],
        "test": [
            "pytest>=6.2.0,<8.0.0",
            "pytest-cov>=2.12.0,<5.0.0",
            "moto[dynamodb]>=4.0.0",
            "requests>=2.25.0",
        ],
    },
    
    # Zip safety
    zip_safe=False,
)