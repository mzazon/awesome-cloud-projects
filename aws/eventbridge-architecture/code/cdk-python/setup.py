#!/usr/bin/env python3
"""
Setup configuration for EventBridge Event-Driven Architecture CDK application

This setup.py file configures the Python package for the CDK application,
including dependencies, metadata, and installation requirements.
"""

from setuptools import setup, find_packages

# Read the README file for long description
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "EventBridge Event-Driven Architecture CDK Application"

# Define package metadata
PACKAGE_NAME = "event-driven-architecture-cdk"
VERSION = "1.0.0"
DESCRIPTION = "CDK application for EventBridge event-driven architecture"
AUTHOR = "Cloud Architecture Team"
AUTHOR_EMAIL = "cloud-team@example.com"
URL = "https://github.com/example/event-driven-architecture-cdk"

# Define dependencies
install_requires = [
    "aws-cdk-lib>=2.140.0,<3.0.0",
    "constructs>=10.0.0,<11.0.0",
    "boto3>=1.34.0",
    "typing-extensions>=4.5.0",
]

# Define development dependencies
extras_require = {
    "dev": [
        "pytest>=7.0.0",
        "pytest-cov>=4.0.0",
        "black>=23.0.0",
        "flake8>=6.0.0",
        "mypy>=1.0.0",
        "aws-lambda-powertools>=2.0.0",
    ],
    "test": [
        "pytest>=7.0.0",
        "pytest-cov>=4.0.0",
        "moto>=4.0.0",  # For mocking AWS services in tests
    ],
}

# Python version requirements
python_requires = ">=3.8"

# Package classifiers
classifiers = [
    "Development Status :: 5 - Production/Stable",
    "Intended Audience :: Developers",
    "License :: OSI Approved :: MIT License",
    "Programming Language :: Python :: 3",
    "Programming Language :: Python :: 3.8",
    "Programming Language :: Python :: 3.9",
    "Programming Language :: Python :: 3.10",
    "Programming Language :: Python :: 3.11",
    "Topic :: Software Development :: Libraries :: Python Modules",
    "Topic :: System :: Systems Administration",
    "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
]

# Setup configuration
setup(
    name=PACKAGE_NAME,
    version=VERSION,
    description=DESCRIPTION,
    long_description=long_description,
    long_description_content_type="text/markdown",
    author=AUTHOR,
    author_email=AUTHOR_EMAIL,
    url=URL,
    packages=find_packages(exclude=["tests", "tests.*"]),
    include_package_data=True,
    python_requires=python_requires,
    install_requires=install_requires,
    extras_require=extras_require,
    classifiers=classifiers,
    keywords=[
        "aws",
        "cdk",
        "eventbridge",
        "lambda",
        "sns",
        "sqs",
        "event-driven",
        "architecture",
        "microservices",
        "serverless",
    ],
    project_urls={
        "Bug Reports": f"{URL}/issues",
        "Source": URL,
        "Documentation": f"{URL}/blob/main/README.md",
    },
    entry_points={
        "console_scripts": [
            "deploy-event-architecture=app:main",
        ],
    },
    # Package data to include
    package_data={
        "": ["*.md", "*.txt", "*.yml", "*.yaml"],
    },
    # Data files to include in installation
    data_files=[
        ("", ["requirements.txt"]),
    ],
    # Zip safe flag
    zip_safe=False,
)

# Additional setup for CDK-specific requirements
if __name__ == "__main__":
    print(f"Setting up {PACKAGE_NAME} v{VERSION}")
    print("=" * 50)
    print(f"Description: {DESCRIPTION}")
    print(f"Author: {AUTHOR}")
    print(f"Python: {python_requires}")
    print("=" * 50)
    print("Run 'pip install -e .' to install in development mode")
    print("Run 'pip install -e .[dev]' to install with development dependencies")
    print("Run 'cdk deploy' to deploy the infrastructure")
    print("=" * 50)