"""
Setup configuration for Real-Time Analytics with Kinesis Data Streams CDK Application

This setup.py file defines the Python package configuration for the CDK application,
including dependencies, entry points, and metadata for proper package management.
"""

from setuptools import setup, find_packages
import os

# Read the contents of README file for long description
this_directory = os.path.abspath(os.path.dirname(__file__))
try:
    with open(os.path.join(this_directory, "README.md"), encoding="utf-8") as f:
        long_description = f.read()
except FileNotFoundError:
    long_description = "Real-Time Analytics with Amazon Kinesis Data Streams - CDK Python Application"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file"""
    try:
        with open(os.path.join(this_directory, "requirements.txt"), "r") as f:
            requirements = []
            for line in f:
                line = line.strip()
                # Skip comments and empty lines
                if line and not line.startswith("#"):
                    # Handle version constraints and remove comments
                    if "#" in line:
                        line = line.split("#")[0].strip()
                    requirements.append(line)
            return requirements
    except FileNotFoundError:
        # Fallback to core requirements if file not found
        return [
            "aws-cdk-lib>=2.110.0,<3.0.0",
            "constructs>=10.3.0,<11.0.0",
            "boto3>=1.28.0",
        ]

setup(
    name="kinesis-analytics-cdk",
    version="2.0.0",
    description="Real-Time Analytics with Amazon Kinesis Data Streams - AWS CDK Application",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS CDK Generator",
    author_email="noreply@example.com",
    url="https://github.com/aws-samples/kinesis-analytics-cdk",
    
    # Package discovery
    packages=find_packages(exclude=["tests", "tests.*"]),
    
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
            "isort>=5.12.0",
            "pre-commit>=3.3.0",
        ],
        "docs": [
            "sphinx>=7.1.0",
            "sphinx-rtd-theme>=1.3.0",
        ],
        "testing": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "moto>=4.2.0",  # AWS service mocking for tests
            "boto3-stubs[essential]>=1.28.0",
        ]
    },
    
    # Entry points for command-line tools
    entry_points={
        "console_scripts": [
            "kinesis-analytics-deploy=app:main",
        ],
    },
    
    # Package classification
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP",
        "Topic :: Database",
        "Topic :: Scientific/Engineering :: Information Analysis",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "kinesis",
        "analytics",
        "streaming",
        "real-time",
        "lambda",
        "cloudwatch",
        "s3",
        "infrastructure",
        "devops",
        "data-processing",
    ],
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws-samples/kinesis-analytics-cdk",
        "Bug Reports": "https://github.com/aws-samples/kinesis-analytics-cdk/issues",
        "AWS CDK": "https://aws.amazon.com/cdk/",
        "Amazon Kinesis": "https://aws.amazon.com/kinesis/",
    },
    
    # Include additional files in package
    include_package_data=True,
    
    # Package data specification
    package_data={
        "": [
            "*.md",
            "*.txt",
            "*.json",
            "*.yaml",
            "*.yml",
        ],
    },
    
    # Zip safe configuration
    zip_safe=False,
    
    # License
    license="Apache-2.0",
    
    # Platforms
    platforms=["any"],
)