#!/usr/bin/env python3
"""
Setup configuration for Dedicated Hosts License Compliance CDK Application

This setup.py file configures the Python package for the CDK application,
including dependencies, metadata, and development requirements.
"""

import setuptools

# Read README file for long description
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "CDK Python application for AWS Dedicated Hosts License Compliance"

# Read requirements from requirements.txt
with open("requirements.txt", "r", encoding="utf-8") as fh:
    requirements = [
        line.strip() 
        for line in fh 
        if line.strip() and not line.startswith("#")
    ]

setuptools.setup(
    name="dedicated-hosts-license-compliance",
    version="1.0.0",
    
    description="AWS CDK Python application for Dedicated Hosts License Compliance",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS Solutions Architect",
    author_email="solutions@example.com",
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Utilities",
    ],
    
    packages=setuptools.find_packages(),
    
    install_requires=requirements,
    
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cdk>=0.1.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "pre-commit>=2.20.0",
        ],
    },
    
    entry_points={
        "console_scripts": [
            "deploy=app:main",
        ],
    },
    
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "dedicated-hosts",
        "license-compliance",
        "byol",
        "license-manager",
        "ec2",
    ],
    
    project_urls={
        "Bug Reports": "https://github.com/your-org/dedicated-hosts-license-compliance/issues",
        "Source": "https://github.com/your-org/dedicated-hosts-license-compliance",
        "Documentation": "https://github.com/your-org/dedicated-hosts-license-compliance/blob/main/README.md",
    },
    
    include_package_data=True,
    zip_safe=False,
)