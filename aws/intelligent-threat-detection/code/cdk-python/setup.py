"""
Setup configuration for GuardDuty Threat Detection CDK Application

This setup.py file configures the Python package for the GuardDuty threat detection
CDK application, including dependencies, metadata, and development requirements.
"""

import setuptools
from pathlib import Path

# Read the README file for the long description
README_PATH = Path(__file__).parent / "README.md"
if README_PATH.exists():
    with open(README_PATH, "r", encoding="utf-8") as fh:
        long_description = fh.read()
else:
    long_description = "CDK Python application for GuardDuty threat detection system"

# Read requirements from requirements.txt
REQUIREMENTS_PATH = Path(__file__).parent / "requirements.txt"
if REQUIREMENTS_PATH.exists():
    with open(REQUIREMENTS_PATH, "r", encoding="utf-8") as fh:
        requirements = [
            line.strip() 
            for line in fh.readlines() 
            if line.strip() and not line.startswith("#")
        ]
else:
    requirements = [
        "aws-cdk-lib>=2.130.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.34.0",
    ]

setuptools.setup(
    name="guardduty-threat-detection-cdk",
    version="1.0.0",
    
    # Package metadata
    author="AWS Recipes Team",
    author_email="aws-recipes@example.com",
    description="AWS CDK Python application for comprehensive GuardDuty threat detection",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-recipes/guardduty-threat-detection",
    
    # Package configuration
    packages=setuptools.find_packages(exclude=["tests", "tests.*"]),
    include_package_data=True,
    
    # Dependencies
    install_requires=requirements,
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "boto3-stubs[essential]",
            "types-boto3",
        ]
    },
    
    # Python version requirements
    python_requires=">=3.8",
    
    # Package classifiers
    classifiers=[
        "Development Status :: 5 - Production/Stable",
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
        "Topic :: Security",
        "Topic :: System :: Monitoring",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Framework :: AWS CDK",
    ],
    
    # Entry points for command line tools
    entry_points={
        "console_scripts": [
            "guardduty-cdk=app:main",
        ],
    },
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "guardduty",
        "security",
        "threat-detection",
        "cloudwatch",
        "sns",
        "eventbridge",
        "monitoring",
        "automation"
    ],
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/aws-recipes/guardduty-threat-detection/issues",
        "Source": "https://github.com/aws-recipes/guardduty-threat-detection",
        "Documentation": "https://docs.aws.amazon.com/guardduty/",
        "CDK Documentation": "https://docs.aws.amazon.com/cdk/",
    },
    
    # Package data
    package_data={
        "": [
            "*.md",
            "*.txt",
            "*.json",
            "*.yaml",
            "*.yml",
        ],
    },
    
    # Zip safety
    zip_safe=False,
)