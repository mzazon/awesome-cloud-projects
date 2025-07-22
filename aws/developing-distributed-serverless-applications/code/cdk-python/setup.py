"""
Setup configuration for Multi-Region Aurora DSQL CDK Python Application

This setup.py file configures the Python package for the CDK application,
including dependencies, metadata, and development requirements.
"""

import setuptools
from pathlib import Path

# Read the README file
readme_path = Path(__file__).parent / "README.md"
if readme_path.exists():
    with open(readme_path, "r", encoding="utf-8") as fh:
        long_description = fh.read()
else:
    long_description = "CDK Python application for Multi-Region Aurora DSQL deployment"

# Read requirements from requirements.txt
requirements_path = Path(__file__).parent / "requirements.txt"
if requirements_path.exists():
    with open(requirements_path, "r", encoding="utf-8") as fh:
        requirements = [
            line.strip()
            for line in fh
            if line.strip() and not line.startswith("#")
        ]
else:
    requirements = [
        "aws-cdk-lib>=2.161.1",
        "constructs>=10.0.0,<11.0.0"
    ]

setuptools.setup(
    name="multi-region-aurora-dsql-cdk",
    version="1.0.0",
    
    description="CDK Python application for deploying multi-region applications with Aurora DSQL",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS Recipes Team",
    author_email="aws-recipes@example.com",
    
    url="https://github.com/aws-recipes/multi-region-aurora-dsql",
    
    package_dir={"": "."},
    packages=setuptools.find_packages(),
    
    install_requires=requirements,
    
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "bandit>=1.7.0",
            "isort>=5.10.0",
            "autopep8>=2.0.0"
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0"
        ]
    },
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP :: HTTP Servers",
        "Topic :: Database :: Database Engines/Servers"
    ],
    
    keywords=[
        "aws",
        "cdk",
        "aurora",
        "dsql",
        "multi-region",
        "serverless",
        "lambda",
        "api-gateway",
        "cloud",
        "infrastructure",
        "devops"
    ],
    
    project_urls={
        "Bug Reports": "https://github.com/aws-recipes/multi-region-aurora-dsql/issues",
        "Source": "https://github.com/aws-recipes/multi-region-aurora-dsql",
        "Documentation": "https://docs.aws.amazon.com/aurora-dsql/",
    },
    
    entry_points={
        "console_scripts": [
            "multi-region-dsql=app:main",
        ],
    },
    
    include_package_data=True,
    zip_safe=False,
    
    # Additional metadata
    license="Apache License 2.0",
    platforms=["any"],
    
    # Development status and maturity
    download_url="https://github.com/aws-recipes/multi-region-aurora-dsql/archive/v1.0.0.tar.gz",
)