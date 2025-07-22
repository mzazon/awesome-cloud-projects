"""
Setup configuration for IoT Data Ingestion CDK Python Application

This package contains AWS CDK infrastructure code for deploying a complete
IoT data ingestion pipeline using AWS IoT Core, Lambda, DynamoDB, and SNS.
"""

import pathlib
from setuptools import setup, find_packages

# Get the current directory
HERE = pathlib.Path(__file__).parent

# Read the README file content
README = (HERE / "README.md").read_text() if (HERE / "README.md").exists() else ""

# Read requirements from requirements.txt
def get_requirements():
    """Read requirements from requirements.txt file."""
    requirements = []
    try:
        with open(HERE / "requirements.txt", "r") as f:
            for line in f:
                line = line.strip()
                # Skip empty lines and comments
                if line and not line.startswith("#"):
                    # Remove inline comments
                    requirement = line.split("#")[0].strip()
                    if requirement:
                        requirements.append(requirement)
    except FileNotFoundError:
        # Fallback to core dependencies if requirements.txt is not found
        requirements = [
            "aws-cdk-lib>=2.120.0,<3.0.0",
            "constructs>=10.0.0,<11.0.0",
            "boto3>=1.34.0",
        ]
    return requirements

setup(
    name="iot-data-ingestion-cdk",
    version="1.0.0",
    description="AWS CDK application for IoT data ingestion pipeline",
    long_description=README,
    long_description_content_type="text/markdown",
    author="AWS Solutions Architecture Team",
    author_email="solutions-team@example.com",
    url="https://github.com/aws-samples/iot-data-ingestion-cdk",
    license="MIT",
    
    # Package configuration
    packages=find_packages(exclude=["tests", "tests.*"]),
    include_package_data=True,
    zip_safe=False,
    
    # Python version requirements
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=get_requirements(),
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "mypy>=1.8.0",
            "black>=23.12.0",
            "flake8>=7.0.0",
            "isort>=5.13.0",
        ],
        "docs": [
            "sphinx>=7.2.0",
            "sphinx-rtd-theme>=2.0.0",
        ],
    },
    
    # Entry points for command-line tools
    entry_points={
        "console_scripts": [
            "iot-cdk-deploy=app:main",
        ],
    },
    
    # Project metadata
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: Internet :: WWW/HTTP",
        "Topic :: Software Development :: Code Generators",
        "Topic :: Utilities",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "iot",
        "lambda",
        "dynamodb",
        "sns",
        "infrastructure",
        "cloud",
        "serverless",
        "real-time",
        "data-ingestion",
        "mqtt",
    ],
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws-samples/iot-data-ingestion-cdk",
        "Bug Reports": "https://github.com/aws-samples/iot-data-ingestion-cdk/issues",
        "AWS IoT Core": "https://aws.amazon.com/iot-core/",
        "AWS CDK": "https://aws.amazon.com/cdk/",
    },
)