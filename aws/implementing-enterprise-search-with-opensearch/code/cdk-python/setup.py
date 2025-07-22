"""
Setup configuration for the OpenSearch Service search solution CDK application.

This setup file defines the Python package configuration including dependencies,
metadata, and development tools for the CDK application that creates a comprehensive
search infrastructure using Amazon OpenSearch Service.
"""

from setuptools import setup, find_packages

# Read the README file for the long description
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "CDK Python application for Implementing Enterprise Search with OpenSearch Service"

# Define package metadata
PACKAGE_NAME = "opensearch-search-solution"
VERSION = "1.0.0"
DESCRIPTION = "CDK Python application for building enterprise-grade search solutions with Amazon OpenSearch Service"
AUTHOR = "AWS CDK Team"
AUTHOR_EMAIL = "aws-cdk@amazon.com"
URL = "https://github.com/aws/aws-cdk"

# Define dependencies
INSTALL_REQUIRES = [
    "aws-cdk-lib==2.121.0",
    "constructs>=10.0.0,<11.0.0",
    "boto3>=1.34.0",
    "botocore>=1.34.0",
    "requests>=2.31.0",
]

# Define development dependencies
EXTRAS_REQUIRE = {
    "dev": [
        "pytest>=7.0.0",
        "pytest-cov>=4.0.0",
        "black>=23.0.0",
        "flake8>=6.0.0",
        "mypy>=1.5.0",
        "types-requests>=2.31.0",
        "boto3-stubs[opensearch,lambda,s3,iam,logs,cloudwatch,sns]>=1.34.0",
    ],
    "alpha": [
        "aws-cdk.aws-lambda-python-alpha>=2.121.0a0",
    ],
}

# Python version requirements
PYTHON_REQUIRES = ">=3.8"

# Classifiers for package categorization
CLASSIFIERS = [
    "Development Status :: 5 - Production/Stable",
    "Intended Audience :: Developers",
    "Intended Audience :: System Administrators",
    "License :: OSI Approved :: Apache Software License",
    "Programming Language :: Python :: 3",
    "Programming Language :: Python :: 3.8",
    "Programming Language :: Python :: 3.9",
    "Programming Language :: Python :: 3.10",
    "Programming Language :: Python :: 3.11",
    "Programming Language :: Python :: 3.12",
    "Topic :: Software Development :: Libraries :: Python Modules",
    "Topic :: System :: Systems Administration",
    "Topic :: Internet :: WWW/HTTP :: Indexing/Search",
    "Typing :: Typed",
]

# Keywords for package discovery
KEYWORDS = [
    "aws",
    "cdk",
    "cloud",
    "infrastructure",
    "opensearch",
    "elasticsearch",
    "search",
    "analytics",
    "enterprise",
    "lambda",
    "serverless",
    "monitoring",
    "machine-learning",
    "real-time",
    "scalable",
]

# Setup configuration
setup(
    name=PACKAGE_NAME,
    version=VERSION,
    description=DESCRIPTION,
    long_description=long_description,
    long_description_content_type="text/markdown",
    author=AUTHOR,
    author_email=AUTHOR_EMAIL,
    url=URL,
    packages=find_packages(exclude=["tests", "tests.*"]),
    include_package_data=True,
    python_requires=PYTHON_REQUIRES,
    install_requires=INSTALL_REQUIRES,
    extras_require=EXTRAS_REQUIRE,
    classifiers=CLASSIFIERS,
    keywords=" ".join(KEYWORDS),
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "Tracker": "https://github.com/aws/aws-cdk/issues",
        "OpenSearch Service": "https://docs.aws.amazon.com/opensearch-service/",
        "CDK Python": "https://docs.aws.amazon.com/cdk/v2/guide/work-with-cdk-python.html",
    },
    entry_points={
        "console_scripts": [
            "opensearch-search-solution=app:main",
        ],
    },
    zip_safe=False,
    options={
        "build": {
            "build_base": "build",
        },
        "bdist_wheel": {
            "universal": False,
        },
    },
)

# Additional setup for development tools
if __name__ == "__main__":
    # Print setup information
    print(f"Setting up {PACKAGE_NAME} v{VERSION}")
    print(f"Description: {DESCRIPTION}")
    print(f"Python requirement: {PYTHON_REQUIRES}")
    print("For development setup, run: pip install -e .[dev,alpha]")
    print("For production setup, run: pip install -e .")