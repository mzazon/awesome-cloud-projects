"""
Setup configuration for EKS CloudWatch Container Insights CDK Python application.

This setup file configures the Python package for the CDK application,
including dependencies, metadata, and entry points for deployment.
"""

import setuptools


with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()


setuptools.setup(
    name="eks-cloudwatch-container-insights",
    version="1.0.0",
    
    author="AWS CDK Generator",
    author_email="example@aws.com",
    
    description="CDK Python application for EKS CloudWatch Container Insights monitoring",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    url="https://github.com/aws-samples/eks-cloudwatch-container-insights",
    
    project_urls={
        "Bug Tracker": "https://github.com/aws-samples/eks-cloudwatch-container-insights/issues",
        "Documentation": "https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/container-insights.html",
        "Source Code": "https://github.com/aws-samples/eks-cloudwatch-container-insights",
    },
    
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
        "Topic :: System :: Monitoring",
        "Topic :: System :: Systems Administration",
    ],
    
    packages=setuptools.find_packages(),
    
    install_requires=[
        "aws-cdk-lib==2.115.0",
        "constructs>=10.0.0,<11.0.0",
        "typing-extensions>=4.0.0",
        "attrs>=22.0.0",
    ],
    
    extras_require={
        "dev": [
            "black>=22.0.0",
            "flake8>=4.0.0",
            "mypy>=0.991",
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
        ],
        "aws": [
            "boto3>=1.26.0",
            "botocore>=1.29.0",
        ],
    },
    
    python_requires=">=3.8",
    
    entry_points={
        "console_scripts": [
            "eks-monitoring-deploy=app:main",
        ],
    },
    
    include_package_data=True,
    zip_safe=False,
    
    keywords=[
        "aws",
        "cdk",
        "eks",
        "kubernetes",
        "cloudwatch",
        "container-insights",
        "monitoring",
        "observability",
        "infrastructure-as-code",
    ],
    
    # Additional metadata
    license="MIT",
    platforms=["any"],
    
    # CDK-specific metadata
    package_data={
        "": ["*.md", "*.txt", "*.yaml", "*.yml", "*.json"],
    },
)