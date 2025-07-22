"""
Setup configuration for EC2 Instance Connect CDK Python application.

This package deploys AWS infrastructure for demonstrating EC2 Instance Connect
secure SSH access management.
"""

from setuptools import setup, find_packages

# Read long description from README if it exists
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "AWS CDK Python application for EC2 Instance Connect secure SSH access"

setup(
    name="ec2-instance-connect-cdk",
    version="1.0.0",
    description="AWS CDK Python application for EC2 Instance Connect secure SSH access",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS Recipes",
    author_email="recipes@example.com",
    url="https://github.com/aws-recipes/ec2-instance-connect",
    
    # Package configuration
    packages=find_packages(exclude=["tests", "tests.*"]),
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=[
        "aws-cdk-lib>=2.120.0,<3.0.0",
        "constructs>=10.3.0,<11.0.0",
        "boto3>=1.34.0",
        "botocore>=1.34.0",
    ],
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "boto3-stubs[essential]>=1.34.0",
            "types-setuptools>=69.0.0",
        ],
    },
    
    # Entry points
    entry_points={
        "console_scripts": [
            "ec2-connect-cdk=app:main",
        ],
    },
    
    # Package metadata
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: MIT License",
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
        "Topic :: Security",
    ],
    
    # Additional metadata
    keywords=[
        "aws",
        "cdk",
        "cloud-development-kit",
        "ec2",
        "instance-connect",
        "ssh",
        "security",
        "infrastructure-as-code",
        "cloudformation",
    ],
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws-recipes/ec2-instance-connect",
        "Tracker": "https://github.com/aws-recipes/ec2-instance-connect/issues",
        "AWS CDK": "https://aws.amazon.com/cdk/",
        "EC2 Instance Connect": "https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/connect-linux-inst-eic.html",
    },
    
    # Include package data
    include_package_data=True,
    zip_safe=False,
)