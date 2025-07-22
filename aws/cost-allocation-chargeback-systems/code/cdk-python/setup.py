"""
Setup configuration for AWS Cost Allocation and Chargeback Systems CDK Python application.

This setup file configures the Python package for the CDK application that deploys
a comprehensive cost allocation and chargeback system using AWS native billing and
cost management tools.
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
            if line.strip() and not line.startswith("#")
        ]

setuptools.setup(
    name="cost-allocation-chargeback-systems",
    version="1.0.0",
    
    description="AWS CDK Python application for cost allocation and chargeback systems",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS Solutions Architecture",
    author_email="solutions@amazon.com",
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "Intended Audience :: Financial and Insurance Industry",
        
        "License :: OSI Approved :: MIT License",
        
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        
        "Topic :: Office/Business :: Financial",
        "Topic :: System :: Systems Administration",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: Internet :: WWW/HTTP",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
    ],
    
    keywords=[
        "aws",
        "cdk",
        "cost-allocation",
        "chargeback",
        "billing",
        "finops",
        "cost-management",
        "budgets",
        "cost-explorer",
        "financial-governance"
    ],
    
    packages=setuptools.find_packages(),
    
    install_requires=requirements,
    
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.7.0",
            "isort>=5.12.0",
            "pre-commit>=3.4.0"
        ],
        "docs": [
            "sphinx>=7.1.0",
            "sphinx-rtd-theme>=1.3.0",
            "myst-parser>=2.0.0"
        ]
    },
    
    entry_points={
        "console_scripts": [
            "deploy-cost-allocation=app:main",
        ],
    },
    
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Cost Management Guide": "https://docs.aws.amazon.com/cost-management/",
        "AWS Budgets": "https://docs.aws.amazon.com/budgets/",
        "Cost Explorer": "https://docs.aws.amazon.com/cost-management/latest/userguide/ce-what-is.html"
    },
    
    package_data={
        "": ["*.md", "*.txt", "*.yaml", "*.yml", "*.json"],
    },
    
    include_package_data=True,
    zip_safe=False,
)