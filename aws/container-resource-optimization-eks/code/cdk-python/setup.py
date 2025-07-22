"""
Setup script for Container Resource Optimization CDK Python Application

This setup script configures the Python package for the CDK application
that implements container resource optimization and right-sizing with Amazon EKS.
"""

import setuptools
from typing import List


def read_requirements() -> List[str]:
    """Read requirements from requirements.txt file."""
    try:
        with open("requirements.txt", "r", encoding="utf-8") as f:
            requirements = []
            for line in f:
                line = line.strip()
                # Skip comments and empty lines
                if line and not line.startswith("#"):
                    # Remove inline comments
                    requirement = line.split("#")[0].strip()
                    if requirement:
                        requirements.append(requirement)
            return requirements
    except FileNotFoundError:
        return [
            "aws-cdk-lib==2.114.1",
            "constructs>=10.0.0,<11.0.0",
            "typing-extensions>=4.0.0",
        ]


setuptools.setup(
    name="container-resource-optimization",
    version="1.0.0",
    description="CDK Python application for container resource optimization and right-sizing with Amazon EKS",
    long_description="""
    A comprehensive AWS CDK Python application that implements automated container 
    resource optimization using Kubernetes Vertical Pod Autoscaler (VPA) and AWS 
    cost monitoring tools on Amazon EKS.
    
    This application deploys:
    - Amazon EKS cluster with managed node groups (On-Demand and Spot)
    - VPC with public and private subnets
    - CloudWatch Container Insights for detailed monitoring
    - Cost optimization dashboard and alerts
    - Lambda function for automated cost analysis
    - SNS notifications for optimization opportunities
    - Comprehensive IAM roles and policies
    
    The solution helps organizations reduce cloud costs by 20-40% through intelligent
    resource right-sizing and automated optimization recommendations.
    """,
    long_description_content_type="text/markdown",
    author="AWS Recipes Project",
    author_email="aws-recipes@example.com",
    url="https://github.com/aws-recipes/container-resource-optimization",
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/eks/latest/best-practices/cost-opt.html",
        "Source": "https://github.com/aws-recipes/container-resource-optimization",
        "Bug Reports": "https://github.com/aws-recipes/container-resource-optimization/issues",
    },
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators", 
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: System :: Systems Administration",
        "Topic :: System :: Monitoring",
        "Topic :: Utilities",
    ],
    license="Apache License 2.0",
    packages=setuptools.find_packages(),
    python_requires=">=3.8",
    install_requires=read_requirements(),
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "boto3-stubs[essential]>=1.34.0",
        ],
        "cli": [
            "awscli>=1.32.0",
            "aws-cdk>=2.114.1",
        ],
    },
    entry_points={
        "console_scripts": [
            "container-optimization=app:main",
        ],
    },
    include_package_data=True,
    zip_safe=False,
    keywords=[
        "aws",
        "cdk",
        "eks",
        "kubernetes",
        "cost-optimization",
        "container",
        "resource-optimization",
        "finops",
        "vpa",
        "cloudwatch",
        "monitoring",
    ],
)