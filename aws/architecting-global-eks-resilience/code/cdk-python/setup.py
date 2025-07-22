#!/usr/bin/env python3
"""
Setup configuration for Multi-Cluster EKS CDK Python application.

This setup.py file configures the Python package for the CDK application
that deploys multi-cluster EKS infrastructure with cross-region networking.
"""

from setuptools import setup, find_packages

# Read long description from README if it exists
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "Multi-Cluster EKS Deployments with Cross-Region Networking using AWS CDK"

# Read requirements from requirements.txt
try:
    with open("requirements.txt", "r", encoding="utf-8") as fh:
        requirements = [
            line.strip() 
            for line in fh 
            if line.strip() and not line.startswith("#")
        ]
except FileNotFoundError:
    requirements = [
        "aws-cdk-lib>=2.100.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "typing-extensions>=4.0.0"
    ]

setup(
    name="multi-cluster-eks-cdk",
    version="1.0.0",
    
    description="AWS CDK Python application for multi-cluster EKS deployment with cross-region networking",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS Solutions Architecture Team",
    author_email="solutions-architecture@example.com",
    
    url="https://github.com/aws-samples/multi-cluster-eks-cdk",
    
    packages=find_packages(),
    
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
    ],
    
    python_requires=">=3.8",
    
    install_requires=requirements,
    
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
    },
    
    entry_points={
        "console_scripts": [
            "multi-cluster-eks-deploy=app:main",
        ],
    },
    
    keywords=[
        "aws",
        "cdk",
        "eks",
        "kubernetes",
        "multi-cluster",
        "cross-region",
        "transit-gateway",
        "vpc-lattice",
        "service-mesh",
        "infrastructure-as-code",
        "cloud-formation"
    ],
    
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/multi-cluster-eks-cdk/issues",
        "Source": "https://github.com/aws-samples/multi-cluster-eks-cdk",
        "Documentation": "https://github.com/aws-samples/multi-cluster-eks-cdk/blob/main/README.md",
    },
    
    # Include additional files in the package
    package_data={
        "": ["*.md", "*.txt", "*.yml", "*.yaml"],
    },
    
    include_package_data=True,
    
    zip_safe=False,
    
    # CDK-specific metadata
    cdk_version=">=2.100.0",
    
    # Project metadata for CDK
    metadata={
        "cdk-version": "2.100.0",
        "aws-services": [
            "EKS",
            "EC2",
            "VPC",
            "Transit Gateway",
            "VPC Lattice",
            "IAM",
            "Route 53",
            "CloudWatch Logs"
        ],
        "deployment-regions": [
            "us-east-1",
            "us-west-2"
        ],
        "architecture-pattern": "multi-cluster-cross-region",
        "complexity": "expert",
        "estimated-cost": "$250-350/month"
    }
)