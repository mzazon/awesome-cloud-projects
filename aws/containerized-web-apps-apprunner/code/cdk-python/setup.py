"""
CDK Python application setup configuration.

This setup.py file configures the Python package for the containerized web application
CDK deployment, including dependencies, metadata, and development tools.
"""

import setuptools
from pathlib import Path

# Read README file for long description
readme_path = Path(__file__).parent / "README.md"
long_description = readme_path.read_text(encoding="utf-8") if readme_path.exists() else ""

# Read requirements from requirements.txt
requirements_path = Path(__file__).parent / "requirements.txt"
with open(requirements_path, 'r') as f:
    requirements = [
        line.strip() 
        for line in f 
        if line.strip() and not line.startswith('#')
    ]

setuptools.setup(
    name="containerized-web-app-cdk",
    version="1.0.0",
    
    description="CDK Python application for containerized web applications with App Runner and RDS",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS CDK Recipe Generator",
    author_email="noreply@amazon.com",
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Typing :: Typed",
    ],
    
    packages=setuptools.find_packages(exclude=["tests"]),
    
    install_requires=requirements,
    
    extras_require={
        "dev": [
            "pytest>=6.0.0",
            "pytest-cov>=2.10.0",
            "black>=21.0.0",
            "flake8>=3.8.0",
            "mypy>=0.812",
            "pre-commit>=2.15.0",
        ]
    },
    
    entry_points={
        "console_scripts": [
            "deploy=app:main",
        ],
    },
    
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/v2/guide/",
        "Source": "https://github.com/aws/aws-cdk",
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
    },
    
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "containers",
        "app-runner",
        "rds",
        "postgresql",
        "secrets-manager",
        "cloudwatch"
    ],
    
    include_package_data=True,
    zip_safe=False,
)