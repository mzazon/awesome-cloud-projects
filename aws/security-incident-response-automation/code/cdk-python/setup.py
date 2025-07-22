"""
Setup configuration for AWS CDK Python Security Incident Response Application

This setup.py file configures the Python package for the automated security
incident response system built with AWS CDK. The application deploys Security Hub,
EventBridge, Lambda, and SNS resources for comprehensive security automation.
"""

import os
from setuptools import setup, find_packages

# Read the README file for the long description
def read_readme():
    """Read README.md file for package description"""
    readme_path = os.path.join(os.path.dirname(__file__), "README.md")
    if os.path.exists(readme_path):
        with open(readme_path, "r", encoding="utf-8") as f:
            return f.read()
    return "AWS CDK Python application for automated security incident response"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements.txt file for package dependencies"""
    requirements_path = os.path.join(os.path.dirname(__file__), "requirements.txt")
    if os.path.exists(requirements_path):
        with open(requirements_path, "r", encoding="utf-8") as f:
            return [
                line.strip() 
                for line in f 
                if line.strip() and not line.startswith("#")
            ]
    return [
        "aws-cdk-lib>=2.100.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
    ]

setup(
    name="security-incident-response-cdk",
    version="1.0.0",
    description="AWS CDK Python application for automated security incident response with Security Hub",
    long_description=read_readme(),
    long_description_content_type="text/markdown",
    
    # Author information
    author="AWS CDK Generator",
    author_email="security-team@company.com",
    
    # Package configuration
    packages=find_packages(exclude=["tests*"]),
    include_package_data=True,
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Package dependencies
    install_requires=read_requirements(),
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
        ],
        "testing": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",  # AWS service mocking for tests
        ],
    },
    
    # Package classification
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: System Administrators",
        "Intended Audience :: Developers",
        "Topic :: System :: Systems Administration",
        "Topic :: Security",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Operating System :: OS Independent",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "security",
        "incident-response",
        "security-hub",
        "lambda",
        "eventbridge",
        "automation",
        "infrastructure",
        "cloud",
    ],
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "Security Hub": "https://docs.aws.amazon.com/securityhub/",
        "EventBridge": "https://docs.aws.amazon.com/eventbridge/",
        "Lambda": "https://docs.aws.amazon.com/lambda/",
    },
    
    # Entry points for CLI commands
    entry_points={
        "console_scripts": [
            "deploy-security-incident-response=app:main",
        ],
    },
    
    # Package data
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # Zip safety
    zip_safe=False,
)