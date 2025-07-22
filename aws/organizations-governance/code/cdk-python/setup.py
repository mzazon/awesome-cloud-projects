"""
Setup configuration for Multi-Account Governance CDK Python Application.

This setup.py file configures the Python package for the CDK application
that implements multi-account governance with AWS Organizations and
Service Control Policies.
"""

import setuptools
import os
from pathlib import Path

# Read the README file for long description
readme_path = Path(__file__).parent / "README.md"
if readme_path.exists():
    with open(readme_path, "r", encoding="utf-8") as fh:
        long_description = fh.read()
else:
    long_description = "Multi-Account Governance with AWS Organizations and Service Control Policies CDK Application"

# Read requirements from requirements.txt
requirements_path = Path(__file__).parent / "requirements.txt"
if requirements_path.exists():
    with open(requirements_path, "r", encoding="utf-8") as fh:
        requirements = [
            line.strip()
            for line in fh.readlines()
            if line.strip() and not line.startswith("#")
        ]
else:
    requirements = [
        "aws-cdk-lib>=2.160.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
    ]

setuptools.setup(
    name="multi-account-governance-cdk",
    version="1.0.0",
    author="AWS CDK Recipe",
    author_email="support@example.com",
    description="Multi-Account Governance with AWS Organizations and Service Control Policies",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/example/multi-account-governance-cdk",
    project_urls={
        "Bug Reports": "https://github.com/example/multi-account-governance-cdk/issues",
        "Source": "https://github.com/example/multi-account-governance-cdk",
        "Documentation": "https://docs.aws.amazon.com/organizations/",
    },
    packages=setuptools.find_packages(),
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
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Security",
        "Typing :: Typed",
    ],
    python_requires=">=3.8",
    install_requires=requirements,
    extras_require={
        "dev": [
            "pytest>=6.2.0",
            "pytest-cov>=2.12.0",
            "black>=21.0.0",
            "flake8>=3.9.0",
            "mypy>=0.910",
        ],
        "docs": [
            "sphinx>=4.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "multi-account-governance=app:main",
        ],
    },
    keywords=[
        "aws",
        "cdk",
        "organizations",
        "service-control-policies",
        "governance",
        "multi-account",
        "security",
        "compliance",
        "cloudformation",
        "infrastructure-as-code",
    ],
    zip_safe=False,
    include_package_data=True,
    package_data={
        "": ["*.json", "*.yaml", "*.yml", "*.md", "*.txt"],
    },
)