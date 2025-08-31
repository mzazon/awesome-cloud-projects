"""
Setup configuration for Basic Secret Management CDK Python application.

This setup.py file configures the Python package for the CDK application,
including metadata, dependencies, and package structure. It follows Python
packaging best practices and CDK conventions.
"""

import setuptools
from pathlib import Path

# Read the README file for long description
long_description = """
# Basic Secret Management with Secrets Manager and Lambda

This AWS CDK Python application demonstrates secure secret management using AWS Secrets Manager 
and AWS Lambda with the AWS Parameters and Secrets Extension layer.

## Architecture

The solution creates:
- AWS Secrets Manager secret with sample database credentials
- AWS Lambda function that retrieves secrets using the optimized extension
- IAM role with least privilege permissions
- CloudWatch log group for monitoring

## Features

- **Security**: Implements AWS Well-Architected Framework security principles
- **Performance**: Uses AWS Parameters and Secrets Extension for optimized retrieval
- **Cost-Effective**: Local caching reduces API calls and associated costs
- **Production-Ready**: Includes proper error handling and logging

## Deployment

```bash
# Install dependencies
pip install -r requirements.txt

# Deploy the stack
cdk deploy

# Test the Lambda function
aws lambda invoke --function-name <function-name> --payload '{}' response.json
```

## Best Practices

- Uses least privilege IAM permissions
- Implements proper resource tagging
- Includes CloudWatch log retention
- Follows CDK naming conventions
- Supports environment-specific deployments
"""

# Define package metadata
setuptools.setup(
    name="basic-secret-management-cdk",
    version="1.0.0",
    
    # Author and contact information
    author="AWS CDK Recipe Generator",
    author_email="mzazon@example.com",
    description="CDK application for basic secret management with AWS Secrets Manager and Lambda",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    # Project URLs and metadata
    url="https://github.com/aws-samples/basic-secret-management-cdk",
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/basic-secret-management-cdk/issues",
        "Source": "https://github.com/aws-samples/basic-secret-management-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
    },
    
    # Package classification
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: JavaScript",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9", 
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Code Generators",
        "Topic :: Utilities",
        "Typing :: Typed",
    ],
    
    # Python version requirements
    python_requires=">=3.8",
    
    # Package discovery and structure
    packages=setuptools.find_packages(exclude=["tests", "tests.*"]),
    
    # Install dependencies from requirements.txt
    install_requires=[
        "aws-cdk-lib==2.168.0",
        "constructs>=10.0.0,<11.0.0",
    ],
    
    # Optional dependencies for development and testing
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "mypy>=1.5.0",
            "pylint>=2.17.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
        ],
        "test": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "boto3>=1.34.0",
            "moto>=4.2.0",
        ],
        "docs": [
            "sphinx>=7.1.0",
            "sphinx-rtd-theme>=1.3.0",
        ],
    },
    
    # Entry points for command-line tools (if needed)
    entry_points={
        "console_scripts": [
            # Add command-line tools here if needed
            # "basic-secret-mgmt=basic_secret_management.cli:main",
        ],
    },
    
    # Include additional files in the package
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # Zip safe configuration
    zip_safe=False,
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "secrets-manager",
        "lambda",
        "security",
        "serverless",
        "python",
        "iac",
        "devops"
    ],
    
    # License information
    license="Apache License 2.0",
)