"""
Setup configuration for Simple Password Generator CDK Python application.

This setup.py file configures the Python package for the AWS CDK application
that deploys a serverless password generator using Lambda and S3.
"""

from setuptools import setup, find_packages

# Read the contents of README file for long description
import os
import sys

# Ensure we can import from the current directory
sys.path.insert(0, os.path.dirname(__file__))

# Package metadata
PACKAGE_NAME = "simple-password-generator-cdk"
VERSION = "1.0.0"
DESCRIPTION = "AWS CDK Python application for Simple Password Generator with Lambda and S3"
LONG_DESCRIPTION = """
Simple Password Generator CDK Application
========================================

This AWS CDK Python application deploys a serverless password generator that provides:

- **Secure Password Generation**: Uses Python's cryptographically secure secrets module
- **Encrypted Storage**: Amazon S3 bucket with AES-256 encryption at rest
- **Versioning Support**: S3 versioning enabled for password history tracking
- **Least Privilege Security**: IAM roles with minimal required permissions
- **Cost Optimization**: Lifecycle policies for intelligent storage tiering
- **Monitoring**: CloudWatch Logs integration for debugging and audit trails

## Architecture

The application creates:
- AWS Lambda function for password generation (Python 3.12 runtime)
- Amazon S3 bucket with encryption, versioning, and lifecycle policies
- IAM role with least privilege permissions
- CloudWatch Log Group for Lambda function logs

## Security Features

- Server-side encryption using S3 managed keys (AES-256)
- Block all public access on S3 bucket
- IAM role with minimal required permissions
- Secure random password generation using Python secrets module
- No sensitive data in CloudFormation outputs

## Deployment

Deploy using AWS CDK:
```bash
cdk deploy
```

## Testing

Test the Lambda function:
```bash
aws lambda invoke --function-name <function-name> --payload '{"length": 16}' response.json
```

## Cleanup

Remove all resources:
```bash
cdk destroy
```
"""

# Author information
AUTHOR = "AWS CDK Python Generator"
AUTHOR_EMAIL = "aws-cdk-python@example.com"
URL = "https://github.com/aws/aws-cdk"

# Package requirements
INSTALL_REQUIRES = [
    "aws-cdk-lib==2.166.0",
    "constructs>=10.0.0,<11.0.0",
    "typing-extensions>=4.0.0",
]

# Development requirements
EXTRAS_REQUIRE = {
    "dev": [
        "pytest>=7.0.0",
        "pytest-cov>=4.0.0",
        "black>=22.0.0",
        "flake8>=5.0.0",
        "mypy>=0.991",
        "boto3>=1.26.0",  # For testing AWS SDK functionality
    ],
    "testing": [
        "pytest>=7.0.0",
        "pytest-cov>=4.0.0",
        "moto>=4.0.0",  # Mock AWS services for testing
    ],
}

# Python version requirement
PYTHON_REQUIRES = ">=3.8"

# Package classifiers for PyPI
CLASSIFIERS = [
    "Development Status :: 4 - Beta",
    "Intended Audience :: Developers",
    "Topic :: Software Development :: Libraries :: Python Modules",
    "Topic :: System :: Systems Administration",
    "License :: OSI Approved :: Apache Software License",
    "Programming Language :: Python :: 3",
    "Programming Language :: Python :: 3.8",
    "Programming Language :: Python :: 3.9",
    "Programming Language :: Python :: 3.10",
    "Programming Language :: Python :: 3.11",
    "Programming Language :: Python :: 3.12",
    "Operating System :: OS Independent",
    "Environment :: Console",
    "Framework :: AWS CDK",
    "Topic :: Security",
    "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
]

# Keywords for package discovery
KEYWORDS = [
    "aws", "cdk", "cloud", "infrastructure", "lambda", "s3", 
    "password", "generator", "security", "serverless", "python"
]

# Package configuration
setup(
    name=PACKAGE_NAME,
    version=VERSION,
    description=DESCRIPTION,
    long_description=LONG_DESCRIPTION,
    long_description_content_type="text/markdown",
    author=AUTHOR,
    author_email=AUTHOR_EMAIL,
    url=URL,
    
    # Package discovery
    packages=find_packages(exclude=["tests", "tests.*"]),
    include_package_data=True,
    
    # Dependencies
    install_requires=INSTALL_REQUIRES,
    extras_require=EXTRAS_REQUIRE,
    python_requires=PYTHON_REQUIRES,
    
    # Package metadata
    classifiers=CLASSIFIERS,
    keywords=KEYWORDS,
    license="Apache-2.0",
    
    # Entry points for command-line scripts (if needed)
    entry_points={
        "console_scripts": [
            # Uncomment if you want to create CLI commands
            # "password-generator-cdk=app:main",
        ],
    },
    
    # Package data files
    package_data={
        "": ["*.md", "*.txt", "*.yaml", "*.yml", "*.json"],
    },
    
    # Zip safety
    zip_safe=False,
    
    # Project URLs for PyPI
    project_urls={
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Source": "https://github.com/aws/aws-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "AWS CDK": "https://aws.amazon.com/cdk/",
    },
)

# Additional setup notes:
# 
# To build and install the package locally:
# python setup.py develop
# 
# To create a distribution package:
# python setup.py sdist bdist_wheel
# 
# To install in development mode:
# pip install -e .
# 
# To install with development dependencies:
# pip install -e .[dev]