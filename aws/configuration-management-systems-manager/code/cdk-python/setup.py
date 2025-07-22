"""
Setup configuration for AWS Systems Manager State Manager CDK Python application.

This setup.py file configures the Python package for the CDK application that
implements configuration management using AWS Systems Manager State Manager.
"""

from setuptools import setup, find_packages

# Read the README file for long description
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "AWS Systems Manager State Manager Configuration Management CDK Application"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file."""
    try:
        with open("requirements.txt", "r", encoding="utf-8") as f:
            return [line.strip() for line in f if line.strip() and not line.startswith("#")]
    except FileNotFoundError:
        return [
            "aws-cdk-lib>=2.114.1",
            "constructs>=10.0.0,<11.0.0",
            "boto3>=1.34.0",
            "botocore>=1.34.0",
        ]

setup(
    name="ssm-state-manager-cdk",
    version="1.0.0",
    description="AWS CDK Python application for Systems Manager State Manager configuration management",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS Recipe Generator",
    author_email="your-email@example.com",
    url="https://github.com/your-org/aws-recipes",
    packages=find_packages(),
    include_package_data=True,
    python_requires=">=3.8",
    install_requires=read_requirements(),
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.5.0",
            "types-boto3>=1.0.0",
        ]
    },
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Utilities",
    ],
    keywords="aws cdk python systems-manager state-manager configuration-management compliance automation",
    project_urls={
        "Bug Reports": "https://github.com/your-org/aws-recipes/issues",
        "Source": "https://github.com/your-org/aws-recipes",
        "Documentation": "https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-state.html",
    },
    entry_points={
        "console_scripts": [
            "deploy-state-manager=app:main",
        ],
    },
)