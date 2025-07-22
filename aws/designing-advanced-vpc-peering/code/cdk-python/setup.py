"""
Setup configuration for Multi-Region VPC Peering CDK Python application.

This setup.py file configures the Python package for the CDK application
that deploys a sophisticated multi-region VPC peering architecture with
hub-and-spoke topology and complex routing scenarios.
"""

from setuptools import setup, find_packages

# Read README for long description
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "Multi-Region VPC Peering with Complex Routing Scenarios CDK Application"

# Read requirements from requirements.txt
try:
    with open("requirements.txt", "r", encoding="utf-8") as fh:
        requirements = [line.strip() for line in fh if line.strip() and not line.startswith("#")]
except FileNotFoundError:
    requirements = [
        "aws-cdk-lib>=2.120.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.26.0",
        "typing-extensions>=4.0.0"
    ]

setup(
    name="multi-region-vpc-peering-cdk",
    version="1.0.0",
    description="CDK Python application for deploying multi-region VPC peering with complex routing scenarios",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS Recipes Team",
    author_email="recipes@aws.amazon.com",
    url="https://github.com/aws/recipes/tree/main/aws/multi-region-vpc-peering-complex-routing-scenarios/code/cdk-python",
    
    packages=find_packages(exclude=["tests*"]),
    
    python_requires=">=3.8",
    
    install_requires=requirements,
    
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "pre-commit>=2.20.0"
        ],
        "docs": [
            "sphinx>=4.0.0",
            "sphinx-rtd-theme>=1.0.0",
            "myst-parser>=0.18.0"
        ]
    },
    
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
        "Topic :: System :: Networking",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: Name Service (DNS)",
        "Topic :: System :: Monitoring",
        "Framework :: AWS CDK",
        "Environment :: Console"
    ],
    
    keywords=[
        "aws",
        "cdk",
        "vpc",
        "peering",
        "networking",
        "multi-region",
        "routing",
        "infrastructure",
        "cloud",
        "hub-and-spoke",
        "transit-routing"
    ],
    
    project_urls={
        "Bug Reports": "https://github.com/aws/recipes/issues",
        "Source": "https://github.com/aws/recipes/tree/main/aws/multi-region-vpc-peering-complex-routing-scenarios/code/cdk-python",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "AWS VPC Documentation": "https://docs.aws.amazon.com/vpc/",
        "AWS Route 53 Resolver": "https://docs.aws.amazon.com/route53/latest/developerguide/resolver.html"
    },
    
    entry_points={
        "console_scripts": [
            "vpc-peering-deploy=app:main",
        ],
    },
    
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    include_package_data=True,
    
    zip_safe=False,
    
    # CDK-specific metadata
    cdk_version=">=2.120.0",
    
    # Security and compliance
    license="Apache-2.0",
    license_files=["LICENSE"],
    
    # Documentation
    documentation_url="https://docs.aws.amazon.com/cdk/",
    
    # Maintainer information
    maintainer="AWS Recipes Team",
    maintainer_email="recipes@aws.amazon.com",
    
    # Platform compatibility
    platforms=["any"],
    
    # Additional metadata for PyPI
    download_url="https://github.com/aws/recipes/archive/main.zip",
    
    # Package health indicators
    obsoletes=[],
    provides=["multi_region_vpc_peering_cdk"],
)