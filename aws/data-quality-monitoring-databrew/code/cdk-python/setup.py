"""
Setup configuration for AWS Glue DataBrew Data Quality Monitoring CDK Application.

This setup file configures the Python package for the CDK application that
creates a comprehensive data quality monitoring solution using AWS services.
"""

import setuptools

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setuptools.setup(
    name="data-quality-monitoring-aws-glue-databrew",
    version="1.0.0",
    author="AWS CDK Team",
    author_email="aws-cdk-team@amazon.com",
    description="AWS CDK application for data quality monitoring with AWS Glue DataBrew",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws/aws-cdk",
    
    packages=setuptools.find_packages(),
    
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Typing :: Typed",
    ],
    
    python_requires=">=3.8",
    
    install_requires=[
        "aws-cdk-lib>=2.114.1",
        "constructs>=10.0.0,<11.0.0",
        "typing-extensions>=4.0.0",
        "boto3>=1.28.0",
        "botocore>=1.31.0",
    ],
    
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=0.991",
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
    },
    
    entry_points={
        "console_scripts": [
            "data-quality-monitoring=app:main",
        ],
    },
    
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "data-quality",
        "databrew",
        "monitoring",
        "analytics",
        "serverless",
    ],
    
    project_urls={
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Source": "https://github.com/aws/aws-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
    },
)