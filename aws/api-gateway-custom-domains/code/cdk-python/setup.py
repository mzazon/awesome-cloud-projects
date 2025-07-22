"""
Setup configuration for API Gateway Custom Domain CDK Python application.

This package provides AWS CDK infrastructure code for deploying a complete
API Gateway solution with custom domain names, SSL certificates, and
Lambda-based backend services.
"""

import setuptools
from pathlib import Path

# Read the README file for long description
readme_path = Path(__file__).parent / "README.md"
long_description = readme_path.read_text(encoding="utf-8") if readme_path.exists() else ""

# Read requirements from requirements.txt
requirements_path = Path(__file__).parent / "requirements.txt"
if requirements_path.exists():
    with open(requirements_path, encoding="utf-8") as f:
        requirements = [
            line.strip() 
            for line in f 
            if line.strip() and not line.startswith("#")
        ]
else:
    requirements = [
        "aws-cdk-lib>=2.167.1",
        "constructs>=10.0.0,<11.0.0",
        "typing-extensions>=4.0.0"
    ]

setuptools.setup(
    name="api-gateway-custom-domain-cdk",
    version="1.0.0",
    description="AWS CDK Python application for API Gateway with custom domain names",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS Recipes",
    author_email="recipes@aws.example.com",
    url="https://github.com/aws-samples/aws-recipes",
    
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Environment :: Console",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: MIT License",
        "Natural Language :: English",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Internet :: WWW/HTTP :: HTTP Servers",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: System :: Systems Administration",
        "Topic :: Utilities",
        "Framework :: AWS CDK",
        "Framework :: AWS CDK :: 2",
    ],
    
    keywords=[
        "aws", "cdk", "api-gateway", "custom-domain", "ssl", "certificate",
        "lambda", "route53", "dns", "serverless", "rest-api", "infrastructure"
    ],
    
    packages=setuptools.find_packages(exclude=["tests", "tests.*"]),
    
    python_requires=">=3.8",
    
    install_requires=requirements,
    
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "pre-commit>=2.20.0",
        ],
        "testing": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",
            "boto3-stubs[essential]>=1.34.0",
        ]
    },
    
    entry_points={
        "console_scripts": [
            "deploy-api-gateway=app:main",
        ],
    },
    
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/aws-recipes/issues",
        "Source": "https://github.com/aws-samples/aws-recipes",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "AWS CDK": "https://aws.amazon.com/cdk/",
        "API Gateway": "https://aws.amazon.com/api-gateway/",
        "Route 53": "https://aws.amazon.com/route53/",
        "Certificate Manager": "https://aws.amazon.com/certificate-manager/",
    },
    
    package_data={
        "": ["*.md", "*.txt", "*.yaml", "*.yml", "*.json"],
    },
    
    include_package_data=True,
    
    zip_safe=False,
    
    # CDK-specific metadata
    options={
        "cdk": {
            "version": "2.167.1",
            "construct_version": "10.0.0",
        }
    }
)