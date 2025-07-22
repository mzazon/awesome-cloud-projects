"""
AWS CDK Python setup configuration for secure file sharing Transfer Family solution.

This setup.py file configures the Python package for the AWS CDK application
that deploys a secure file sharing solution using AWS Transfer Family Web Apps.

Author: AWS CDK Recipe Generator
Version: 1.0
"""

import setuptools
from pathlib import Path

# Read long description from README if available
readme_path = Path(__file__).parent / "README.md"
long_description = readme_path.read_text(encoding="utf-8") if readme_path.exists() else ""

# Package metadata
PACKAGE_NAME = "secure_file_sharing_cdk"
VERSION = "1.0.0"
DESCRIPTION = "AWS CDK application for secure file sharing with Transfer Family Web Apps"
AUTHOR = "AWS Solutions"
AUTHOR_EMAIL = "aws-solutions@amazon.com"
URL = "https://github.com/aws-samples/recipes"

# Define requirements
CDK_VERSION = "2.163.1"

# Core requirements needed for the CDK application
INSTALL_REQUIRES = [
    f"aws-cdk-lib=={CDK_VERSION}",
    "constructs>=10.0.0,<11.0.0",
    "python-dotenv>=1.0.0",
    "pyyaml>=6.0.0",
]

# Development requirements for testing and code quality
DEV_REQUIRES = [
    "pytest>=7.4.0",
    "pytest-cov>=4.1.0",
    "black>=23.7.0",
    "flake8>=6.0.0",
    "mypy>=1.5.0",
    "types-boto3>=1.0.0",
    f"boto3-stubs[s3,iam,transfer,cloudtrail,logs,sso-admin]>=1.34.0",
]

# Package configuration
setuptools.setup(
    name=PACKAGE_NAME,
    version=VERSION,
    description=DESCRIPTION,
    long_description=long_description,
    long_description_content_type="text/markdown",
    author=AUTHOR,
    author_email=AUTHOR_EMAIL,
    url=URL,
    
    # Package discovery
    packages=setuptools.find_packages(),
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    include_package_data=True,
    
    # Python version requirements
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=INSTALL_REQUIRES,
    extras_require={
        "dev": DEV_REQUIRES,
        "test": ["pytest>=7.4.0", "pytest-cov>=4.1.0"],
        "lint": ["black>=23.7.0", "flake8>=6.0.0", "mypy>=1.5.0"],
    },
    
    # Entry points for command-line interface
    entry_points={
        "console_scripts": [
            "deploy-secure-file-sharing=app:main",
        ],
    },
    
    # Classification metadata
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
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: File Transfer Protocol (FTP)",
        "Topic :: Security",
        "Topic :: System :: Archiving",
    ],
    
    # Keywords for discovery
    keywords=[
        "aws",
        "cdk",
        "transfer-family",
        "s3",
        "file-sharing",
        "secure",
        "web-app",
        "identity-center",
        "cloudtrail",
        "audit",
        "sftp",
        "infrastructure-as-code",
    ],
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/transfer/",
        "Source": "https://github.com/aws-samples/recipes",
        "Bug Reports": "https://github.com/aws-samples/recipes/issues",
        "AWS Transfer Family": "https://aws.amazon.com/aws-transfer-family/",
        "AWS CDK": "https://aws.amazon.com/cdk/",
    },
    
    # License
    license="MIT",
    
    # Zip safety
    zip_safe=False,
)