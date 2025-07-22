"""
Setup configuration for CloudFormation Nested Stacks CDK Python Application

This setup.py file configures the Python package for the CDK application that demonstrates
CloudFormation nested stack patterns using AWS CDK. It includes all necessary dependencies
and development tools for building production-ready infrastructure as code.
"""

from setuptools import setup, find_packages

# Read README for long description
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "CDK Python application for CloudFormation nested stacks with cross-stack references"

# Read requirements from requirements.txt
def read_requirements(filename):
    """Read requirements from requirements.txt file."""
    try:
        with open(filename, "r", encoding="utf-8") as f:
            return [
                line.strip()
                for line in f
                if line.strip() and not line.startswith("#")
            ]
    except FileNotFoundError:
        return []

# Development dependencies
dev_requirements = [
    "pytest>=7.0.0",
    "pytest-cov>=4.0.0",
    "black>=22.0.0",
    "flake8>=5.0.0",
    "mypy>=1.0.0",
    "bandit>=1.7.0",
    "safety>=2.0.0",
    "sphinx>=5.0.0",
    "sphinx-rtd-theme>=1.0.0",
]

setup(
    name="cloudformation-nested-stacks-cdk",
    version="1.0.0",
    author="AWS CDK Team",
    author_email="aws-cdk-dev@amazon.com",
    description="CDK Python application demonstrating CloudFormation nested stack patterns",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws/aws-cdk",
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
    },
    packages=find_packages(exclude=["tests", "tests.*"]),
    classifiers=[
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
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Utilities",
        "Typing :: Typed",
    ],
    python_requires=">=3.8",
    install_requires=[
        "aws-cdk-lib>=2.160.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.28.0",
        "botocore>=1.31.0",
        "PyYAML>=6.0",
    ],
    extras_require={
        "dev": dev_requirements,
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
        "testing": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",  # For mocking AWS services in tests
        ],
        "type-checking": [
            "mypy>=1.0.0",
            "types-boto3>=1.0.0",
            "boto3-stubs[essential]>=1.28.0",
        ],
        "security": [
            "bandit>=1.7.0",
            "safety>=2.0.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "cdk-deploy=app:main",
        ],
    },
    include_package_data=True,
    zip_safe=False,
    keywords=[
        "aws",
        "cdk",
        "cloudformation",
        "nested-stacks",
        "infrastructure-as-code",
        "devops",
        "cloud",
        "automation",
    ],
    license="Apache License 2.0",
    platforms=["any"],
)