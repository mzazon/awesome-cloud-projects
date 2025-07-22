"""
Setup configuration for GPU Workload CDK Python application.

This setup.py file configures the Python package for the AWS CDK application
that deploys GPU-accelerated workloads using EC2 P4 and G4 instances.

The package includes:
- Complete infrastructure for GPU computing workloads
- P4 instances for ML training with NVIDIA A100 GPUs
- G4 instances for inference with NVIDIA T4 GPUs  
- Comprehensive monitoring and cost optimization
- Security configurations and IAM roles
"""

import os
from setuptools import setup, find_packages

# Read the README file for long description
def read_readme():
    """Read README.md file for package description."""
    readme_path = os.path.join(os.path.dirname(__file__), "README.md")
    if os.path.exists(readme_path):
        with open(readme_path, "r", encoding="utf-8") as f:
            return f.read()
    return "AWS CDK Python application for GPU-accelerated workloads"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file."""
    requirements_path = os.path.join(os.path.dirname(__file__), "requirements.txt")
    if os.path.exists(requirements_path):
        with open(requirements_path, "r", encoding="utf-8") as f:
            return [
                line.strip() 
                for line in f 
                if line.strip() and not line.startswith("#")
            ]
    return []

setup(
    name="gpu-workload-cdk",
    version="1.0.0",
    
    # Package metadata
    description="AWS CDK Python application for deploying GPU-accelerated workloads",
    long_description=read_readme(),
    long_description_content_type="text/markdown",
    
    # Author information
    author="AWS Solutions Architecture Team",
    author_email="aws-solutions@amazon.com",
    
    # Project URLs
    url="https://github.com/aws-samples/gpu-workload-cdk",
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws-samples/gpu-workload-cdk",
        "Tracker": "https://github.com/aws-samples/gpu-workload-cdk/issues",
    },
    
    # Package configuration
    packages=find_packages(exclude=["tests*"]),
    include_package_data=True,
    zip_safe=False,
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Package dependencies
    install_requires=read_requirements(),
    
    # Optional dependencies for development
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "mypy>=1.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "isort>=5.12.0",
            "pre-commit>=3.0.0",
            "bandit>=1.7.0",
        ],
        "docs": [
            "sphinx>=6.0.0",
            "sphinx-rtd-theme>=1.3.0",
        ],
        "testing": [
            "moto>=4.2.0",
            "boto3-stubs[essential]>=1.34.0",
        ],
    },
    
    # Package classification
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Distributed Computing",
        "Topic :: Scientific/Engineering :: Artificial Intelligence",
        "Typing :: Typed",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "gpu",
        "machine-learning",
        "hpc",
        "ec2",
        "p4",
        "g4",
        "nvidia",
        "cuda",
    ],
    
    # Entry points for command-line tools
    entry_points={
        "console_scripts": [
            "gpu-workload-deploy=app:main",
        ],
    },
    
    # License
    license="Apache License 2.0",
    
    # Additional metadata
    platforms=["any"],
    
    # Package data
    package_data={
        "": ["*.md", "*.txt", "*.yaml", "*.yml", "*.json"],
    },
)