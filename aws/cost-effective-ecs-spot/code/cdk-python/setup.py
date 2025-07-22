"""
Setup configuration for Cost-Effective ECS Clusters with Spot Instances CDK Application

This setup.py file configures the Python package for the CDK application that
creates cost-effective ECS clusters using EC2 Spot Instances.
"""

from setuptools import setup, find_packages

# Read the contents of README file
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "Cost-Effective ECS Clusters with EC2 Spot Instances CDK Application"

# Read requirements from requirements.txt
try:
    with open("requirements.txt", "r", encoding="utf-8") as fh:
        requirements = [line.strip() for line in fh if line.strip() and not line.startswith("#")]
except FileNotFoundError:
    requirements = [
        "aws-cdk-lib==2.165.0",
        "constructs>=10.0.0,<11.0.0",
    ]

setup(
    name="cost-effective-ecs-clusters-cdk",
    version="1.0.0",
    description="AWS CDK application for creating cost-effective ECS clusters with EC2 Spot Instances",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS CDK Team",
    author_email="your-email@example.com",
    url="https://github.com/your-org/cost-effective-ecs-clusters-cdk",
    packages=find_packages(),
    
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Code Generators",
        "Topic :: System :: Systems Administration",
        "Topic :: Utilities",
    ],
    
    python_requires=">=3.8",
    install_requires=requirements,
    
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
        ],
        "docs": [
            "sphinx>=4.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
    },
    
    entry_points={
        "console_scripts": [
            "cost-effective-ecs-cdk=app:main",
        ],
    },
    
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "ecs",
        "spot-instances",
        "containers",
        "cost-optimization",
        "devops",
        "automation",
    ],
    
    project_urls={
        "Bug Reports": "https://github.com/your-org/cost-effective-ecs-clusters-cdk/issues",
        "Source": "https://github.com/your-org/cost-effective-ecs-clusters-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
    },
    
    # Include package data
    include_package_data=True,
    zip_safe=False,
    
    # Metadata for package discovery
    license="Apache-2.0",
    platforms=["any"],
    
    # Package metadata
    maintainer="AWS CDK Team",
    maintainer_email="your-email@example.com",
    
    # Additional metadata
    download_url="https://github.com/your-org/cost-effective-ecs-clusters-cdk/archive/v1.0.0.tar.gz",
)