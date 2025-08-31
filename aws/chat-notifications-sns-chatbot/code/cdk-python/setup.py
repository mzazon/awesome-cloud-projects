"""
Setup configuration for the Chat Notifications CDK Python application.

This setup.py file defines the package metadata and dependencies for the
CDK application that creates chat notifications using AWS SNS and Chatbot.
The application enables teams to receive AWS alerts directly in Slack or Teams.
"""

import os
import re
from typing import List

import setuptools


def read_file(file_path: str) -> str:
    """Read the contents of a file safely."""
    try:
        with open(file_path, "r", encoding="utf-8") as fh:
            return fh.read()
    except FileNotFoundError:
        return ""


def get_requirements() -> List[str]:
    """Extract requirements from requirements.txt file."""
    requirements_content = read_file("requirements.txt")
    if not requirements_content:
        # Fallback to basic requirements if file is missing
        return [
            "aws-cdk-lib>=2.150.0,<3.0.0",
            "constructs>=10.3.0,<11.0.0"
        ]
    
    requirements = []
    for line in requirements_content.split('\n'):
        line = line.strip()
        # Skip empty lines and comments
        if line and not line.startswith('#'):
            requirements.append(line)
    
    return requirements


def get_version() -> str:
    """Extract version from package or use default."""
    # Try to read version from __init__.py if it exists
    init_file = read_file("__init__.py")
    if init_file:
        version_match = re.search(r"^__version__ = ['\"]([^'\"]*)['\"]", init_file, re.M)
        if version_match:
            return version_match.group(1)
    
    # Default version
    return "1.0.0"


# Read the contents of README file for long description
long_description = read_file("README.md")
if not long_description:
    long_description = """
    # Chat Notifications CDK Python Application
    
    This CDK application creates the infrastructure needed for AWS chat notifications
    using Amazon SNS and AWS Chatbot. It enables teams to receive real-time alerts
    from AWS services directly in their Slack or Microsoft Teams channels.
    
    ## Features
    
    - Encrypted SNS topic for secure message delivery
    - CloudWatch alarm for testing and demonstration
    - IAM roles with least-privilege permissions for Chatbot
    - Comprehensive outputs for manual configuration steps
    
    ## Prerequisites
    
    - AWS CDK v2 installed
    - Python 3.8 or later
    - AWS CLI configured with appropriate permissions
    - Active Slack workspace or Microsoft Teams
    """

setuptools.setup(
    name="chat-notifications-cdk",
    version=get_version(),
    
    # Author information
    author="AWS Solutions Architect",
    author_email="solutions-architect@example.com",
    
    # Package description
    description="CDK Python application for AWS Chat Notifications with SNS and Chatbot",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    # Project URLs
    url="https://github.com/aws-samples/chat-notifications-cdk",
    
    # Package discovery
    packages=setuptools.find_packages(exclude=["tests", "tests.*"]),
    
    # Dependencies
    install_requires=get_requirements(),
    
    # Python version requirement
    python_requires=">=3.8",
    
    # PyPI classifiers
    classifiers=[
        # Development status
        "Development Status :: 4 - Beta",
        
        # Intended audience
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "Intended Audience :: Information Technology",
        
        # Topic categories
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: System :: Monitoring",
        "Topic :: Communications :: Chat",
        "Topic :: System :: Systems Administration",
        
        # License
        "License :: OSI Approved :: MIT License",
        
        # Python versions
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        
        # Operating system
        "Operating System :: OS Independent",
        
        # Framework
        "Framework :: AWS CDK",
        "Framework :: AWS CDK :: 2",
        
        # Environment
        "Environment :: Console",
        "Natural Language :: English",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws", "cdk", "python", "sns", "chatbot", "notifications", 
        "devops", "infrastructure", "slack", "teams", "monitoring",
        "alerts", "chat", "communication", "cloudwatch"
    ],
    
    # Project URLs for metadata
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/chat-notifications-cdk/issues",
        "Source": "https://github.com/aws-samples/chat-notifications-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "AWS CDK": "https://aws.amazon.com/cdk/",
        "AWS SNS": "https://aws.amazon.com/sns/",
        "AWS Chatbot": "https://aws.amazon.com/chatbot/",
        "Changelog": "https://github.com/aws-samples/chat-notifications-cdk/blob/main/CHANGELOG.md",
    },
    
    # Entry points for command line tools (if needed)
    entry_points={
        "console_scripts": [
            # Uncomment if you want to provide CLI commands
            # "chat-notifications=app:main",
        ],
    },
    
    # Additional package data
    package_data={
        "": [
            "*.md", 
            "*.txt", 
            "*.json", 
            "*.yaml", 
            "*.yml",
            "cdk.json",
            "requirements.txt"
        ],
    },
    
    # Include additional files in the package
    include_package_data=True,
    
    # Zip safety
    zip_safe=False,
    
    # Options for different Python implementations
    options={
        "bdist_wheel": {
            "universal": False,  # This is a Python 3 only package
        }
    },
    
    # Test suite configuration
    test_suite="tests",
    
    # Additional metadata
    platforms=["any"],
    license="MIT",
    
    # Extras require for development
    extras_require={
        "dev": [
            "pytest>=8.0.0",
            "pytest-cov>=4.0.0", 
            "black>=24.0.0",
            "flake8>=7.0.0",
            "mypy>=1.8.0",
            "types-setuptools",
        ],
        "docs": [
            "sphinx>=7.0.0",
            "sphinx-rtd-theme>=2.0.0",
        ],
        "aws": [
            "boto3>=1.34.0",
            "boto3-stubs[sns,cloudwatch,iam]>=1.34.0",
        ]
    }
)