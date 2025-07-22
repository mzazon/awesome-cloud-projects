"""
Setup configuration for S3 Storage Cost Optimization CDK application.

This setup file configures the Python package for the CDK application,
including dependencies, metadata, and development tools.
"""

from setuptools import setup, find_packages

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setup(
    name="storage-cost-optimization-cdk",
    version="1.0.0",
    author="AWS CDK Team",
    author_email="aws-cdk-team@amazon.com",
    description="CDK application for S3 storage cost optimization with intelligent tiering and lifecycle policies",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/storage-cost-optimization-cdk",
    packages=find_packages(),
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Archiving :: Backup",
        "Topic :: System :: Archiving :: Mirroring",
        "Typing :: Typed",
    ],
    python_requires=">=3.8",
    install_requires=[
        "aws-cdk-lib>=2.120.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.34.0",
        "botocore>=1.34.0",
    ],
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "black>=23.0.0",
            "mypy>=1.0.0",
            "flake8>=6.0.0",
            "boto3-stubs[s3,cloudwatch,budgets,iam,lambda,events,logs]>=1.34.0",
            "types-python-dateutil>=2.8.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "storage-cost-optimization=app:main",
        ],
    },
    keywords=[
        "aws",
        "cdk",
        "s3",
        "storage",
        "cost-optimization",
        "intelligent-tiering",
        "lifecycle-policies",
        "cloudwatch",
        "budgets",
        "lambda",
        "monitoring",
        "analytics",
    ],
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/storage-cost-optimization-cdk/issues",
        "Source": "https://github.com/aws-samples/storage-cost-optimization-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "AWS S3 Documentation": "https://docs.aws.amazon.com/s3/",
        "AWS CloudWatch Documentation": "https://docs.aws.amazon.com/cloudwatch/",
    },
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    include_package_data=True,
    zip_safe=False,
)