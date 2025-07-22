"""
Setup configuration for Intelligent Document QA System CDK Python application.

This setup.py file configures the Python package for the CDK application that
deploys an intelligent document question-answering system using AWS Bedrock
and Amazon Kendra services.
"""

import setuptools
from pathlib import Path

# Read the README file for long description
this_directory = Path(__file__).parent
long_description = ""
readme_path = this_directory / "README.md"
if readme_path.exists():
    long_description = readme_path.read_text(encoding="utf-8")

# Read requirements from requirements.txt
requirements = []
requirements_path = this_directory / "requirements.txt"
if requirements_path.exists():
    with open(requirements_path, "r", encoding="utf-8") as f:
        requirements = [
            line.strip()
            for line in f
            if line.strip() and not line.startswith("#")
        ]

setuptools.setup(
    name="intelligent-document-qa-cdk",
    version="1.0.0",
    description="CDK Python application for Intelligent Document QA System with Bedrock and Kendra",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS CDK Generator",
    author_email="support@example.com",
    
    # Package configuration
    python_requires=">=3.8",
    packages=setuptools.find_packages(),
    
    # Dependencies
    install_requires=requirements,
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "isort>=5.0.0",
            "mypy>=1.0.0",
        ],
        "testing": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",
            "boto3-stubs[s3,kendra,bedrock-runtime,lambda,apigateway]>=1.28.0",
        ]
    },
    
    # Project URLs
    project_urls={
        "Source": "https://github.com/example/intelligent-document-qa-cdk",
        "Documentation": "https://docs.example.com/intelligent-document-qa",
        "Bug Reports": "https://github.com/example/intelligent-document-qa-cdk/issues",
    },
    
    # Classifiers for PyPI
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
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: System :: Systems Administration",
        "Topic :: Utilities",
        "Typing :: Typed",
    ],
    
    # Keywords for discoverability
    keywords=[
        "aws",
        "cdk",
        "bedrock",
        "kendra",
        "ai",
        "machine-learning",
        "document-search",
        "question-answering",
        "nlp",
        "infrastructure-as-code",
        "cloud",
        "serverless"
    ],
    
    # Entry points for console scripts
    entry_points={
        "console_scripts": [
            "deploy-qa-system=app:main",
        ],
    },
    
    # Include additional files
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.yaml", "*.yml", "*.json"],
    },
    
    # Zip safety
    zip_safe=False,
)