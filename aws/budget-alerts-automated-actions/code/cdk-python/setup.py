"""
Setup configuration for AWS Budget Alerts CDK Python application.

This package provides Infrastructure as Code (IaC) for implementing
comprehensive budget monitoring and automated cost control actions
using AWS CDK Python.
"""

import setuptools
from pathlib import Path

# Read the README file for long description
readme_path = Path(__file__).parent / "README.md"
long_description = ""
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
    name="budget-alerts-automated-actions",
    version="1.0.0",
    
    description="AWS CDK Python application for budget alerts and automated cost control actions",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS Solutions Architect",
    author_email="solutions@amazon.com",
    url="https://github.com/aws-samples/budget-alerts-cdk-python",
    
    package_dir={"": "."},
    packages=setuptools.find_packages(where="."),
    
    install_requires=install_requires,
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Office/Business :: Financial",
        "Typing :: Typed",
    ],
    
    keywords=[
        "aws", "cdk", "budget", "cost-control", "finops", 
        "automation", "lambda", "sns", "iam", "cloudformation"
    ],
    
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws-samples/budget-alerts-cdk-python",
        "Bug Reports": "https://github.com/aws-samples/budget-alerts-cdk-python/issues",
        "AWS CDK": "https://aws.amazon.com/cdk/",
        "AWS Budgets": "https://aws.amazon.com/aws-cost-management/aws-budgets/",
    },
    
    # Entry points for CLI commands
    entry_points={
        "console_scripts": [
            "budget-alerts-deploy=app:main",
        ],
    },
    
    # Additional package metadata
    include_package_data=True,
    zip_safe=False,
    
    # Testing configuration
    extras_require={
        "dev": [
            "pytest>=7.1.0",
            "pytest-cov>=4.0.0",
            "mypy>=1.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "isort>=5.10.0",
        ],
        "docs": [
            "sphinx>=5.3.0",
            "sphinx-rtd-theme>=1.2.0",
        ],
    },
)