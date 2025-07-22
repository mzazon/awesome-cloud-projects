"""
AWS CDK Python Package Setup for Sustainability Dashboards.

This setup.py file configures the Python package for deploying intelligent
sustainability dashboards using AWS CDK with support for carbon footprint
analytics, cost correlation, and QuickSight visualization.
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
requirements = []
if requirements_path.exists():
    with open(requirements_path, "r", encoding="utf-8") as fh:
        requirements = [
            line.strip() for line in fh.readlines()
            if line.strip() and not line.startswith("#")
        ]

setuptools.setup(
    name="sustainability-dashboard-cdk",
    version="1.0.0",
    
    description="AWS CDK application for intelligent sustainability dashboards with carbon footprint analytics",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS Solutions Architecture Team",
    author_email="sustainability-team@example.com",
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators", 
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Utilities"
    ],
    
    install_requires=requirements,
    
    packages=setuptools.find_packages(),
    
    # Entry points for command-line tools (optional)
    entry_points={
        "console_scripts": [
            "deploy-sustainability-dashboard=app:main",
        ],
    },
    
    # Additional metadata
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws-samples/sustainability-dashboard-cdk",
        "Bug Reports": "https://github.com/aws-samples/sustainability-dashboard-cdk/issues",
    },
    
    # Package data and additional files
    include_package_data=True,
    zip_safe=False,
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "sustainability", 
        "carbon-footprint",
        "quicksight",
        "analytics",
        "cost-optimization",
        "lambda",
        "s3",
        "cloudwatch",
        "eventbridge"
    ],
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "mypy>=1.0.0", 
            "flake8>=5.0.0",
            "pre-commit>=2.20.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ]
    }
)