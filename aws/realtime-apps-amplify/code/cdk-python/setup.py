"""
Setup configuration for Real-Time Applications CDK Python package.

This package contains AWS CDK infrastructure code for deploying a full-stack
real-time chat application using AWS AppSync, Cognito, DynamoDB, and Lambda.
"""

from setuptools import setup, find_packages

# Read the contents of the README file
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "CDK Python application for Real-Time Applications with AWS AppSync"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file."""
    try:
        with open("requirements.txt", "r", encoding="utf-8") as req_file:
            return [line.strip() for line in req_file if line.strip() and not line.startswith("#")]
    except FileNotFoundError:
        return [
            "aws-cdk-lib>=2.168.0",
            "constructs>=10.0.0,<11.0.0",
            "boto3>=1.34.0"
        ]

setup(
    name="realtime-app-cdk",
    version="1.0.0",
    
    description="AWS CDK Python application for Real-Time Applications with AppSync and Amplify",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS CDK Team",
    author_email="aws-cdk-team@amazon.com",
    
    url="https://github.com/aws/aws-cdk",
    
    packages=find_packages(exclude=["tests", "tests.*"]),
    
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
        "Topic :: Communications :: Chat",
        "Typing :: Typed",
    ],
    
    keywords="aws cdk appsync graphql realtime chat websocket amplify",
    
    python_requires=">=3.8",
    
    install_requires=read_requirements(),
    
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.7.0",
            "flake8>=6.0.0",
            "mypy>=1.5.0",
            "types-boto3>=1.0.0",
        ],
        "docs": [
            "sphinx>=7.1.0",
            "sphinx-rtd-theme>=1.3.0",
        ],
    },
    
    entry_points={
        "console_scripts": [
            "realtime-app-cdk=app:main",
        ],
    },
    
    project_urls={
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
    },
    
    include_package_data=True,
    zip_safe=False,
    
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # CDK-specific metadata
    cdkVersion="2.168.0",
    
    # Additional metadata
    license="Apache-2.0",
    platforms=["any"],
    
    # Project configuration
    options={
        "bdist_wheel": {
            "universal": False,
        },
    },
)