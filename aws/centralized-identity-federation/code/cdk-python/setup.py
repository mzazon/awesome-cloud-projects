"""
Setup script for AWS CDK Python Identity Federation application.

This setup.py file configures the Python package for the Identity Federation
with AWS SSO CDK application. It defines package metadata, dependencies,
and installation requirements.
"""

import setuptools

# Read the README file for long description
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "AWS CDK Python application for Identity Federation with AWS SSO"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file."""
    requirements = []
    try:
        with open("requirements.txt", "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                # Skip comments and empty lines
                if line and not line.startswith("#"):
                    # Remove inline comments
                    requirement = line.split("#")[0].strip()
                    if requirement:
                        requirements.append(requirement)
    except FileNotFoundError:
        # Fallback to basic requirements if file not found
        requirements = [
            "aws-cdk-lib==2.139.0",
            "constructs>=10.0.0,<11.0.0",
            "boto3>=1.26.0",
            "botocore>=1.29.0"
        ]
    return requirements

setuptools.setup(
    name="identity-federation-aws-sso-cdk",
    version="1.0.0",
    
    author="AWS CDK Python Generator",
    author_email="cdk@example.com",
    
    description="AWS CDK Python application for Identity Federation with AWS SSO",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    url="https://github.com/aws-samples/aws-cdk-examples",
    
    packages=setuptools.find_packages(),
    
    install_requires=read_requirements(),
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP",
    ],
    
    keywords=[
        "aws",
        "cdk",
        "identity",
        "federation",
        "sso",
        "iam",
        "security",
        "authentication",
        "authorization",
        "enterprise"
    ],
    
    # Entry points for command line scripts
    entry_points={
        "console_scripts": [
            "identity-federation-cdk=app:main",
        ],
    },
    
    # Include additional package data
    include_package_data=True,
    package_data={
        "": ["*.txt", "*.md", "*.json", "*.yaml", "*.yml"],
    },
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/aws-cdk-examples/issues",
        "Source": "https://github.com/aws-samples/aws-cdk-examples",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
    },
    
    # Additional metadata
    zip_safe=False,
    
    # Test configuration
    test_suite="tests",
    
    # Extras for optional dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "types-boto3>=1.0.0"
        ],
        "testing": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0"
        ]
    }
)