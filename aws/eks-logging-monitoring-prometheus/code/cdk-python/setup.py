"""
Setup configuration for EKS Observability CDK Python application.

This setup.py file configures the Python package for the EKS cluster logging and monitoring
solution using AWS CDK. It includes all necessary dependencies and metadata for the project.
"""

from setuptools import setup, find_packages

# Read the contents of README file
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = """
    # EKS Observability CDK Python Application
    
    This CDK application creates a comprehensive observability stack for Amazon EKS that includes:
    - EKS cluster with comprehensive control plane logging
    - CloudWatch Container Insights for infrastructure monitoring
    - Fluent Bit for log collection and forwarding
    - Amazon Managed Service for Prometheus for metrics collection
    - CloudWatch dashboards and alarms for monitoring
    - Sample application with Prometheus metrics
    """

setup(
    name="eks-observability-cdk",
    version="1.0.0",
    description="AWS CDK Python application for EKS cluster logging and monitoring with CloudWatch and Prometheus",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS Cloud Recipes",
    author_email="recipes@aws.com",
    url="https://github.com/aws-samples/cloud-recipes",
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/cloud-recipes/issues",
        "Source": "https://github.com/aws-samples/cloud-recipes",
    },
    packages=find_packages(exclude=["tests*"]),
    python_requires=">=3.8",
    install_requires=[
        "aws-cdk-lib>=2.156.0",
        "constructs>=10.0.0,<11.0.0",
    ],
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "isort>=5.0.0",
            "types-requests>=2.0.0",
            "boto3-stubs[essential]>=1.26.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
        "test": [
            "moto>=4.0.0",
            "pytest-mock>=3.0.0",
        ],
    },
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: System :: Monitoring",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Operating System :: OS Independent",
        "Environment :: Console",
        "Framework :: AWS CDK",
        "Framework :: AWS CDK :: 2",
    ],
    keywords=[
        "aws",
        "cdk",
        "eks",
        "kubernetes",
        "monitoring",
        "observability",
        "cloudwatch",
        "prometheus",
        "logging",
        "container-insights",
        "fluent-bit",
        "infrastructure-as-code",
    ],
    entry_points={
        "console_scripts": [
            "eks-observability-cdk=app:app",
        ],
    },
    include_package_data=True,
    zip_safe=False,
)