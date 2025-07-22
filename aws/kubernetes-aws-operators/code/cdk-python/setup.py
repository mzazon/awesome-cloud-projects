"""
Setup configuration for Kubernetes Operators AWS Resources CDK Application

This setup.py file configures the Python package for the CDK application
that deploys infrastructure for managing AWS resources through Kubernetes operators.
"""

from setuptools import setup, find_packages

# Read requirements from requirements.txt
with open("requirements.txt") as f:
    required_packages = [
        line.strip() 
        for line in f 
        if line.strip() and not line.startswith("#")
    ]

# Read long description from README if available
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "CDK application for Kubernetes Operators managing AWS Resources"

setup(
    name="kubernetes-operators-aws-resources",
    version="1.0.0",
    author="Cloud Recipe Team",
    author_email="recipes@example.com",
    description="CDK Python application for Kubernetes Operators managing AWS Resources",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/example/kubernetes-operators-aws-resources",
    project_urls={
        "Bug Tracker": "https://github.com/example/kubernetes-operators-aws-resources/issues",
        "Documentation": "https://github.com/example/kubernetes-operators-aws-resources/wiki",
        "Source Code": "https://github.com/example/kubernetes-operators-aws-resources",
    },
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
        "Topic :: Internet :: WWW/HTTP",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
    ],
    packages=find_packages(exclude=["tests", "tests.*"]),
    python_requires=">=3.8",
    install_requires=required_packages,
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.5.0",
            "bandit>=1.7.5",
        ],
        "docs": [
            "sphinx>=7.1.0",
            "sphinx-rtd-theme>=1.3.0",
        ],
        "testing": [
            "aws-cdk.assertions>=2.110.0",
            "boto3>=1.28.0",
            "moto>=4.2.0",  # Mock AWS services for testing
        ],
    },
    entry_points={
        "console_scripts": [
            "cdk-operators=app:main",
        ],
    },
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.yaml", "*.yml", "*.json"],
    },
    zip_safe=False,
    keywords=[
        "aws",
        "cdk",
        "kubernetes",
        "operators",
        "infrastructure",
        "cloud",
        "devops",
        "automation",
        "containers",
        "eks"
    ],
    license="MIT",
    platforms=["any"],
    
    # CDK-specific metadata
    options={
        "bdist_wheel": {
            "universal": False,
        },
    },
    
    # Security and quality metadata
    download_url="https://github.com/example/kubernetes-operators-aws-resources/archive/v1.0.0.tar.gz",
    
    # Additional metadata for AWS CDK
    cdx_metadata={
        "aws_cdk_version": ">=2.110.0",
        "target_framework": "aws-cdk-lib",
        "deployment_target": "aws",
        "infrastructure_type": "kubernetes_operators",
        "supported_regions": [
            "us-east-1",
            "us-east-2", 
            "us-west-1",
            "us-west-2",
            "eu-west-1",
            "eu-west-2",
            "eu-central-1",
            "ap-southeast-1",
            "ap-southeast-2",
            "ap-northeast-1"
        ],
        "required_aws_services": [
            "eks",
            "iam", 
            "s3",
            "lambda",
            "ec2",
            "cloudwatch"
        ]
    }
)