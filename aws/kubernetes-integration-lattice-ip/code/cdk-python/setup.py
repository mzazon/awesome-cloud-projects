"""
Setup configuration for Kubernetes VPC Lattice Integration CDK Python application.

This module provides package configuration for the AWS CDK Python application
that deploys infrastructure for connecting self-managed Kubernetes clusters
across VPCs using VPC Lattice as a service mesh layer.
"""

import setuptools
from pathlib import Path

# Read the long description from README if it exists
readme_path = Path(__file__).parent / "README.md"
if readme_path.exists():
    with open(readme_path, "r", encoding="utf-8") as fh:
        long_description = fh.read()
else:
    long_description = "AWS CDK Python application for Kubernetes VPC Lattice Integration"

# Read requirements from requirements.txt
requirements_path = Path(__file__).parent / "requirements.txt"
if requirements_path.exists():
    with open(requirements_path, "r", encoding="utf-8") as fh:
        install_requires = [
            line.strip() 
            for line in fh.readlines() 
            if line.strip() and not line.startswith("#")
        ]
else:
    install_requires = [
        "aws-cdk-lib>=2.168.0",
        "constructs>=10.0.0",
        "boto3>=1.34.0",
        "botocore>=1.34.0",
    ]

setuptools.setup(
    name="kubernetes-vpc-lattice-integration",
    version="1.0.0",
    
    author="AWS Solutions Architecture",
    author_email="solutions@aws.com",
    
    description="AWS CDK Python application for Kubernetes VPC Lattice Integration",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    url="https://github.com/aws-samples/kubernetes-vpc-lattice-integration",
    
    packages=setuptools.find_packages(),
    
    install_requires=install_requires,
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Networking",
        "Topic :: System :: Systems Administration",
    ],
    
    keywords=[
        "aws",
        "cdk",
        "kubernetes",
        "vpc-lattice",
        "service-mesh",
        "networking",
        "containers",
        "infrastructure",
        "cloud",
    ],
    
    entry_points={
        "console_scripts": [
            "k8s-lattice-deploy=app:main",
        ],
    },
    
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/kubernetes-vpc-lattice-integration/issues",
        "Source": "https://github.com/aws-samples/kubernetes-vpc-lattice-integration",
        "Documentation": "https://docs.aws.amazon.com/vpc-lattice/",
    },
)