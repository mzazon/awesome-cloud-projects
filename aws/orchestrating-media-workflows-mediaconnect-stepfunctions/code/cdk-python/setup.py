"""
Setup configuration for AWS CDK Python Media Workflow application.

This module defines the package configuration for the Media Workflow CDK stack,
including dependencies, metadata, and entry points.
"""

import setuptools
from pathlib import Path

# Read the long description from README if it exists
long_description = "AWS CDK Python application for Orchestrating Media Workflows with MediaConnect and Step Functions"
readme_path = Path(__file__).parent / "README.md"
if readme_path.exists():
    with open(readme_path, "r", encoding="utf-8") as fh:
        long_description = fh.read()

# Read requirements from requirements.txt
requirements_path = Path(__file__).parent / "requirements.txt"
install_requires = []
if requirements_path.exists():
    with open(requirements_path, "r", encoding="utf-8") as fh:
        install_requires = [
            line.strip() 
            for line in fh.readlines() 
            if line.strip() and not line.startswith("#")
        ]

setuptools.setup(
    name="media-workflow-cdk",
    version="1.0.0",
    author="AWS CDK Team",
    author_email="aws-cdk-dev@amazon.com",
    description="CDK Python app for Orchestrating Media Workflows with MediaConnect and Step Functions",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws/aws-cdk",
    project_urls={
        "Source": "https://github.com/aws/aws-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
    },
    packages=setuptools.find_packages(),
    py_modules=["app"],
    install_requires=install_requires,
    python_requires=">=3.8",
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Typing :: Typed",
    ],
    keywords=[
        "aws",
        "cdk",
        "python",
        "mediaconnect",
        "stepfunctions",
        "media",
        "streaming",
        "workflow",
        "cloudformation",
        "infrastructure",
        "lambda",
        "cloudwatch",
        "sns",
        "eventbridge"
    ],
    entry_points={
        "console_scripts": [
            "media-workflow=app:main",
        ],
    },
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "pre-commit>=3.0.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",
        ],
    },
    include_package_data=True,
    zip_safe=False,
    license="Apache-2.0",
)