"""
Setup configuration for Event-Driven Architecture with Amazon EventBridge CDK Python application

This setup.py file defines the Python package configuration for the CDK application
that creates a complete event-driven architecture using Amazon EventBridge as the
central event router for an e-commerce platform.
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
            if line.strip() and not line.startswith("#") and not line.startswith("-")
        ]

setuptools.setup(
    name="event-driven-architecture-eventbridge",
    version="1.0.0",
    
    description="CDK Python application for Microservices with EventBridge Routing",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS Recipe Generator",
    author_email="recipes@example.com",
    
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
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP",
        "Framework :: AWS CDK",
        "Framework :: AWS CDK :: 2",
    ],
    
    keywords=[
        "aws",
        "cdk",
        "eventbridge",
        "lambda",
        "sqs",
        "event-driven",
        "serverless",
        "microservices",
        "e-commerce",
        "cloud",
        "infrastructure",
        "iac"
    ],
    
    packages=setuptools.find_packages(),
    
    install_requires=requirements,
    
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "types-boto3>=1.0.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
    },
    
    project_urls={
        "Bug Reports": "https://github.com/your-org/recipes/issues",
        "Source": "https://github.com/your-org/recipes",
        "Documentation": "https://docs.aws.amazon.com/eventbridge/",
        "CDK Documentation": "https://docs.aws.amazon.com/cdk/",
    },
    
    entry_points={
        "console_scripts": [
            "eventbridge-demo=app:main",
        ],
    },
    
    include_package_data=True,
    zip_safe=False,
    
    # CDK-specific metadata
    cdk={
        "version": "2.168.0",
        "language": "python",
        "framework": "aws-cdk-lib",
    },
)