"""
Setup script for Centralized Alert Management CDK Python application

This setup.py file configures the Python package for the CDK application,
including dependencies, metadata, and development tools.
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
    with open(requirements_path, 'r', encoding='utf-8') as f:
        requirements = [
            line.strip() 
            for line in f 
            if line.strip() and not line.startswith('#')
        ]

setuptools.setup(
    name="centralized-alert-management-cdk",
    version="1.0.0",
    description="AWS CDK Python application for Centralized Alert Management with User Notifications",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    # Author information
    author="AWS Recipe Generator",
    author_email="recipes@aws.example.com",
    
    # Project URLs
    url="https://github.com/aws-samples/centralized-alert-management",
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/notifications/",
        "Source": "https://github.com/aws-samples/centralized-alert-management",
        "Tracker": "https://github.com/aws-samples/centralized-alert-management/issues",
    },
    
    # Package configuration
    packages=setuptools.find_packages(exclude=["tests*"]),
    include_package_data=True,
    
    # Python version requirements
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=requirements,
    
    # Package classification
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
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Monitoring",
        "Topic :: System :: Systems Administration",
        "Typing :: Typed",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "cloudwatch",
        "notifications",
        "monitoring",
        "alerts",
        "s3",
        "infrastructure",
        "devops"
    ],
    
    # Entry points for command-line tools
    entry_points={
        "console_scripts": [
            "cdk-deploy=app:main",
        ],
    },
    
    # Development dependencies (extras)
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.5.0",
            "pre-commit>=3.4.0",
        ],
        "security": [
            "cdk-nag>=2.27.0",
            "bandit>=1.7.5",
            "safety>=2.3.0",
        ],
        "docs": [
            "sphinx>=7.1.0",
            "sphinx-rtd-theme>=1.3.0",
            "myst-parser>=2.0.0",
        ],
    },
    
    # Package data and resources
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # Zip safety
    zip_safe=False,
    
    # Metadata for PyPI
    license="MIT",
    platforms=["any"],
)