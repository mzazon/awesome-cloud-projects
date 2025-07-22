"""
Setup configuration for the Distributed EFS CDK Python application.

This setup.py file configures the Python package for the distributed file system
implementation using Amazon EFS with AWS CDK.
"""

from setuptools import setup, find_packages

# Read the README file for long description
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "Distributed File System with Amazon EFS - CDK Python Application"

# Read requirements from requirements.txt
try:
    with open("requirements.txt", "r", encoding="utf-8") as fh:
        requirements = [line.strip() for line in fh if line.strip() and not line.startswith("#")]
except FileNotFoundError:
    requirements = [
        "aws-cdk-lib==2.140.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.28.0",
        "botocore>=1.31.0",
    ]

setup(
    name="distributed-efs-cdk",
    version="1.0.0",
    description="Distributed File System with Amazon EFS - CDK Python Application",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS Solutions Architect",
    author_email="solutions@aws.com",
    url="https://github.com/aws-samples/distributed-efs-cdk",
    license="MIT",
    
    # Package discovery
    packages=find_packages(exclude=["tests", "tests.*"]),
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=requirements,
    
    # Optional dependencies for development
    extras_require={
        "dev": [
            "mypy>=1.0.0",
            "black>=22.0.0",
            "flake8>=4.0.0",
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "autopep8>=2.0.0",
            "isort>=5.0.0",
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
            "safety>=2.0.0",
            "bandit>=1.7.0",
            "pylint>=2.15.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",
            "boto3-stubs>=1.28.0",
        ],
    },
    
    # Entry points for command line scripts
    entry_points={
        "console_scripts": [
            "deploy-distributed-efs=app:main",
        ],
    },
    
    # Package data
    include_package_data=True,
    
    # Classifiers for PyPI
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
        "Programming Language :: Python :: 3.12",
        "Topic :: System :: Filesystems",
        "Topic :: System :: Distributed Computing",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
        "Environment :: Console",
        "Framework :: AWS CDK",
        "Natural Language :: English",
    ],
    
    # Keywords for search
    keywords=[
        "aws",
        "cdk",
        "efs",
        "elastic file system",
        "distributed storage",
        "nfs",
        "cloud storage",
        "infrastructure as code",
        "amazon web services",
        "file sharing",
        "high availability",
        "multi-az",
        "backup",
        "monitoring",
        "security",
    ],
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/efs/",
        "Source": "https://github.com/aws-samples/distributed-efs-cdk",
        "Bug Reports": "https://github.com/aws-samples/distributed-efs-cdk/issues",
        "AWS CDK": "https://aws.amazon.com/cdk/",
        "Amazon EFS": "https://aws.amazon.com/efs/",
    },
    
    # Additional metadata
    zip_safe=False,
    platforms=["any"],
)