"""
Setup configuration for the Multi-Region Backup Strategies CDK Python application.

This setup.py file defines the package configuration and dependencies
for the AWS CDK Python application that implements multi-region backup
strategies using AWS Backup.
"""

import setuptools
from typing import List


def read_requirements() -> List[str]:
    """
    Read requirements from requirements.txt file.
    
    Returns:
        List of requirement strings
    """
    try:
        with open("requirements.txt", "r", encoding="utf-8") as fp:
            requirements = []
            for line in fp:
                line = line.strip()
                # Skip empty lines and comments
                if line and not line.startswith("#"):
                    # Remove inline comments
                    requirement = line.split("#")[0].strip()
                    if requirement:
                        requirements.append(requirement)
            return requirements
    except FileNotFoundError:
        # Fallback requirements if file doesn't exist
        return [
            "aws-cdk-lib>=2.150.0,<3.0.0",
            "constructs>=10.3.0,<11.0.0",
            "boto3>=1.34.0"
        ]


def read_long_description() -> str:
    """
    Read the long description from README.md if available.
    
    Returns:
        Long description string
    """
    try:
        with open("README.md", "r", encoding="utf-8") as fp:
            return fp.read()
    except FileNotFoundError:
        return """
        AWS CDK Python application for implementing multi-region backup strategies 
        using AWS Backup with cross-region copy, lifecycle policies, and automated monitoring.
        """


setuptools.setup(
    name="multi-region-backup-cdk",
    version="1.0.0",
    description="AWS CDK application for multi-region backup strategies using AWS Backup",
    long_description=read_long_description(),
    long_description_content_type="text/markdown",
    author="AWS CDK Generator",
    author_email="devops@example.com",
    url="https://github.com/your-org/multi-region-backup-cdk",
    
    # Package configuration
    packages=setuptools.find_packages(),
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=read_requirements(),
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.9.0",
            "mypy>=1.6.0",
            "flake8>=6.1.0",
        ],
        "security": [
            "cdk-nag>=2.27.0",
        ]
    },
    
    # Package classification
    classifiers=[
        "Development Status :: 5 - Production/Stable",
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
        "Topic :: System :: Archiving :: Backup",
        "Topic :: System :: Systems Administration",
        "Framework :: AWS CDK",
        "Framework :: AWS CDK :: 2",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "backup",
        "multi-region",
        "disaster-recovery",
        "infrastructure-as-code",
        "cloud",
        "devops"
    ],
    
    # Entry points for CLI tools (optional)
    entry_points={
        "console_scripts": [
            "multi-region-backup=app:main",
        ],
    },
    
    # Include additional files in package
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # Project URLs for PyPI
    project_urls={
        "Bug Reports": "https://github.com/your-org/multi-region-backup-cdk/issues",
        "Source": "https://github.com/your-org/multi-region-backup-cdk",
        "Documentation": "https://github.com/your-org/multi-region-backup-cdk/wiki",
    },
    
    # License
    license="MIT",
    
    # Zip safety - CDK applications should be zip-safe
    zip_safe=True,
)