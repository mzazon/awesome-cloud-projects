"""
Setup configuration for Amazon Connect Contact Center CDK Application

This setup.py file configures the Python package for the CDK application that deploys
a complete Amazon Connect contact center solution with storage, monitoring, and analytics.

Author: AWS CDK Python Application Generator
Version: 1.0
"""

import pathlib
from typing import List

import setuptools


def read_requirements(filename: str) -> List[str]:
    """Read requirements from requirements.txt file."""
    requirements_path = pathlib.Path(__file__).parent / filename
    with open(requirements_path, encoding="utf-8") as requirements_file:
        return [
            line.strip()
            for line in requirements_file
            if line.strip() and not line.startswith("#")
        ]


def read_readme() -> str:
    """Read the README file for long description."""
    readme_path = pathlib.Path(__file__).parent / "README.md"
    if readme_path.exists():
        with open(readme_path, encoding="utf-8") as readme_file:
            return readme_file.read()
    return "Amazon Connect Contact Center Solution CDK Application"


# Package configuration
setuptools.setup(
    name="contact-center-cdk",
    version="1.0.0",
    
    description="Amazon Connect Contact Center Solution CDK Application",
    long_description=read_readme(),
    long_description_content_type="text/markdown",
    
    author="AWS CDK Python Application Generator",
    author_email="contact@example.com",
    
    package_dir={"": "."},
    packages=setuptools.find_packages(where="."),
    
    install_requires=read_requirements("requirements.txt"),
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Communications :: Telephony",
        "Topic :: Office/Business :: Office Suites",
    ],
    
    keywords=[
        "aws",
        "cdk",
        "amazon-connect",
        "contact-center",
        "telephony",
        "customer-service",
        "cloud",
        "infrastructure",
        "s3",
        "cloudwatch",
        "iam"
    ],
    
    project_urls={
        "Source": "https://github.com/example/contact-center-cdk",
        "Bug Reports": "https://github.com/example/contact-center-cdk/issues",
        "Documentation": "https://github.com/example/contact-center-cdk/wiki",
    },
    
    entry_points={
        "console_scripts": [
            "contact-center-deploy=app:main",
        ],
    },
    
    include_package_data=True,
    zip_safe=False,
)