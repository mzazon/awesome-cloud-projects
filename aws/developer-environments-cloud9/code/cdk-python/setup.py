"""
Setup configuration for AWS Cloud9 Developer Environment CDK Application

This setup.py file configures the Python package for the Cloud9 developer
environment CDK application, including all necessary dependencies and
metadata for proper deployment and development.
"""

from setuptools import setup, find_packages

# Read long description from README if it exists
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "AWS Cloud9 Developer Environment CDK Application"

setup(
    name="cloud9-developer-environment-cdk",
    version="1.0.0",
    description="AWS CDK application for creating Cloud9 developer environments with team collaboration features",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS CDK Developer",
    author_email="developer@example.com",
    url="https://github.com/aws-samples/cloud9-developer-environment-cdk",
    packages=find_packages(exclude=["tests", "tests.*"]),
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Package dependencies
    install_requires=[
        "aws-cdk-lib>=2.100.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "python-dotenv>=1.0.0",
    ],
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "types-setuptools",
            "boto3-stubs[essential]>=1.26.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",
        ],
    },
    
    # Entry points for command line tools
    entry_points={
        "console_scripts": [
            "cloud9-dev-env=app:main",
        ],
    },
    
    # Package classifiers
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP",
        "Topic :: Software Development :: Code Generators",
        "Framework :: AWS CDK",
        "Framework :: AWS CDK :: 2",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "cloud9",
        "development",
        "environment",
        "collaboration",
        "infrastructure",
        "devops",
        "codecommit",
        "cloudwatch",
        "iam",
        "ec2",
    ],
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/cloud9-developer-environment-cdk/issues",
        "Source": "https://github.com/aws-samples/cloud9-developer-environment-cdk",
        "Documentation": "https://docs.aws.amazon.com/cloud9/",
        "AWS CDK Documentation": "https://docs.aws.amazon.com/cdk/v2/guide/home.html",
    },
    
    # Include additional files
    include_package_data=True,
    zip_safe=False,
    
    # License
    license="Apache License 2.0",
    
    # Package data
    package_data={
        "": ["*.md", "*.txt", "*.yaml", "*.yml", "*.json"],
    },
)