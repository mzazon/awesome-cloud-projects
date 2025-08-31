"""
Setup configuration for Simple JSON to CSV Converter CDK Python Application.

This setup file configures the Python package for the CDK application that creates
a serverless data processing pipeline for converting JSON files to CSV format.
"""

import setuptools
from setuptools import find_packages

# Read the contents of README file for long description
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "Simple JSON to CSV Converter with Lambda and S3 - CDK Python Application"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file."""
    try:
        with open("requirements.txt", "r", encoding="utf-8") as req_file:
            requirements = []
            for line in req_file:
                line = line.strip()
                if line and not line.startswith("#"):
                    # Remove version comments and get package name with version
                    requirement = line.split("#")[0].strip()
                    if requirement:
                        requirements.append(requirement)
            return requirements
    except FileNotFoundError:
        # Fallback to minimal requirements if file doesn't exist
        return [
            "aws-cdk-lib>=2.170.0",
            "constructs>=10.0.0,<11.0.0",
            "cdk-nag>=2.28.0"
        ]

setuptools.setup(
    name="json-csv-converter-cdk",
    version="1.0.0",
    
    # Package metadata
    author="AWS CDK Generator",
    author_email="developer@example.com",
    description="CDK Python application for serverless JSON to CSV conversion",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/example/json-csv-converter-cdk",
    
    # Package configuration
    packages=find_packages(),
    include_package_data=True,
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=read_requirements(),
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0", 
            "black>=23.7.0",
            "flake8>=6.0.0",
            "mypy>=1.5.0",
            "types-requests>=2.31.0",
            "boto3-stubs[s3,lambda,iam,logs]>=1.34.0"
        ],
        "test": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "moto>=4.2.0",  # AWS service mocking for tests
            "pytest-mock>=3.11.0"
        ]
    },
    
    # Package classifiers
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
        "Topic :: Software Development :: Code Generators",
        "Topic :: Internet :: WWW/HTTP",
        "Topic :: System :: Installation/Setup",
        "Typing :: Typed"
    ],
    
    # Entry points for CLI commands
    entry_points={
        "console_scripts": [
            "deploy-json-csv-converter=app:main",
        ],
    },
    
    # Keywords for PyPI
    keywords=[
        "aws", "cdk", "serverless", "lambda", "s3", 
        "json", "csv", "data-processing", "cloud", 
        "infrastructure-as-code", "python"
    ],
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/example/json-csv-converter-cdk/issues",
        "Source": "https://github.com/example/json-csv-converter-cdk",
        "Documentation": "https://github.com/example/json-csv-converter-cdk/blob/main/README.md",
    },
    
    # License
    license="Apache-2.0",
    
    # Minimum setuptools version
    setup_requires=["setuptools>=45", "wheel"],
    
    # Include non-Python files
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # Zip safety
    zip_safe=False
)