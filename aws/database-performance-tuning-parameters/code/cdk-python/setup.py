"""
Setup configuration for Database Performance Tuning CDK Python application.

This setup.py file configures the Python package for the CDK application,
including dependencies, metadata, and development requirements.
"""

import setuptools
from pathlib import Path

# Read the README file for long description
readme_path = Path(__file__).parent / "README.md"
if readme_path.exists():
    with open(readme_path, "r", encoding="utf-8") as fh:
        long_description = fh.read()
else:
    long_description = "AWS CDK Python application for Database Performance Tuning with Parameter Groups"

# Read requirements from requirements.txt
requirements_path = Path(__file__).parent / "requirements.txt"
with open(requirements_path, "r", encoding="utf-8") as fh:
    requirements = [
        line.strip() 
        for line in fh.readlines() 
        if line.strip() and not line.startswith("#")
    ]

setuptools.setup(
    name="database-performance-tuning-cdk",
    version="1.0.0",
    description="AWS CDK Python application for Database Performance Tuning with Parameter Groups",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS Recipes Team",
    author_email="aws-recipes@example.com",
    url="https://github.com/aws-recipes/database-performance-tuning",
    
    # Package configuration
    package_dir={"": "."},
    packages=setuptools.find_packages(where="."),
    
    # Dependencies
    install_requires=requirements,
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=0.991",
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.2.0",  # For AWS service mocking
            "boto3-stubs[rds,ec2,cloudwatch]>=1.28.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
            "sphinx-autodoc-typehints>=1.19.0",
        ]
    },
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Package metadata
    classifiers=[
        "Development Status :: 4 - Beta",
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
        "Topic :: Database",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "database",
        "performance",
        "tuning",
        "postgresql",
        "rds",
        "parameter-groups",
        "cloudwatch",
        "monitoring",
        "infrastructure-as-code",
    ],
    
    # Entry points for command-line scripts
    entry_points={
        "console_scripts": [
            "deploy-database-performance-tuning=app:main",
        ],
    },
    
    # Include additional files in the package
    include_package_data=True,
    package_data={
        "": [
            "*.md",
            "*.txt",
            "*.yaml",
            "*.yml",
            "*.json",
        ],
    },
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/aws-recipes/database-performance-tuning/issues",
        "Source": "https://github.com/aws-recipes/database-performance-tuning",
        "Documentation": "https://aws-recipes.github.io/database-performance-tuning/",
    },
    
    # License
    license="MIT",
    
    # Zip safety
    zip_safe=False,
)