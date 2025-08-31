"""
Setup configuration for Simple File Backup Notifications CDK Python application.

This setup.py file configures the Python package for the CDK application
that creates an automated notification system for S3 backup file uploads
using SNS email notifications.
"""

import setuptools
from typing import List


def read_requirements() -> List[str]:
    """
    Read requirements from requirements.txt file.
    
    Returns:
        List[str]: List of package requirements
    """
    try:
        with open("requirements.txt", "r", encoding="utf-8") as f:
            requirements = []
            for line in f:
                line = line.strip()
                # Skip empty lines and comments
                if line and not line.startswith("#"):
                    requirements.append(line)
            return requirements
    except FileNotFoundError:
        # Fallback requirements if file not found
        return [
            "aws-cdk-lib>=2.155.0,<3.0.0",
            "constructs>=10.0.0,<11.0.0",
        ]


def read_long_description() -> str:
    """
    Read long description from README file or provide default.
    
    Returns:
        str: Long description for the package
    """
    try:
        with open("README.md", "r", encoding="utf-8") as f:
            return f.read()
    except FileNotFoundError:
        return """
        # Simple File Backup Notifications CDK Application
        
        This CDK application creates an automated notification system using Amazon S3 
        event notifications integrated with Amazon SNS to send instant email alerts 
        whenever files are uploaded to your backup bucket.
        
        ## Features
        - S3 bucket with encryption and versioning
        - SNS topic with email subscription
        - Event-driven notifications for file uploads
        - Cost-optimized lifecycle policies
        - Security best practices implementation
        
        ## Usage
        Deploy with: `cdk deploy`
        """


setuptools.setup(
    # Package metadata
    name="simple-file-backup-notifications-cdk",
    version="1.0.0",
    author="AWS CDK Developer",
    author_email="developer@example.com",
    description="CDK application for automated S3 backup file notifications via SNS",
    long_description=read_long_description(),
    long_description_content_type="text/markdown",
    url="https://github.com/example/simple-file-backup-notifications-cdk",
    
    # Package configuration
    packages=setuptools.find_packages(),
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: System Administrators",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: System :: Archiving :: Backup",
        "Topic :: System :: Monitoring",
        "Topic :: Communications :: Email",
        "Typing :: Typed",
    ],
    
    # Python version requirements
    python_requires=">=3.8",
    
    # Package dependencies
    install_requires=read_requirements(),
    
    # Optional dependencies for development
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "black>=22.0.0",
            "flake8>=4.0.0",
            "mypy>=0.991",
            "boto3>=1.26.0",
        ],
        "docs": [
            "sphinx>=4.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
        "testing": [
            "pytest>=7.0.0",
            "pytest-cov>=3.0.0",
            "moto>=4.0.0",  # For mocking AWS services in tests
        ],
    },
    
    # Entry points for command-line scripts
    entry_points={
        "console_scripts": [
            "deploy-backup-notifications=app:create_app",
        ],
    },
    
    # Include additional files in the package
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/example/simple-file-backup-notifications-cdk/issues",
        "Source": "https://github.com/example/simple-file-backup-notifications-cdk",
        "Documentation": "https://github.com/example/simple-file-backup-notifications-cdk/wiki",
    },
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "s3",
        "sns",
        "notifications",
        "backup",
        "monitoring",
        "cloud",
        "infrastructure",
        "email",
        "event-driven",
        "serverless",
    ],
    
    # Zip safe configuration
    zip_safe=False,
)