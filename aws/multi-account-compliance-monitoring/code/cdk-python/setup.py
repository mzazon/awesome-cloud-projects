"""
Setup configuration for the Cross-Account Compliance Monitoring CDK application.

This setup.py file configures the Python package for the CDK application that
implements cross-account compliance monitoring with AWS Systems Manager and Security Hub.
"""

from setuptools import setup, find_packages

# Read the README file for long description
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "Cross-Account Compliance Monitoring with AWS Systems Manager and Security Hub"

# Read requirements from requirements.txt
try:
    with open("requirements.txt", "r", encoding="utf-8") as fh:
        requirements = [line.strip() for line in fh if line.strip() and not line.startswith("#")]
except FileNotFoundError:
    requirements = [
        "aws-cdk-lib>=2.166.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "typing-extensions>=4.0.0",
    ]

setup(
    name="compliance-monitoring-cdk",
    version="1.0.0",
    description="CDK Python application for cross-account compliance monitoring with AWS Systems Manager and Security Hub",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS Solutions Architecture",
    author_email="support@aws.com",
    url="https://github.com/aws-samples/compliance-monitoring-cdk",
    
    # Package configuration
    packages=find_packages(exclude=["tests*"]),
    include_package_data=True,
    zip_safe=False,
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=requirements,
    
    # Development dependencies
    extras_require={
        "dev": [
            "black>=23.0.0",
            "pylint>=3.0.0",
            "mypy>=1.0.0",
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
        ],
        "docs": [
            "sphinx>=6.0.0",
            "sphinx-rtd-theme>=1.3.0",
        ],
    },
    
    # Entry points for command-line scripts
    entry_points={
        "console_scripts": [
            "cdk-compliance-monitoring=app:main",
        ],
    },
    
    # Package classification
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: OS Independent",
        "Programming Language :: Python",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Security",
        "Topic :: System :: Systems Administration",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Framework :: AWS CDK",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "compliance",
        "security-hub",
        "systems-manager",
        "cross-account",
        "monitoring",
        "security",
        "governance",
        "infrastructure-as-code",
    ],
    
    # Project metadata
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws-samples/compliance-monitoring-cdk",
        "Bug Reports": "https://github.com/aws-samples/compliance-monitoring-cdk/issues",
        "AWS CDK": "https://aws.amazon.com/cdk/",
        "AWS Security Hub": "https://aws.amazon.com/security-hub/",
        "AWS Systems Manager": "https://aws.amazon.com/systems-manager/",
    },
    
    # License information
    license="Apache License 2.0",
    license_files=["LICENSE"],
)