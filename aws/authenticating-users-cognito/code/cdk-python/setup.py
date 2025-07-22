"""
Setup configuration for the Cognito User Pools CDK Python application.

This setup file configures the Python package for the user authentication system
using Amazon Cognito User Pools with advanced security features and role-based access control.
"""

import setuptools
from pathlib import Path

# Read the README file for the long description
readme_path = Path(__file__).parent / "README.md"
long_description = readme_path.read_text(encoding="utf-8") if readme_path.exists() else ""

# Read requirements from requirements.txt
requirements_path = Path(__file__).parent / "requirements.txt"
if requirements_path.exists():
    with open(requirements_path, "r", encoding="utf-8") as f:
        requirements = [
            line.strip() 
            for line in f 
            if line.strip() and not line.startswith("#")
        ]
else:
    requirements = [
        "aws-cdk-lib>=2.140.0,<3.0.0",
        "constructs>=10.3.0,<11.0.0",
        "boto3>=1.34.0",
        "botocore>=1.34.0"
    ]

setuptools.setup(
    name="cognito-user-pools-cdk",
    version="1.0.0",
    
    description="AWS CDK Python application for Authenticating Users with Cognito User Pools",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS Solutions Architect",
    author_email="solutions@amazon.com",
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: Internet :: WWW/HTTP",
        "Topic :: Security",
        "Topic :: System :: Systems Administration :: Authentication/Directory",
    ],
    
    keywords=[
        "aws",
        "cdk",
        "cognito",
        "authentication",
        "user-pools",
        "oauth",
        "mfa",
        "security",
        "identity",
        "authorization"
    ],
    
    install_requires=requirements,
    
    extras_require={
        "dev": [
            "mypy>=1.8.0",
            "black>=23.0.0",
            "pylint>=3.0.0",
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "bandit>=1.7.5",  # Security linter
            "safety>=2.3.0",  # Check for known security vulnerabilities
        ],
        "testing": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "moto>=4.2.0",  # Mock AWS services for testing
            "responses>=0.23.0",  # Mock HTTP requests
        ]
    },
    
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cognito/",
        "Source": "https://github.com/aws-samples/aws-cdk-examples",
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "CDK Documentation": "https://docs.aws.amazon.com/cdk/",
    },
    
    entry_points={
        "console_scripts": [
            "cognito-auth-deploy=app:main",
        ],
    },
    
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    include_package_data=True,
    zip_safe=False,
)