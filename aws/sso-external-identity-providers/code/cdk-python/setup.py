"""
Setup configuration for AWS IAM Identity Center (SSO) with External Identity Providers CDK Application

This setup.py file configures the Python package for the CDK application that demonstrates
implementing AWS Single Sign-On (IAM Identity Center) with external identity provider integration.
"""

import os
from pathlib import Path

from setuptools import find_packages, setup

# Read the contents of the README file
this_directory = Path(__file__).parent
long_description = ""
readme_file = this_directory / "README.md"
if readme_file.exists():
    long_description = readme_file.read_text(encoding="utf-8")

# Read requirements from requirements.txt
requirements_file = this_directory / "requirements.txt"
requirements = []
if requirements_file.exists():
    with open(requirements_file, "r", encoding="utf-8") as f:
        requirements = [
            line.strip()
            for line in f
            if line.strip() and not line.startswith("#")
        ]

# Extract version from environment or use default
version = os.environ.get("PACKAGE_VERSION", "1.0.0")

setup(
    name="aws-sso-external-idp-cdk",
    version=version,
    description="AWS CDK Python application for implementing IAM Identity Center with external identity providers",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS CDK Team",
    author_email="aws-cdk@amazon.com",
    url="https://github.com/aws/aws-cdk",
    license="Apache-2.0",
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Code Generators",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: System :: Systems Administration",
        "Typing :: Typed",
    ],
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "sso",
        "identity-center",
        "saml",
        "federation",
        "identity-provider",
        "authentication",
        "authorization",
    ],
    packages=find_packages(exclude=["tests", "tests.*"]),
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    include_package_data=True,
    install_requires=requirements,
    extras_require={
        "dev": [
            "black>=23.0.0,<25.0.0",
            "flake8>=6.0.0,<8.0.0",
            "mypy>=1.8.0,<2.0.0",
            "pytest>=7.4.0,<9.0.0",
            "pytest-cov>=4.1.0,<6.0.0",
            "moto>=4.2.0,<6.0.0",
        ],
        "testing": [
            "pytest>=7.4.0,<9.0.0",
            "pytest-cov>=4.1.0,<6.0.0",
            "moto>=4.2.0,<6.0.0",
            "boto3-stubs[identitystore,iam,organizations,s3,sso,sso-admin]>=1.34.0,<2.0.0",
        ],
    },
    python_requires=">=3.8",
    entry_points={
        "console_scripts": [
            "deploy-sso=app:main",
        ],
    },
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "Tracker": "https://github.com/aws/aws-cdk/issues",
        "AWS CDK Guide": "https://docs.aws.amazon.com/cdk/latest/guide/",
        "AWS IAM Identity Center": "https://docs.aws.amazon.com/singlesignon/latest/userguide/",
        "SAML 2.0 Federation": "https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_saml.html",
    },
    zip_safe=False,
    platforms=["any"],
)