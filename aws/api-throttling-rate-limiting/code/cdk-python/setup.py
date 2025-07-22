"""
Setup configuration for AWS CDK Python application.

This setup.py file configures the Python package for the API throttling and 
rate limiting CDK application, including all dependencies and metadata.
"""

import setuptools
from pathlib import Path

# Read the requirements file
requirements_path = Path(__file__).parent / "requirements.txt"
with open(requirements_path, "r", encoding="utf-8") as f:
    requirements = [
        line.strip() 
        for line in f 
        if line.strip() and not line.startswith("#")
    ]

# Read the README if it exists
readme_path = Path(__file__).parent / "README.md"
long_description = ""
if readme_path.exists():
    with open(readme_path, "r", encoding="utf-8") as f:
        long_description = f.read()
else:
    long_description = "AWS CDK Python application for API Throttling and Rate Limiting"

setuptools.setup(
    name="api-throttling-rate-limiting-cdk",
    version="1.0.0",
    description="AWS CDK Python application for implementing comprehensive API throttling and rate limiting with API Gateway",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    # Author information
    author="AWS CDK Generator",
    author_email="developer@example.com",
    
    # Package discovery
    packages=setuptools.find_packages(),
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=requirements,
    
    # Package metadata
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP :: HTTP Servers",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "api-gateway",
        "throttling",
        "rate-limiting",
        "infrastructure-as-code",
        "cloud",
        "serverless"
    ],
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
    },
    
    # Package data
    include_package_data=True,
    zip_safe=False,
    
    # Entry points for command line scripts
    entry_points={
        "console_scripts": [
            "deploy-api-throttling=app:main",
        ],
    },
)