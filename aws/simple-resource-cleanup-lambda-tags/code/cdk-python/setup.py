"""
Setup configuration for AWS CDK Python Resource Cleanup Automation application.

This setup file configures the Python package for the CDK application that
creates an automated resource cleanup system using AWS Lambda to identify
and terminate EC2 instances based on specific tags.
"""

import setuptools

# Read the long description from README (if it exists)
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "AWS CDK Python application for automated resource cleanup using Lambda and tags"

# Read requirements from requirements.txt
with open("requirements.txt", "r", encoding="utf-8") as fh:
    requirements = [
        line.strip() 
        for line in fh.readlines() 
        if line.strip() and not line.startswith("#")
    ]

setuptools.setup(
    name="resource-cleanup-cdk",
    version="1.0.0",
    
    # Package information
    author="AWS CDK Team",
    author_email="aws-cdk@amazon.com",
    description="CDK Python application for automated EC2 resource cleanup using Lambda and tags",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    # Project URLs
    url="https://github.com/aws/aws-cdk",
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "Tracker": "https://github.com/aws/aws-cdk/issues",
    },
    
    # Package discovery and requirements
    packages=setuptools.find_packages(),
    install_requires=requirements,
    
    # Python version requirements
    python_requires=">=3.8",
    
    # Package classification
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
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Typing :: Typed",
    ],
    
    # Entry points for command-line scripts (if needed)
    entry_points={
        "console_scripts": [
            "resource-cleanup-cdk=app:main",
        ],
    },
    
    # Include additional files
    include_package_data=True,
    zip_safe=False,
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "lambda",
        "ec2",
        "automation",
        "resource-cleanup",
        "cost-optimization",
        "serverless",
        "sns",
        "notifications",
        "tags",
    ],
    
    # Optional dependencies for development
    extras_require={
        "dev": [
            "mypy>=1.8.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
        ],
        "test": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "moto>=4.2.0",  # For mocking AWS services in tests
        ],
    },
)