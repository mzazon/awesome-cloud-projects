"""
Setup configuration for Video Content Analysis CDK Python application.

This package contains the AWS CDK Python code for deploying a complete 
video content analysis pipeline using Amazon Rekognition, Step Functions,
Lambda, S3, DynamoDB, and SNS/SQS.
"""

from setuptools import setup, find_packages

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setup(
    name="video-content-analysis-cdk",
    version="1.0.0",
    author="AWS Solutions Architecture",
    author_email="solutions@example.com",
    description="AWS CDK Python application for video content analysis pipeline",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/video-content-analysis-cdk",
    packages=find_packages(),
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
        "Topic :: Multimedia :: Video :: Conversion",
        "Topic :: Scientific/Engineering :: Artificial Intelligence",
    ],
    python_requires=">=3.8",
    install_requires=[
        "aws-cdk-lib>=2.120.0",
        "constructs>=10.0.0",
        "boto3>=1.34.0",
        "botocore>=1.34.0",
    ],
    extras_require={
        "dev": [
            "mypy>=1.8.0",
            "black>=23.12.0",
            "flake8>=6.1.0",
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "aws-cdk.aws-lambda-python-alpha>=2.120.0a0",
        ],
        "docs": [
            "sphinx>=7.2.0",
            "sphinx-rtd-theme>=1.3.0",
            "myst-parser>=2.0.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "video-analysis-cdk=app:main",
        ],
    },
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.yaml", "*.yml", "*.json"],
    },
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/video-content-analysis-cdk/issues",
        "Source": "https://github.com/aws-samples/video-content-analysis-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/latest/guide/",
        "AWS CDK": "https://aws.amazon.com/cdk/",
        "Amazon Rekognition": "https://aws.amazon.com/rekognition/",
        "AWS Step Functions": "https://aws.amazon.com/step-functions/",
    },
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "video",
        "analysis",
        "rekognition",
        "step-functions",
        "lambda",
        "s3",
        "dynamodb",
        "sns",
        "sqs",
        "content-moderation",
        "segment-detection",
        "media-analysis",
        "serverless",
        "machine-learning",
        "ai",
        "automation",
    ],
)