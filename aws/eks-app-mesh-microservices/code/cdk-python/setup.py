"""
Setup configuration for AWS CDK Python application.

This setup.py file configures the Python package for the CDK application
that deploys microservices on EKS with AWS App Mesh service mesh capabilities.
"""

import setuptools

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setuptools.setup(
    name="microservices-eks-app-mesh",
    version="1.0.0",
    
    description="AWS CDK Python application for deploying microservices on EKS with App Mesh",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS Solutions Architecture Team",
    author_email="aws-solutions@amazon.com",
    
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
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP :: HTTP Servers",
        "Typing :: Typed",
    ],
    
    install_requires=[
        "aws-cdk-lib==2.139.0",
        "constructs>=10.0.0,<11.0.0",
    ],
    
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "types-setuptools>=65.0.0",
        ]
    },
    
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "microservices",
        "kubernetes",
        "eks",
        "app-mesh",
        "service-mesh",
        "containers",
        "devops"
    ],
    
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
    },
)