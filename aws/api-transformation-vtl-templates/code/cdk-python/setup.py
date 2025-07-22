"""
Setup configuration for Request/Response Transformation CDK Python Application

This setup.py file configures the Python package for the CDK application that
implements request/response transformation with VTL templates and custom models.
"""

from setuptools import setup, find_packages

# Read the contents of README file
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "CDK Python application for request/response transformation with VTL templates and custom models"

setup(
    name="request-response-transformation-cdk",
    version="1.0.0",
    description="CDK Python application for Transforming API Requests with VTL Templates",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS CDK Team",
    author_email="aws-cdk-team@amazon.com",
    url="https://github.com/aws/aws-cdk",
    
    # Package configuration
    packages=find_packages(exclude=["tests", "tests.*"]),
    package_dir={"": "."},
    
    # Python version requirement
    python_requires=">=3.8,<4.0",
    
    # Dependencies
    install_requires=[
        "aws-cdk-lib>=2.163.1,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.26.0,<2.0.0",
    ],
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0,<8.0.0",
            "pytest-cov>=4.0.0,<5.0.0",
            "black>=22.0.0,<24.0.0",
            "flake8>=5.0.0,<7.0.0",
            "mypy>=1.0.0,<2.0.0",
            "boto3-stubs[s3,lambda,apigateway]>=1.26.0,<2.0.0",
            "pre-commit>=3.0.0,<4.0.0",
        ],
        "test": [
            "pytest>=7.0.0,<8.0.0",
            "pytest-cov>=4.0.0,<5.0.0",
            "moto>=4.0.0,<5.0.0",  # For mocking AWS services in tests
        ],
    },
    
    # Entry points
    entry_points={
        "console_scripts": [
            "cdk-transform-app=app:main",
        ],
    },
    
    # Package metadata
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
        "Topic :: System :: Systems Administration",
        "Topic :: Utilities",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "api-gateway",
        "lambda",
        "vtl",
        "transformation",
        "serverless",
        "rest-api",
        "json-schema",
        "request-response",
        "mapping-templates",
    ],
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Funding": "https://github.com/sponsors/aws",
    },
    
    # Include additional files
    include_package_data=True,
    
    # Package data
    package_data={
        "": [
            "*.md",
            "*.txt",
            "*.json",
            "*.yaml",
            "*.yml",
        ],
    },
    
    # Zip safe
    zip_safe=False,
    
    # License
    license="Apache-2.0",
    
    # Platforms
    platforms=["any"],
)