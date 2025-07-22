"""
Setup configuration for MLOps Pipeline CDK Python Application

This setup script configures the Python package for the CDK application
that deploys end-to-end MLOps infrastructure with SageMaker Pipelines.
It includes all necessary dependencies and development tools for building,
testing, and deploying the infrastructure.
"""

import setuptools
from pathlib import Path

# Read the README file for long description
long_description = Path("README.md").read_text(encoding="utf-8") if Path("README.md").exists() else ""

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file."""
    requirements_file = Path("requirements.txt")
    if requirements_file.exists():
        with open(requirements_file, 'r', encoding='utf-8') as f:
            # Filter out comments and empty lines
            return [
                line.strip() 
                for line in f 
                if line.strip() and not line.startswith('#')
            ]
    return []

setuptools.setup(
    name="mlops-pipeline-cdk",
    version="1.0.0",
    description="AWS CDK Python application for end-to-end MLOps with SageMaker Pipelines",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS Solutions",
    author_email="aws-solutions@amazon.com",
    
    # Package configuration
    packages=setuptools.find_packages(),
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=read_requirements(),
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "pre-commit>=3.0.0",
        ],
        "testing": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto[all]>=4.0.0",
            "pytest-mock>=3.0.0",
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
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Scientific/Engineering :: Artificial Intelligence",
        "Typing :: Typed",
    ],
    
    # Keywords for discoverability
    keywords=[
        "aws",
        "cdk",
        "cloud-development-kit",
        "infrastructure-as-code",
        "mlops",
        "machine-learning",
        "sagemaker",
        "pipelines",
        "devops",
        "automation",
    ],
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "SageMaker Documentation": "https://docs.aws.amazon.com/sagemaker/",
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
    },
    
    # Entry points for command-line interfaces (if needed)
    entry_points={
        "console_scripts": [
            # Add CLI scripts here if needed
        ],
    },
    
    # Include additional files in the package
    include_package_data=True,
    package_data={
        "": [
            "*.md",
            "*.txt",
            "*.json",
            "*.yaml",
            "*.yml",
        ],
    },
    
    # Exclude development and testing files from distribution
    exclude_package_data={
        "": [
            "tests/*",
            "*.pyc",
            "__pycache__/*",
        ],
    },
    
    # Zip safety - CDK applications should not be zipped
    zip_safe=False,
)