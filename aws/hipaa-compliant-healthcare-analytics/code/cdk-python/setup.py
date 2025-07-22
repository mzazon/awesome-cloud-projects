"""
Setup configuration for Healthcare Data Processing Pipelines CDK application

This setup.py file configures the Python package for the AWS CDK application
that deploys healthcare data processing pipelines with AWS HealthLake.
"""

import setuptools

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setuptools.setup(
    name="healthcare-data-processing-cdk",
    version="1.0.0",
    
    description="AWS CDK application for Healthcare Data Processing Pipelines with AWS HealthLake",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS CDK Generator",
    author_email="cloudinfrastructure@example.com",
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Healthcare Industry",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Code Generators",
        "Topic :: Utilities",
        "Topic :: Scientific/Engineering :: Medical Science Apps.",
    ],
    
    install_requires=[
        "aws-cdk-lib==2.162.1",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.26.0",
        "botocore>=1.29.0",
    ],
    
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "black>=22.0.0",
            "flake8>=4.0.0",
            "mypy>=0.910",
            "boto3-stubs[essential]>=1.26.0",
            "types-requests>=2.28.0",
        ],
    },
    
    entry_points={
        "console_scripts": [
            "healthcare-cdk=app:main",
        ],
    },
    
    keywords=[
        "aws",
        "cdk",
        "healthlake",
        "healthcare",
        "fhir",
        "hipaa",
        "data-processing",
        "analytics",
        "lambda",
        "eventbridge",
        "s3",
        "cloud",
        "infrastructure",
        "iac"
    ],
    
    project_urls={
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Source": "https://github.com/aws/aws-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "AWS HealthLake": "https://docs.aws.amazon.com/healthlake/",
    },
)