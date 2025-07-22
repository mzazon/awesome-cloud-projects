"""
Setup configuration for Amazon Textract Document Analysis Solution CDK Python Application

This setup.py file configures the Python package for the CDK application,
including dependencies, metadata, and entry points.
"""

from setuptools import setup, find_packages

# Read requirements from requirements.txt
with open("requirements.txt", "r", encoding="utf-8") as fh:
    requirements = [line.strip() for line in fh if line.strip() and not line.startswith("#")]

# Read long description from README if it exists
long_description = """
# Amazon Textract Document Analysis Solution - CDK Python

This CDK Python application deploys a complete document analysis solution using Amazon Textract.
The solution includes:

- S3 buckets for input and output document storage
- Lambda function for document processing with Textract
- SNS topic for processing notifications
- IAM roles and policies with least privilege access
- CloudWatch logs for monitoring and debugging

## Features

- **Multi-format Support**: Processes PDF, JPG, JPEG, PNG, TIFF, and TIF files
- **Intelligent Analysis**: Extracts text, forms, tables, and answers custom queries
- **Event-driven Processing**: Automatically triggers on document upload to S3
- **Scalable Architecture**: Serverless design that scales with document volume
- **Comprehensive Monitoring**: CloudWatch logs and SNS notifications
- **Cost Optimization**: Lifecycle policies and intelligent storage transitions

## Deployment

```bash
# Install dependencies
pip install -r requirements.txt

# Deploy the stack
cdk deploy

# Test the solution
aws s3 cp test-document.pdf s3://[input-bucket]/test-documents/
```

## Security

The solution implements security best practices including:
- S3 bucket encryption with AWS managed keys
- IAM roles with least privilege access
- Lambda function with secure environment variables
- VPC endpoints for private communication (optional)

## Cost Optimization

- S3 lifecycle policies automatically transition older documents to cheaper storage
- Lambda function optimized for cost with appropriate memory allocation
- Pay-per-use pricing model scales with actual usage
"""

setup(
    name="textract-document-analysis-cdk",
    version="1.0.0",
    description="CDK Python application for Amazon Textract document analysis solution",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS CDK Team",
    author_email="aws-cdk-team@amazon.com",
    url="https://github.com/aws/aws-cdk",
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: Information Technology",
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Utilities",
        "Typing :: Typed",
    ],
    keywords="aws cdk textract document analysis machine learning ocr",
    packages=find_packages(),
    include_package_data=True,
    python_requires=">=3.8",
    install_requires=requirements,
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "isort>=5.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "bandit>=1.7.0",
            "safety>=2.3.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.2.0",
        ],
        "enhanced": [
            "pillow>=9.0.0",
            "pandas>=1.5.0",
            "numpy>=1.23.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "textract-cdk=app:main",
        ],
    },
    project_urls={
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Source": "https://github.com/aws/aws-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "AWS Textract": "https://aws.amazon.com/textract/",
    },
    license="Apache-2.0",
    zip_safe=False,
    package_data={
        "": ["*.txt", "*.md", "*.json", "*.yaml", "*.yml"],
    },
)