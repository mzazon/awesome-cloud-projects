"""
Setup configuration for Document Summarization CDK Application

This setup.py file configures the Python package for the CDK application
that deploys an intelligent document summarization system using AWS services.
"""

import setuptools

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setuptools.setup(
    name="document-summarization-cdk",
    version="1.0.0",
    
    author="AWS CDK",
    description="CDK application for intelligent document summarization with Amazon Bedrock and Lambda",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    url="https://github.com/aws-samples/intelligent-document-summarization",
    
    packages=setuptools.find_packages(),
    
    install_requires=[
        "aws-cdk-lib>=2.120.0,<3.0.0",
        "constructs>=10.0.0,<12.0.0",
        "boto3>=1.26.0",
    ],
    
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
        ]
    },
    
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
        "Framework :: AWS CDK",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: Scientific/Engineering :: Artificial Intelligence",
    ],
    
    keywords=[
        "aws",
        "cdk",
        "cloud-development-kit",
        "infrastructure-as-code",
        "document-processing",
        "ai",
        "bedrock",
        "lambda",
        "serverless",
        "textract",
        "summarization"
    ],
    
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/intelligent-document-summarization/issues",
        "Source": "https://github.com/aws-samples/intelligent-document-summarization",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
    },
)