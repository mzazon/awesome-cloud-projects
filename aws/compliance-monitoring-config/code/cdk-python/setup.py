"""
Setup configuration for the AWS Config Compliance Monitoring CDK application.

This setup.py file defines the package metadata and dependencies for the CDK Python application
that creates a comprehensive compliance monitoring system using AWS Config.
"""

import setuptools
from pathlib import Path

# Read the README file for the long description
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
    name="compliance-monitoring-aws-config",
    version="1.0.0",
    
    description="AWS CDK Python application for comprehensive compliance monitoring with AWS Config",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS Recipe Generator",
    author_email="your-email@example.com",
    
    package_dir={"": "src"},
    packages=setuptools.find_packages(where="src"),
    
    install_requires=requirements,
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Security",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Framework :: AWS CDK",
        "Framework :: AWS CDK :: 2",
    ],
    
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "config",
        "compliance",
        "monitoring",
        "security",
        "governance",
        "automation"
    ],
    
    project_urls={
        "Bug Reports": "https://github.com/your-org/compliance-monitoring/issues",
        "Source": "https://github.com/your-org/compliance-monitoring",
        "Documentation": "https://docs.aws.amazon.com/config/",
    },
    
    entry_points={
        "console_scripts": [
            "deploy-compliance=app:main",
        ],
    },
    
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "bandit>=1.7.0",  # Security linting
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",  # Mock AWS services for testing
        ],
    },
    
    include_package_data=True,
    zip_safe=False,
)