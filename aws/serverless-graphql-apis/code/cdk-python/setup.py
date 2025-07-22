"""
Python package setup configuration for Serverless GraphQL APIs CDK application.

This setup.py file configures the Python package for the CDK application that
implements serverless GraphQL APIs using AWS AppSync and EventBridge Scheduler.
It defines the package metadata, dependencies, and entry points for the application.

Author: CDK Generator v1.3
Version: 1.0
"""

import setuptools
from pathlib import Path

# Read the README file for long description
readme_path = Path(__file__).parent / "README.md"
if readme_path.exists():
    with open(readme_path, "r", encoding="utf-8") as fh:
        long_description = fh.read()
else:
    long_description = "CDK Python application for serverless GraphQL APIs with AWS AppSync and EventBridge Scheduler"

# Read requirements from requirements.txt
requirements_path = Path(__file__).parent / "requirements.txt"
if requirements_path.exists():
    with open(requirements_path, "r", encoding="utf-8") as fh:
        requirements = [
            line.strip() 
            for line in fh.readlines() 
            if line.strip() and not line.startswith("#") and not line.startswith("-")
        ]
else:
    requirements = [
        "aws-cdk-lib>=2.139.0",
        "constructs>=10.0.0",
        "boto3>=1.34.0",
        "typing-extensions>=4.0.0"
    ]

setuptools.setup(
    name="serverless-graphql-apis-cdk",
    version="1.0.0",
    
    # Package metadata
    author="CDK Generator",
    author_email="dev@example.com",
    description="CDK Python application for serverless GraphQL APIs with AWS AppSync and EventBridge Scheduler",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/your-org/serverless-graphql-apis",
    
    # Package configuration
    packages=setuptools.find_packages(),
    package_data={
        "": ["*.graphql", "*.json", "*.yaml", "*.yml"],
    },
    include_package_data=True,
    
    # Dependencies
    install_requires=requirements,
    
    # Python version requirements
    python_requires=">=3.8",
    
    # Package classifiers
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
        "Topic :: Software Development :: Code Generators",
        "Framework :: AWS CDK",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "graphql",
        "appsync",
        "eventbridge",
        "scheduler",
        "serverless",
        "dynamodb",
        "lambda",
        "infrastructure-as-code",
        "cloud-development-kit"
    ],
    
    # Entry points for CLI commands (optional)
    entry_points={
        "console_scripts": [
            "deploy-graphql-api=app:main",
        ],
    },
    
    # Development dependencies (optional)
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "pre-commit>=3.0.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
            "myst-parser>=0.18.0",
        ],
    },
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/your-org/serverless-graphql-apis/issues",
        "Source": "https://github.com/your-org/serverless-graphql-apis",
        "Documentation": "https://docs.example.com/serverless-graphql-apis",
        "AWS CDK": "https://aws.amazon.com/cdk/",
        "AWS AppSync": "https://aws.amazon.com/appsync/",
        "EventBridge": "https://aws.amazon.com/eventbridge/",
    },
    
    # License information
    license="MIT",
    
    # Zip safe configuration
    zip_safe=False,
)