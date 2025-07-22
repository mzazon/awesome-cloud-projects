"""
Setup configuration for Aurora Serverless CDK Python application.

This setup file defines the Python package configuration for the CDK application
that deploys Aurora Serverless v2 infrastructure with automatic scaling capabilities.
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
    name="aurora-serverless-cdk",
    version="1.0.0",
    description="AWS CDK Python application for Aurora Serverless v2 database scaling",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="Database Engineering Team",
    author_email="database-team@company.com",
    license="Apache-2.0",
    url="https://github.com/company/aurora-serverless-cdk",
    project_urls={
        "Documentation": "https://docs.company.com/aurora-serverless",
        "Source": "https://github.com/company/aurora-serverless-cdk",
        "Bug Reports": "https://github.com/company/aurora-serverless-cdk/issues",
    },
    
    packages=setuptools.find_packages(),
    include_package_data=True,
    
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
        "Topic :: Database",
        "Topic :: Database :: Database Engines/Servers",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Typing :: Typed",
    ],
    
    python_requires=">=3.8",
    install_requires=requirements,
    
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "isort>=5.10.0",
            "bandit>=1.7.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
        "testing": [
            "moto[rds,ec2,cloudwatch]>=4.0.0",
            "pytest-mock>=3.10.0",
            "coverage>=7.0.0",
        ],
    },
    
    entry_points={
        "console_scripts": [
            "aurora-serverless-deploy=app:main",
        ],
    },
    
    keywords=[
        "aws",
        "cdk",
        "aurora",
        "serverless",
        "database",
        "scaling",
        "mysql",
        "rds",
        "infrastructure",
        "cloud",
        "devops",
        "automation",
    ],
    
    # Package metadata
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # Ensure compatibility with CDK
    zip_safe=False,
    
    # Project metadata for PyPI
    platforms=["any"],
    
    # Additional metadata
    obsoletes=["legacy-aurora-cdk"],
)