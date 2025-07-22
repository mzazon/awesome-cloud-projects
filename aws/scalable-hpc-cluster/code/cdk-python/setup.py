"""
Setup configuration for AWS ParallelCluster HPC Infrastructure CDK Application

This setup.py file configures the Python package for the CDK application that creates
the foundational infrastructure for AWS ParallelCluster HPC deployments.
"""

from setuptools import setup, find_packages
import os

# Read version from environment or default
VERSION = os.environ.get("VERSION", "1.0.0")

# Read long description from README if available
LONG_DESCRIPTION = """
AWS CDK Python Application for High Performance Computing Clusters with AWS ParallelCluster

This CDK application creates the foundational infrastructure required for AWS ParallelCluster HPC deployments,
including VPC, subnets, security groups, IAM roles, S3 storage, FSx Lustre filesystems, and monitoring resources.

Key Features:
- Custom VPC with public and private subnets optimized for HPC workloads
- Security groups configured for head node and compute node communication
- S3 bucket with lifecycle policies for data management
- FSx Lustre filesystem with S3 integration for high-performance storage
- IAM roles with least-privilege permissions for cluster components
- CloudWatch monitoring and alerting for cluster performance
- Comprehensive configuration management through AWS Secrets Manager

The infrastructure is designed to support auto-scaling HPC clusters with Slurm job scheduler,
enabling cost-effective high-performance computing workloads in the cloud.
"""

# Development requirements
DEV_REQUIREMENTS = [
    "pytest>=7.2.0",
    "pytest-cov>=4.0.0",
    "black>=23.0.0",
    "flake8>=6.0.0",
    "mypy>=1.0.0",
    "isort>=5.12.0",
    "bandit>=1.7.0",
    "safety>=2.3.0",
]

# Documentation requirements
DOC_REQUIREMENTS = [
    "sphinx>=5.0.0",
    "sphinx-rtd-theme>=1.2.0",
]

setup(
    name="hpc-parallelcluster-cdk",
    version=VERSION,
    description="AWS CDK application for ParallelCluster HPC infrastructure",
    long_description=LONG_DESCRIPTION,
    long_description_content_type="text/markdown",
    author="AWS Solutions Team",
    author_email="aws-solutions@amazon.com",
    url="https://github.com/aws-samples/hpc-parallelcluster-cdk",
    license="MIT-0",
    
    # Package configuration
    packages=find_packages(exclude=["tests*"]),
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=[
        "aws-cdk-lib>=2.100.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.26.0",
        "botocore>=1.29.0",
        "pyyaml>=6.0",
        "jsonschema>=4.17.0",
        "jinja2>=3.1.0",
    ],
    
    # Optional dependencies
    extras_require={
        "dev": DEV_REQUIREMENTS,
        "docs": DOC_REQUIREMENTS,
        "all": DEV_REQUIREMENTS + DOC_REQUIREMENTS,
    },
    
    # Entry points
    entry_points={
        "console_scripts": [
            "cdk-hpc-deploy=app:main",
        ],
    },
    
    # Package metadata
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
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Distributed Computing",
        "Topic :: System :: Systems Administration",
        "Topic :: Scientific/Engineering",
    ],
    
    # Keywords for PyPI
    keywords=[
        "aws",
        "cdk",
        "hpc",
        "parallelcluster",
        "slurm",
        "high-performance-computing",
        "infrastructure",
        "cloud",
        "scientific-computing",
    ],
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/hpc-parallelcluster-cdk/issues",
        "Source": "https://github.com/aws-samples/hpc-parallelcluster-cdk",
        "Documentation": "https://docs.aws.amazon.com/parallelcluster/",
        "AWS ParallelCluster": "https://aws.amazon.com/hpc/parallelcluster/",
    },
    
    # Package data
    include_package_data=True,
    package_data={
        "": ["*.yaml", "*.yml", "*.json", "*.md", "*.txt"],
    },
    
    # Zip safe
    zip_safe=False,
)