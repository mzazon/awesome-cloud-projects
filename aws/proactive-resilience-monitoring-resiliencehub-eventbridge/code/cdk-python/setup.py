"""
Setup configuration for the AWS CDK Python Resilience Monitoring Application.

This setup.py file configures the Python package for the CDK application that
deploys proactive application resilience monitoring with AWS Resilience Hub
and EventBridge integration.
"""

import setuptools
from typing import List


def _read_long_description() -> str:
    """Read the long description from README if available."""
    try:
        with open("README.md", "r", encoding="utf-8") as fh:
            return fh.read()
    except FileNotFoundError:
        return "AWS CDK Python application for proactive resilience monitoring"


def _read_requirements() -> List[str]:
    """Read requirements from requirements.txt file."""
    try:
        with open("requirements.txt", "r", encoding="utf-8") as fh:
            return [
                line.strip()
                for line in fh.readlines()
                if line.strip() and not line.startswith("#")
            ]
    except FileNotFoundError:
        return [
            "aws-cdk-lib>=2.150.0,<3.0.0",
            "constructs>=10.0.0,<11.0.0",
            "boto3>=1.34.0",
        ]


setuptools.setup(
    name="resilience-monitoring-cdk",
    version="1.0.0",
    author="AWS CDK Developer",
    author_email="developer@example.com",
    description="AWS CDK Python application for proactive application resilience monitoring",
    long_description=_read_long_description(),
    long_description_content_type="text/markdown",
    url="https://github.com/aws/aws-cdk",
    packages=setuptools.find_packages(),
    classifiers=[
        "Development Status :: 5 - Production/Stable",
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
    python_requires=">=3.8",
    install_requires=_read_requirements(),
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "boto3-stubs[essential]>=1.34.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "resilience-monitoring-cdk=app:main",
        ],
    },
    project_urls={
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Source": "https://github.com/aws/aws-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
    },
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "resilience",
        "monitoring",
        "eventbridge",
        "lambda",
        "cloudwatch",
        "automation",
    ],
    zip_safe=False,
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.yaml", "*.yml", "*.json"],
    },
)