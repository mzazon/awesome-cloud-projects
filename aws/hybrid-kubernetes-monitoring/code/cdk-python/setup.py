"""
Setup configuration for Hybrid Kubernetes Monitoring CDK Python Application

This setup.py file configures the Python package for the CDK application that deploys
a hybrid Kubernetes monitoring solution using Amazon EKS Hybrid Nodes and CloudWatch.
"""

import setuptools
from pathlib import Path

# Read the README file for long description
readme_path = Path(__file__).parent / "README.md"
long_description = readme_path.read_text(encoding="utf-8") if readme_path.exists() else ""

# Read requirements from requirements.txt
requirements_path = Path(__file__).parent / "requirements.txt"
if requirements_path.exists():
    with open(requirements_path, "r", encoding="utf-8") as f:
        requirements = [
            line.strip() 
            for line in f 
            if line.strip() and not line.startswith("#")
        ]
else:
    requirements = [
        "aws-cdk-lib>=2.169.0",
        "constructs>=10.3.0",
    ]

setuptools.setup(
    name="hybrid-kubernetes-monitoring-cdk",
    version="1.0.0",
    
    description="CDK Python application for Hybrid Kubernetes Monitoring with EKS Hybrid Nodes",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS Solutions Architecture",
    author_email="solutions-architects@amazon.com",
    
    url="https://github.com/aws-samples/hybrid-kubernetes-monitoring",
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: System Administrators",
        "Intended Audience :: Developers",
        "Topic :: System :: Systems Administration",
        "Topic :: System :: Monitoring",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Framework :: AWS CDK",
        "Framework :: AWS CDK :: 2",
    ],
    
    keywords=[
        "aws",
        "cdk",
        "eks",
        "kubernetes",
        "monitoring",
        "cloudwatch",
        "hybrid",
        "fargate",
        "containers",
        "observability",
        "infrastructure",
        "devops",
    ],
    
    packages=setuptools.find_packages(exclude=["tests*"]),
    
    install_requires=requirements,
    
    extras_require={
        "dev": [
            "pytest>=8.0.0",
            "pytest-cov>=4.0.0",
            "black>=24.0.0",
            "flake8>=7.0.0",
            "mypy>=1.8.0",
            "isort>=5.13.0",
            "bandit>=1.7.6",
            "safety>=3.0.0",
        ],
        "docs": [
            "sphinx>=7.2.0",
            "sphinx-rtd-theme>=2.0.0",
        ],
        "typing": [
            "types-requests>=2.31.0",
            "boto3-stubs[eks,ec2,iam,cloudwatch,logs]>=1.34.0",
        ],
    },
    
    entry_points={
        "console_scripts": [
            "hybrid-monitoring-deploy=app:main",
        ],
    },
    
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/eks/latest/userguide/hybrid-nodes-overview.html",
        "Source": "https://github.com/aws-samples/hybrid-kubernetes-monitoring",
        "Bug Reports": "https://github.com/aws-samples/hybrid-kubernetes-monitoring/issues",
        "AWS EKS": "https://aws.amazon.com/eks/",
        "AWS CloudWatch": "https://aws.amazon.com/cloudwatch/",
        "AWS Fargate": "https://aws.amazon.com/fargate/",
    },
    
    license="MIT",
    
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    include_package_data=True,
    
    zip_safe=False,
    
    platforms=["any"],
    
    # CDK-specific metadata
    options={
        "build_scripts": {
            "executable": "/usr/bin/env python3",
        },
    },
)