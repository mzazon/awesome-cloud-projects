"""
Setup configuration for Business Notifications CDK Application.

This setup.py file configures the Python package for the CDK application that creates
a serverless business notification system using EventBridge Scheduler and SNS.

Author: AWS CDK Generator v2.0
Recipe: Scheduling Notifications with EventBridge and SNS
"""

import setuptools
from typing import List


def get_requirements() -> List[str]:
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
        # Fallback requirements if file doesn't exist
        return [
            "aws-cdk-lib>=2.160.0,<3.0.0",
            "constructs>=10.0.0,<11.0.0",
            "typing-extensions>=4.0.0",
        ]


def get_long_description() -> str:
    """
    Get long description from README or provide default.
    
    Returns:
        str: Long description for the package
    """
    try:
        with open("README.md", "r", encoding="utf-8") as f:
            return f.read()
    except FileNotFoundError:
        return """
# Business Notifications CDK Application

This AWS CDK application creates a serverless notification system using EventBridge Scheduler
and Amazon SNS to automatically send business notifications on predefined schedules.

## Features

- **Automated Scheduling**: Uses EventBridge Scheduler for precise timing control
- **Reliable Delivery**: SNS ensures message delivery with built-in retry mechanisms  
- **Multiple Schedules**: Daily, weekly, and monthly notification schedules
- **Enterprise Security**: IAM roles with least privilege permissions
- **Cost Effective**: Serverless architecture with pay-per-use pricing
- **Scalable**: Handles growth from startup to enterprise scale

## Architecture

The solution includes:
- SNS Topic for business notifications
- IAM Role for EventBridge Scheduler execution  
- Schedule Group for organizing business schedules
- Multiple schedules for different business cadences

## Deployment

```bash
# Install dependencies
pip install -r requirements.txt

# Deploy the stack
cdk deploy

# Optionally specify notification email
cdk deploy -c notification_email=user@company.com
```
"""


setuptools.setup(
    name="business-notifications-cdk",
    version="1.0.0",
    author="AWS CDK Generator",
    author_email="example@example.com",
    description="CDK application for automated business notifications using EventBridge Scheduler and SNS",
    long_description=get_long_description(),
    long_description_content_type="text/markdown",
    url="https://github.com/example/business-notifications-cdk",
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/example/business-notifications-cdk",
        "Tracker": "https://github.com/example/business-notifications-cdk/issues",
    },
    packages=setuptools.find_packages(),
    install_requires=get_requirements(),
    python_requires=">=3.8",
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
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: Internet",
        "Topic :: System :: Networking",
        "Topic :: System :: Systems Administration",
        "Typing :: Typed",
    ],
    keywords=[
        "aws",
        "cdk",
        "eventbridge",
        "scheduler", 
        "sns",
        "notifications",
        "serverless",
        "business",
        "automation",
        "infrastructure",
        "cloud",
    ],
    entry_points={
        "console_scripts": [
            "business-notifications=app:main",
        ],
    },
    include_package_data=True,
    zip_safe=False,
)