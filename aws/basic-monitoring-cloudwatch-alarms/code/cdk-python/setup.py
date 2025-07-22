"""
Setup script for the Basic CloudWatch Monitoring CDK Application.

This script configures the Python package for the AWS CDK application that
creates a complete monitoring solution using Amazon CloudWatch and SNS.
"""

import pathlib
from setuptools import setup, find_packages

# Get the long description from the README file
HERE = pathlib.Path(__file__).parent
README = (HERE / "README.md").read_text() if (HERE / "README.md").exists() else ""

# Read requirements from requirements.txt
with open("requirements.txt", "r", encoding="utf-8") as fh:
    requirements = [line.strip() for line in fh if line.strip() and not line.startswith("#")]

setup(
    name="basic-monitoring-cloudwatch-alarms",
    version="1.0.0",
    description="AWS CDK Python application for basic CloudWatch monitoring with alarms",
    long_description=README,
    long_description_content_type="text/markdown",
    author="AWS CDK Team",
    author_email="aws-cdk-dev@amazon.com",
    url="https://github.com/aws/aws-cdk",
    project_urls={
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Source": "https://github.com/aws/aws-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
    },
    packages=find_packages(exclude=["tests*"]),
    python_requires=">=3.8",
    install_requires=requirements,
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "bandit>=1.7.0",
            "pre-commit>=3.0.0",
            "sphinx>=7.0.0",
            "sphinx-rtd-theme>=1.3.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "pytest-mock>=3.10.0",
            "pytest-html>=4.1.0",
            "moto>=5.0.0",
            "faker>=19.12.0",
            "freezegun>=1.2.0",
            "responses>=0.23.0",
        ],
        "docs": [
            "sphinx>=7.0.0",
            "sphinx-rtd-theme>=1.3.0",
            "sphinx-autodoc-typehints>=1.24.0",
            "myst-parser>=2.0.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "basic-monitoring=app:main",
        ],
    },
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
        "Topic :: System :: Monitoring",
        "Topic :: System :: Systems Administration",
        "Topic :: Utilities",
        "Typing :: Typed",
    ],
    keywords=[
        "aws",
        "cdk",
        "cloudwatch",
        "monitoring",
        "alarms",
        "sns",
        "notifications",
        "infrastructure",
        "devops",
        "automation",
    ],
    license="Apache-2.0",
    platforms=["any"],
    zip_safe=False,
    include_package_data=True,
    package_data={
        "": ["*.txt", "*.md", "*.json", "*.yaml", "*.yml"],
    },
)