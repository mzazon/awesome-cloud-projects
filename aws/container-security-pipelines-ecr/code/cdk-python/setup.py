"""
Setup configuration for Container Security Scanning Pipeline CDK application

This setup.py file configures the Python package for the CDK application,
including dependencies, metadata, and entry points.
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
    name="container-security-scanning-cdk",
    version="1.0.0",
    
    description="AWS CDK Python application for Container Security Scanning Pipeline with ECR and Third-Party Tools",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS CDK Python Generator",
    author_email="your-email@example.com",
    
    python_requires=">=3.9",
    
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Security",
    ],
    
    keywords="aws cdk container security scanning ecr inspector vulnerability",
    
    packages=setuptools.find_packages(),
    
    install_requires=requirements,
    
    # Entry points for command line tools
    entry_points={
        "console_scripts": [
            "deploy-security-pipeline=app:main",
        ],
    },
    
    # Additional package data
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # Include additional files
    include_package_data=True,
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "Tracker": "https://github.com/aws/aws-cdk/issues",
    },
    
    # Extras for development
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "types-boto3>=1.0.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
        "security": [
            "bandit>=1.7.0",
            "safety>=2.0.0",
        ],
    },
    
    # License
    license="MIT",
    
    # Zip safe
    zip_safe=False,
)