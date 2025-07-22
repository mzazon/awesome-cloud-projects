"""
AWS CDK Python Setup Configuration for WAF Security

This setup.py file configures the Python package for the WAF security CDK application.
It includes all necessary dependencies and metadata for proper deployment.
"""

from setuptools import setup, find_packages

# Read the contents of README file for long description
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "AWS CDK Python application for comprehensive WAF security implementation"

# Define package metadata
setup(
    name="waf-security-cdk",
    version="1.0.0",
    description="AWS CDK Python application for implementing comprehensive WAF security rules",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS CDK Generator",
    author_email="developer@example.com",
    
    # Package configuration
    packages=find_packages(),
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=[
        "aws-cdk-lib==2.165.0",
        "constructs>=10.0.0,<11.0.0",
        "typing-extensions>=4.0.0",
    ],
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "boto3>=1.26.0",
            "botocore>=1.29.0",
        ]
    },
    
    # Entry points for CLI commands
    entry_points={
        "console_scripts": [
            "deploy-waf=app:main",
        ],
    },
    
    # Package classification
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: System Administrators",
        "Intended Audience :: Developers",
        "Topic :: System :: Systems Administration",
        "Topic :: Security",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
    ],
    
    # Keywords for package discovery
    keywords="aws cdk waf security firewall cloudfront alb protection",
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
    },
    
    # Package data
    include_package_data=True,
    zip_safe=False,
)