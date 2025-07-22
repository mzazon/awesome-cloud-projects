"""
Setup configuration for Multi-VPC Transit Gateway Architecture CDK Python application.

This setup script configures the Python package for the CDK application,
including dependencies, metadata, and development tools.
"""

import pathlib
from setuptools import setup, find_packages

# Read the contents of README file
HERE = pathlib.Path(__file__).parent
README = (HERE / "README.md").read_text() if (HERE / "README.md").exists() else "Multi-VPC Transit Gateway Architecture CDK Python Application"

# Read requirements from requirements.txt
REQUIREMENTS = []
requirements_file = HERE / "requirements.txt"
if requirements_file.exists():
    with open(requirements_file) as f:
        REQUIREMENTS = [
            line.strip() 
            for line in f 
            if line.strip() and not line.startswith('#')
        ]

setup(
    name="multi-vpc-transit-gateway-cdk",
    version="1.0.0",
    
    # Package metadata
    description="AWS CDK Python application for Multi-VPC Transit Gateway Architecture with Route Table Management",
    long_description=README,
    long_description_content_type="text/markdown",
    
    # Author information
    author="AWS CDK Python Generator",
    author_email="infrastructure@example.com",
    
    # URLs
    url="https://github.com/example/multi-vpc-transit-gateway-cdk",
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/example/multi-vpc-transit-gateway-cdk",
        "Bug Reports": "https://github.com/example/multi-vpc-transit-gateway-cdk/issues",
    },
    
    # Package discovery
    packages=find_packages(exclude=["tests", "tests.*"]),
    
    # Python version requirements
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=REQUIREMENTS,
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "safety>=2.0.0",
            "bandit>=1.7.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",  # AWS service mocking for tests
        ],
    },
    
    # Entry points for CLI commands
    entry_points={
        "console_scripts": [
            "multi-vpc-tgw-deploy=app:main",
        ],
    },
    
    # Package classification
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Networking",
        "Topic :: System :: Systems Administration",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Operating System :: OS Independent",
        "Environment :: Console",
        "Framework :: AWS CDK",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "infrastructure-as-code",
        "transit-gateway",
        "vpc",
        "networking",
        "route-tables",
        "multi-vpc",
        "enterprise-architecture",
        "cloud-infrastructure",
        "network-segmentation",
        "zero-trust",
        "security",
    ],
    
    # License
    license="Apache License 2.0",
    
    # Include additional files
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.yaml", "*.yml", "*.json"],
    },
    
    # Zip safety
    zip_safe=False,
    
    # Platform compatibility
    platforms=["any"],
    
    # CDK-specific metadata
    cdk_version="2.121.1",
    
    # Additional options
    options={
        "bdist_wheel": {
            "universal": False,
        },
    },
)