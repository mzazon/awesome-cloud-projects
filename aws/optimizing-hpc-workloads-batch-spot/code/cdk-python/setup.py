"""
Setup configuration for the HPC Batch Spot CDK Python application.

This package deploys AWS infrastructure for optimizing high-performance computing
workloads using AWS Batch with Spot instances, including shared storage and monitoring.
"""

import setuptools
from pathlib import Path

# Read the long description from README if it exists
try:
    long_description = (Path(__file__).parent / "README.md").read_text(encoding="utf-8")
except FileNotFoundError:
    long_description = "AWS CDK Python application for HPC workloads with AWS Batch and Spot Instances"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file."""
    requirements_path = Path(__file__).parent / "requirements.txt"
    if requirements_path.exists():
        with open(requirements_path, 'r', encoding='utf-8') as f:
            requirements = []
            for line in f:
                line = line.strip()
                # Skip empty lines and comments
                if line and not line.startswith('#'):
                    # Remove inline comments
                    req = line.split('#')[0].strip()
                    if req:
                        requirements.append(req)
            return requirements
    return [
        "aws-cdk-lib==2.167.1",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.26.0"
    ]

setuptools.setup(
    name="hpc-batch-spot-cdk",
    version="1.0.0",
    
    description="AWS CDK Python application for HPC workloads with AWS Batch and Spot Instances",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS CDK Generator",
    author_email="devops@example.com",
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Intended Audience :: Science/Research",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: Scientific/Engineering",
        "Topic :: System :: Distributed Computing",
    ],
    
    keywords=[
        "aws", "cdk", "batch", "spot-instances", "hpc", 
        "high-performance-computing", "cost-optimization", 
        "infrastructure-as-code", "cloud-computing"
    ],
    
    packages=setuptools.find_packages(exclude=["tests*"]),
    
    install_requires=read_requirements(),
    
    extras_require={
        "dev": [
            "mypy>=1.0.0",
            "black>=23.0.0",
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "flake8>=6.0.0",
            "isort>=5.12.0",
        ],
        "testing": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",
            "aws-cdk.assertions>=2.167.1",
        ],
    },
    
    entry_points={
        "console_scripts": [
            "hpc-batch-spot=app:main",
        ],
    },
    
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/recipes/issues",
        "Source": "https://github.com/aws-samples/recipes",
        "Documentation": "https://github.com/aws-samples/recipes/tree/main/aws/optimizing-high-performance-computing-workloads-with-aws-batch-and-spot-instances",
    },
    
    include_package_data=True,
    zip_safe=False,
)