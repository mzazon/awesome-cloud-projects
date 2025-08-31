"""
Setup script for Resource Tagging Automation CDK Python application.

This setup script configures the Python package for the automated resource
tagging system that uses EventBridge to capture CloudTrail events and
triggers Lambda functions to apply standardized organizational tags.
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
    requirements = [
        line.strip()
        for line in requirements_path.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.startswith("#")
    ]

setuptools.setup(
    name="resource-tagging-automation-cdk",
    version="1.0.0",
    
    description="CDK Python application for automated AWS resource tagging",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS Solutions Architecture",
    author_email="solutions@example.com",
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: System :: Systems Administration",
        "Topic :: Utilities",
    ],
    
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "automation",
        "tagging",
        "governance",
        "lambda",
        "eventbridge",
        "cloudtrail",
        "cost-management"
    ],
    
    packages=setuptools.find_packages(exclude=["tests*"]),
    
    install_requires=requirements,
    
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "black>=23.0.0",
            "mypy>=1.0.0",
            "flake8>=6.0.0",
            "pytest-cov>=4.0.0",
            "pre-commit>=3.0.0"
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
            "sphinx-autodoc-typehints>=1.19.0"
        ]
    },
    
    entry_points={
        "console_scripts": [
            "resource-tagging-cdk=app:main",
        ],
    },
    
    include_package_data=True,
    
    package_data={
        "": ["*.json", "*.yaml", "*.yml", "*.md"],
    },
    
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/resource-tagging-automation/issues",
        "Source": "https://github.com/aws-samples/resource-tagging-automation",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "AWS CDK": "https://aws.amazon.com/cdk/",
    },
    
    zip_safe=False,
)