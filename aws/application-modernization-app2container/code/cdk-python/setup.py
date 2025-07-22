"""
Setup configuration for AWS App2Container CDK Python application.

This package provides Infrastructure as Code (IaC) for deploying the complete
AWS App2Container modernization infrastructure using AWS CDK Python.
"""

import setuptools
from typing import List

# Read long description from README
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = """
    AWS App2Container CDK Python Application
    
    This CDK application provisions the complete infrastructure needed for application
    modernization using AWS App2Container, including ECS cluster, ECR repository,
    CI/CD pipeline, and supporting services.
    """

# Read requirements from requirements.txt
def parse_requirements(filename: str) -> List[str]:
    """Parse requirements from requirements.txt file."""
    try:
        with open(filename, "r", encoding="utf-8") as f:
            requirements = []
            for line in f:
                line = line.strip()
                # Skip comments and empty lines
                if line and not line.startswith("#"):
                    # Remove inline comments
                    req = line.split("#")[0].strip()
                    if req:
                        requirements.append(req)
            return requirements
    except FileNotFoundError:
        # Fallback requirements if file not found
        return [
            "aws-cdk-lib>=2.162.1",
            "constructs>=10.0.0,<11.0.0",
            "boto3>=1.35.0",
            "botocore>=1.35.0"
        ]

setuptools.setup(
    name="app2container-cdk",
    version="1.0.0",
    
    author="AWS Solutions Team",
    author_email="aws-solutions@amazon.com",
    
    description="AWS App2Container modernization infrastructure using CDK Python",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    url="https://github.com/aws-samples/aws-app2container-recipes",
    
    package_dir={"": "."},
    packages=setuptools.find_packages(where="."),
    
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
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
        "Topic :: Software Development :: Build Tools",
    ],
    
    python_requires=">=3.8",
    
    install_requires=parse_requirements("requirements.txt"),
    
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "pre-commit>=3.0.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
            "myst-parser>=0.18.0",
        ],
    },
    
    entry_points={
        "console_scripts": [
            "app2container-cdk=app:main",
        ],
    },
    
    keywords=[
        "aws",
        "cdk",
        "app2container",
        "containerization", 
        "modernization",
        "ecs",
        "fargate",
        "docker",
        "migration",
        "infrastructure",
        "devops",
        "cicd"
    ],
    
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/aws-app2container-recipes/issues",
        "Source": "https://github.com/aws-samples/aws-app2container-recipes",
        "Documentation": "https://docs.aws.amazon.com/app2container/",
        "AWS App2Container": "https://aws.amazon.com/app2container/",
    },
    
    include_package_data=True,
    zip_safe=False,
)