#!/usr/bin/env python3
"""
Setup configuration for the AWS CDK Python application for S3 Cross-Region Replication disaster recovery.

This setup.py file configures the Python package for the CDK application, defining
metadata, dependencies, and installation requirements.
"""

import setuptools

# Read the long description from README if it exists
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "AWS CDK Python application for S3 Cross-Region Replication disaster recovery solution"

# Read requirements from requirements.txt
def parse_requirements(filename):
    """Parse requirements from requirements.txt file."""
    requirements = []
    try:
        with open(filename, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                # Skip empty lines and comments
                if line and not line.startswith('#'):
                    # Remove inline comments
                    if '#' in line:
                        line = line.split('#')[0].strip()
                    requirements.append(line)
    except FileNotFoundError:
        # Fallback requirements if file doesn't exist
        requirements = [
            "aws-cdk-lib>=2.120.0,<3.0.0",
            "constructs>=10.0.0,<11.0.0",
            "typing-extensions>=4.0.0"
        ]
    return requirements

setuptools.setup(
    name="disaster-recovery-s3-cdk",
    version="1.0.0",
    
    description="AWS CDK Python application for S3 Cross-Region Replication disaster recovery",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS Solutions",
    author_email="aws-solutions@amazon.com",
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Code Generators",
        "Topic :: Utilities",
        "Topic :: System :: Disaster Recovery",
        "Topic :: System :: Archiving :: Backup",
    ],
    
    install_requires=parse_requirements("requirements.txt"),
    
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0", 
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "isort>=5.0.0"
        ]
    },
    
    py_modules=["app"],
    
    entry_points={
        "console_scripts": [
            "disaster-recovery-s3=app:main",
        ],
    },
    
    keywords=[
        "aws",
        "cdk", 
        "s3",
        "disaster-recovery",
        "cross-region-replication",
        "backup",
        "infrastructure-as-code",
        "cloud",
        "devops"
    ],
    
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "AWS S3 Documentation": "https://docs.aws.amazon.com/s3/",
        "CDK Python Reference": "https://docs.aws.amazon.com/cdk/api/v2/python/",
    },
    
    package_data={
        "": ["*.md", "*.txt", "*.json"],
    },
    
    include_package_data=True,
    zip_safe=False,
)