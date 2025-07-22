"""
Setup configuration for Privacy-Preserving Data Analytics CDK Python application.

This setup file configures the Python package for AWS CDK deployment of
privacy-preserving data analytics infrastructure using AWS Clean Rooms,
Glue, and QuickSight services.
"""

import setuptools
from typing import List


def read_requirements() -> List[str]:
    """Read requirements from requirements.txt file."""
    try:
        with open("requirements.txt", "r", encoding="utf-8") as file:
            requirements = [
                line.strip()
                for line in file.readlines()
                if line.strip() and not line.startswith("#")
            ]
        return requirements
    except FileNotFoundError:
        # Fallback requirements if file is not found
        return [
            "aws-cdk-lib>=2.160.0",
            "constructs>=10.0.0",
            "boto3>=1.35.0",
        ]


def read_long_description() -> str:
    """Read long description from README file."""
    try:
        with open("README.md", "r", encoding="utf-8") as file:
            return file.read()
    except FileNotFoundError:
        return """
        AWS CDK Python application for building privacy-preserving data analytics
        infrastructure using AWS Clean Rooms, Glue, and QuickSight.
        
        This application creates secure multi-party data collaboration environments
        with differential privacy protections and interactive visualization capabilities.
        """


setuptools.setup(
    name="privacy-preserving-analytics-cdk",
    version="1.0.0",
    description="AWS CDK Python app for Privacy-Preserving Data Analytics with Clean Rooms",
    long_description=read_long_description(),
    long_description_content_type="text/markdown",
    author="AWS Cloud Team",
    author_email="cloud-team@example.com",
    python_requires=">=3.8",
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Code Generators",
        "Topic :: Utilities",
        "Typing :: Typed",
    ],
    install_requires=read_requirements(),
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.5.0",
            "pre-commit>=3.0.0",
        ],
        "docs": [
            "sphinx>=7.0.0",
            "sphinx-rtd-theme>=1.3.0",
        ],
    },
    py_modules=["app"],
    entry_points={
        "console_scripts": [
            "deploy-privacy-analytics=app:main",
        ],
    },
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/clean-rooms/",
        "Source": "https://github.com/aws-samples/privacy-preserving-analytics",
        "Bug Reports": "https://github.com/aws-samples/privacy-preserving-analytics/issues",
    },
    keywords=[
        "aws",
        "cdk",
        "clean-rooms",
        "privacy",
        "analytics",
        "differential-privacy",
        "data-collaboration",
        "quicksight",
        "glue",
        "infrastructure-as-code",
    ],
    include_package_data=True,
    zip_safe=False,
)