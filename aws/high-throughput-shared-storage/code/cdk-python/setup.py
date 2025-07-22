"""
Setup configuration for High-Performance File Systems with Amazon FSx CDK application.

This package provides Infrastructure as Code for deploying comprehensive
Amazon FSx file systems including Lustre, Windows File Server, and NetApp ONTAP
with supporting infrastructure and monitoring.
"""

import setuptools
from pathlib import Path

# Read the README file for long description
readme_path = Path(__file__).parent / "README.md"
long_description = readme_path.read_text() if readme_path.exists() else ""

# Read requirements from requirements.txt
requirements_path = Path(__file__).parent / "requirements.txt"
if requirements_path.exists():
    with open(requirements_path) as f:
        requirements = [line.strip() for line in f if line.strip() and not line.startswith('#')]
else:
    requirements = [
        "aws-cdk-lib>=2.100.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.26.0",
        "botocore>=1.29.0"
    ]

setuptools.setup(
    name="high-performance-fsx-cdk",
    version="1.0.0",
    description="CDK Python application for high-performance file systems with Amazon FSx",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS Solutions Architect",
    author_email="aws-solutions@example.com",
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: System :: Systems Administration",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: Internet :: WWW/HTTP",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
    ],
    
    keywords=[
        "aws",
        "cdk",
        "infrastructure",
        "file-systems",
        "fsx",
        "lustre", 
        "windows-file-server",
        "netapp-ontap",
        "high-performance-computing",
        "hpc",
        "storage"
    ],
    
    packages=setuptools.find_packages(),
    
    install_requires=requirements,
    
    extras_require={
        "dev": [
            "mypy>=1.0.0",
            "black>=22.0.0",
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "flake8>=5.0.0",
            "isort>=5.10.0"
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
            "myst-parser>=0.18.0"
        ]
    },
    
    entry_points={
        "console_scripts": [
            "deploy-fsx=app:main",
        ],
    },
    
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/high-performance-fsx-cdk/issues",
        "Source": "https://github.com/aws-samples/high-performance-fsx-cdk",
        "Documentation": "https://docs.aws.amazon.com/fsx/",
    },
    
    include_package_data=True,
    zip_safe=False,
    
    # Metadata for package discovery
    package_data={
        "": ["*.md", "*.txt", "*.yml", "*.yaml", "*.json"],
    },
)