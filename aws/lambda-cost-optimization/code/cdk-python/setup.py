"""
Setup script for AWS Lambda Cost Compute Optimizer CDK Application

This setup script configures the Python package for the Lambda Cost Optimizer
CDK application, including all dependencies and metadata required for deployment.
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
    name="lambda-cost-compute-optimizer",
    version="1.0.0",
    
    description="AWS CDK application for Lambda cost optimization using Compute Optimizer",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS Recipes",
    author_email="aws-recipes@example.com",
    
    package_dir={"": "."},
    packages=setuptools.find_packages(where="."),
    
    install_requires=requirements,
    
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
        "Framework :: AWS CDK",
        "Framework :: AWS CDK :: 2",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: System :: Monitoring",
    ],
    
    keywords=[
        "aws",
        "cdk",
        "lambda",
        "cost-optimization",
        "compute-optimizer",
        "serverless",
        "infrastructure-as-code",
        "cloud",
        "monitoring"
    ],
    
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/compute-optimizer/",
        "Source": "https://github.com/aws-samples/aws-recipes",
        "Bug Reports": "https://github.com/aws-samples/aws-recipes/issues",
        "AWS CDK": "https://aws.amazon.com/cdk/",
        "AWS Compute Optimizer": "https://aws.amazon.com/compute-optimizer/",
    },
    
    entry_points={
        "console_scripts": [
            "lambda-cost-optimizer=app:main",
        ],
    },
    
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "pytest-mock>=3.11.0",
            "black>=23.7.0",
            "isort>=5.12.0",
            "flake8>=6.0.0",
            "mypy>=1.5.0",
        ],
        "docs": [
            "Sphinx>=7.1.0",
            "sphinx-rtd-theme>=1.3.0",
        ],
        "testing": [
            "moto>=4.2.0",
            "pytest-xdist>=3.3.0",
        ],
    },
    
    include_package_data=True,
    zip_safe=False,
)