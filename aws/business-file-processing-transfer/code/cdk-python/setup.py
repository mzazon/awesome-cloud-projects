"""
AWS CDK Python setup configuration for automated business file processing
with AWS Transfer Family and Step Functions.

This setup file configures the CDK Python application for deployment
and development, including dependencies, metadata, and build configuration.
"""

import os
from setuptools import setup, find_packages

# Read the contents of README file for long description
def read_file(filename):
    """Read file contents for use in setup configuration."""
    here = os.path.abspath(os.path.dirname(__file__))
    with open(os.path.join(here, filename), encoding='utf-8') as f:
        return f.read()

# Package metadata
PACKAGE_NAME = "file-processing-cdk"
VERSION = "1.0.0"
DESCRIPTION = "AWS CDK Python application for automated business file processing"
LONG_DESCRIPTION = """
AWS CDK Python application that creates a complete serverless file processing pipeline
using AWS Transfer Family and Step Functions.

This application deploys:
- Secure SFTP endpoints via AWS Transfer Family
- Automated file processing using Lambda functions
- Workflow orchestration with Step Functions
- Multi-tier S3 storage with lifecycle policies
- Comprehensive monitoring and alerting

The solution is designed for organizations that need to process business-critical
files from partners through legacy SFTP protocols while modernizing their internal
data processing workflows.
"""

AUTHOR = "AWS CDK Generator"
AUTHOR_EMAIL = "aws-cdk@example.com"
URL = "https://github.com/aws-samples/file-processing-cdk"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file."""
    requirements_path = os.path.join(os.path.dirname(__file__), 'requirements.txt')
    if os.path.exists(requirements_path):
        with open(requirements_path, 'r', encoding='utf-8') as f:
            requirements = []
            for line in f:
                line = line.strip()
                # Skip comments and empty lines
                if line and not line.startswith('#'):
                    # Extract package name and version, ignore inline comments
                    requirement = line.split('#')[0].strip()
                    if requirement:
                        requirements.append(requirement)
            return requirements
    return []

# Development dependencies
DEV_REQUIREMENTS = [
    'pytest>=7.0.0',
    'pytest-cov>=4.0.0',
    'black>=22.0.0',
    'flake8>=5.0.0',
    'mypy>=1.0.0',
    'pydocstyle>=6.0.0',
    'isort>=5.0.0',
    'bandit>=1.7.0',
    'safety>=2.0.0'
]

# Package classification
CLASSIFIERS = [
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
    "Programming Language :: JavaScript",
    "Topic :: Software Development :: Code Generators",
    "Topic :: Utilities",
    "Topic :: System :: Systems Administration",
    "Topic :: Internet :: File Transfer Protocol (FTP)",
    "Topic :: System :: Archiving",
    "Typing :: Typed"
]

# Keywords for package discovery
KEYWORDS = [
    "aws", "cdk", "cloud", "infrastructure", "serverless",
    "transfer-family", "step-functions", "lambda", "s3",
    "sftp", "file-processing", "automation", "workflow",
    "business-integration", "data-pipeline"
]

setup(
    name=PACKAGE_NAME,
    version=VERSION,
    description=DESCRIPTION,
    long_description=LONG_DESCRIPTION,
    long_description_content_type="text/plain",
    author=AUTHOR,
    author_email=AUTHOR_EMAIL,
    url=URL,
    
    # Package configuration
    packages=find_packages(exclude=["tests*"]),
    include_package_data=True,
    zip_safe=False,
    
    # Python version requirements
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=read_requirements(),
    extras_require={
        "dev": DEV_REQUIREMENTS,
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",  # AWS service mocking for tests
            "boto3-stubs[essential]>=1.35.0"  # Type stubs for boto3
        ]
    },
    
    # Package classification
    classifiers=CLASSIFIERS,
    keywords=" ".join(KEYWORDS),
    
    # Entry points for CLI tools (if needed)
    entry_points={
        "console_scripts": [
            # Add CLI entry points here if needed in future
            # "file-processing-cli=file_processing.cli:main",
        ]
    },
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws-samples/file-processing-cdk",
        "Bug Reports": "https://github.com/aws-samples/file-processing-cdk/issues",
        "AWS CDK": "https://aws.amazon.com/cdk/",
        "AWS Transfer Family": "https://aws.amazon.com/aws-transfer-family/",
        "AWS Step Functions": "https://aws.amazon.com/step-functions/"
    },
    
    # License
    license="Apache License 2.0",
    
    # Additional metadata
    platforms=["any"],
    
    # Package data
    package_data={
        "": ["*.txt", "*.md", "*.json", "*.yaml", "*.yml"],
    },
)