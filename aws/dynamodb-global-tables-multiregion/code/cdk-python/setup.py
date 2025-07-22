"""
Setup configuration for DynamoDB Global Tables Multi-Region CDK Application.

This setup file configures the Python package for the CDK application,
including dependencies, entry points, and metadata.
"""

from setuptools import setup, find_packages

# Read the contents of README file
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "DynamoDB Global Tables Multi-Region CDK Application"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file."""
    try:
        with open("requirements.txt", "r", encoding="utf-8") as f:
            return [line.strip() for line in f if line.strip() and not line.startswith("#")]
    except FileNotFoundError:
        return [
            "aws-cdk-lib>=2.167.0",
            "constructs>=10.3.0",
            "typing-extensions>=4.0.0",
            "boto3>=1.34.0",
        ]

setup(
    name="dynamodb-global-tables-cdk",
    version="1.0.0",
    description="AWS CDK Python application for DynamoDB Global Tables Multi-Region setup",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS Solutions Architect",
    author_email="solutions-architect@amazon.com",
    url="https://github.com/aws-samples/dynamodb-global-tables-cdk",
    
    # Package configuration
    packages=find_packages(exclude=["tests*"]),
    include_package_data=True,
    zip_safe=False,
    
    # Python version requirements
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=read_requirements(),
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "bandit>=1.7.0",
            "pre-commit>=3.0.0",
            "isort>=5.12.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.2.0",
            "responses>=0.23.0",
            "jsonschema>=4.17.0",
        ],
        "docs": [
            "sphinx>=6.0.0",
            "sphinx-rtd-theme>=1.3.0",
        ],
        "jupyter": [
            "jupyterlab>=4.0.0",
            "ipython>=8.0.0",
        ],
    },
    
    # Entry points for command line tools
    entry_points={
        "console_scripts": [
            "deploy-global-tables=app:main",
        ],
    },
    
    # Package metadata
    classifiers=[
        "Development Status :: 4 - Beta",
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
        "Topic :: System :: Systems Administration",
        "Topic :: Utilities",
        "Framework :: AWS CDK",
        "Framework :: AWS CDK :: 2",
    ],
    
    # Keywords for PyPI
    keywords=[
        "aws",
        "cdk",
        "dynamodb",
        "global-tables",
        "multi-region",
        "infrastructure",
        "cloudformation",
        "python",
        "cloud",
        "devops",
        "infrastructure-as-code",
    ],
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/dynamodb-global-tables-cdk/issues",
        "Source": "https://github.com/aws-samples/dynamodb-global-tables-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/v2/guide/",
        "AWS CDK": "https://aws.amazon.com/cdk/",
        "DynamoDB Global Tables": "https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/GlobalTables.html",
    },
    
    # License
    license="MIT",
    
    # Package data
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # Manifest
    data_files=[
        ("", ["requirements.txt"]),
    ],
)