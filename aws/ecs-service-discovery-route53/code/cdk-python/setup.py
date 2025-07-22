"""
Setup configuration for ECS Service Discovery CDK Python application.

This setup.py file configures the Python package for the CDK application
that creates ECS service discovery infrastructure with Route 53 and ALB.
"""

import setuptools
from pathlib import Path

# Read the README file for long description
try:
    long_description = Path("../README.md").read_text(encoding="utf-8")
except FileNotFoundError:
    long_description = "CDK Python application for ECS Service Discovery with Route 53 and Application Load Balancer"

setuptools.setup(
    name="ecs-service-discovery-cdk",
    version="1.0.0",
    
    description="CDK Python application for ECS Service Discovery with Route 53 and Application Load Balancer",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS CDK",
    author_email="",
    
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
        "Topic :: Software Development :: Code Generators",
        "Topic :: Utilities",
        "Topic :: System :: Systems Administration",
        "Typing :: Typed",
    ],
    
    install_requires=[
        "aws-cdk-lib>=2.100.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
    ],
    
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
        ],
    },
    
    py_modules=["app"],
    
    entry_points={
        "console_scripts": [
            "ecs-service-discovery=app:main",
        ],
    },
    
    keywords=[
        "aws",
        "cdk",
        "ecs",
        "fargate",
        "service-discovery",
        "route53",
        "cloudmap",
        "load-balancer",
        "microservices",
        "infrastructure",
        "cloud",
    ],
    
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
    },
)