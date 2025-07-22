"""
Setup configuration for the Offline-First Mobile Applications CDK Python project.

This setup.py file configures the Python package for the CDK application that
deploys AWS infrastructure for offline-first mobile applications using
Amplify DataStore, AppSync, DynamoDB, and Cognito.
"""

from setuptools import setup, find_packages

# Read the contents of the README file for long description
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = """
    AWS CDK Python application for deploying offline-first mobile application infrastructure.
    
    This CDK application creates the necessary AWS resources for building mobile applications
    that work seamlessly in both online and offline scenarios using AWS Amplify DataStore.
    """

# Read requirements from requirements.txt
with open("requirements.txt", "r", encoding="utf-8") as fh:
    requirements = [line.strip() for line in fh if line.strip() and not line.startswith("#")]

setup(
    name="offline-first-mobile-cdk",
    version="1.0.0",
    description="AWS CDK Python app for offline-first mobile applications with Amplify DataStore",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS CDK Team",
    author_email="support@aws.amazon.com",
    url="https://github.com/aws/aws-cdk",
    license="Apache-2.0",
    
    # Package configuration
    packages=find_packages(exclude=["tests*"]),
    include_package_data=True,
    zip_safe=False,
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=requirements,
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "boto3-stubs[cognito-idp,appsync,dynamodb,lambda,iam,logs]>=1.26.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",
        ],
    },
    
    # Project classifiers
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
        "Topic :: Software Development :: Code Generators",
    ],
    
    # Keywords for package discovery
    keywords="aws cdk python amplify datastore offline-first mobile appsync dynamodb cognito",
    
    # Entry points
    entry_points={
        "console_scripts": [
            "deploy-offline-first-mobile=app:main",
        ],
    },
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Source": "https://github.com/aws/aws-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "AWS CDK Guide": "https://docs.aws.amazon.com/cdk/v2/guide/",
    },
    
    # Minimum CDK version compatibility
    options={
        "bdist_wheel": {
            "universal": False,
        },
    },
)