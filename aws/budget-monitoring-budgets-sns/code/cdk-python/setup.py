"""
Setup configuration for Budget Monitoring CDK Python Application.

This setup.py file configures the Python package for the budget monitoring
CDK application, including dependencies, metadata, and installation requirements.
"""

import setuptools
from pathlib import Path

# Read the README file for long description
readme_path = Path(__file__).parent / "README.md"
long_description = readme_path.read_text(encoding="utf-8") if readme_path.exists() else ""

# Read requirements from requirements.txt
requirements_path = Path(__file__).parent / "requirements.txt"
requirements = []
if requirements_path.exists():
    with open(requirements_path, "r", encoding="utf-8") as f:
        requirements = [
            line.strip() 
            for line in f 
            if line.strip() and not line.startswith("#") and not line.startswith("--")
        ]

setuptools.setup(
    name="budget-monitoring-cdk",
    version="1.0.0",
    
    description="AWS CDK Python application for budget monitoring with AWS Budgets and SNS",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS Recipes Team",
    author_email="recipes@aws.com",
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: JavaScript",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Code Generators",
        "Topic :: System :: Systems Administration",
        "Topic :: Office/Business :: Financial :: Accounting",
        "Typing :: Typed",
    ],
    
    install_requires=requirements,
    
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.5.0",
            "types-setuptools>=68.0.0",
        ],
        "cli": [
            "awscli>=1.29.0",
            "aws-cdk>=2.120.0",
        ]
    },
    
    package_dir={"": "."},
    packages=setuptools.find_packages(where="."),
    include_package_data=True,
    
    entry_points={
        "console_scripts": [
            "budget-monitoring-app=app:main",
        ],
    },
    
    project_urls={
        "Bug Tracker": "https://github.com/aws-samples/recipes/issues",
        "Documentation": "https://github.com/aws-samples/recipes",
        "Source Code": "https://github.com/aws-samples/recipes",
    },
    
    keywords=[
        "aws",
        "cdk",
        "budgets", 
        "sns",
        "cost-management",
        "monitoring",
        "notifications",
        "infrastructure-as-code",
        "cloud-formation",
        "python"
    ],
    
    zip_safe=False,
)