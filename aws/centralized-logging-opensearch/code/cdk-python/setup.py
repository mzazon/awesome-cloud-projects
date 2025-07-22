"""
Setup configuration for Centralized Logging with OpenSearch Service CDK application

This setup.py file configures the Python package for the CDK application,
defining dependencies, metadata, and installation requirements.
"""

from setuptools import setup, find_packages

# Read the README file for the long description
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "CDK Python application for Centralized Logging with Amazon OpenSearch Service"

# Read requirements from requirements.txt
def read_requirements():
    """Read and parse requirements.txt file"""
    try:
        with open("requirements.txt", "r", encoding="utf-8") as f:
            return [
                line.strip() 
                for line in f 
                if line.strip() and not line.startswith("#")
            ]
    except FileNotFoundError:
        # Fallback requirements if requirements.txt is not found
        return [
            "aws-cdk-lib>=2.110.0,<3.0.0",
            "constructs>=10.0.0,<11.0.0",
            "boto3>=1.34.0",
        ]

setup(
    name="centralized-logging-opensearch-cdk",
    version="1.0.0",
    author="AWS CDK Developer",
    author_email="developer@example.com",
    description="CDK Python application for Centralized Logging with Amazon OpenSearch Service",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws/aws-cdk",
    packages=find_packages(exclude=["tests*"]),
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: System :: Logging",
        "Topic :: System :: Monitoring",
        "Typing :: Typed",
    ],
    python_requires=">=3.8",
    install_requires=read_requirements(),
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "boto3-stubs[essential]>=1.34.0",
        ],
        "testing": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",  # For mocking AWS services in tests
        ],
    },
    entry_points={
        "console_scripts": [
            "cdk-centralized-logging=app:main",
        ],
    },
    project_urls={
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
    },
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "opensearch",
        "elasticsearch",
        "logging",
        "kinesis",
        "lambda",
        "cloudwatch",
        "monitoring",
        "analytics",
        "devops",
    ],
    include_package_data=True,
    zip_safe=False,
)