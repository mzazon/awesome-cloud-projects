"""
Setup configuration for Cross-Region Service Failover CDK Python Application

This setup.py file configures the Python package for the CDK application
that implements cross-region service failover using VPC Lattice and Route53.
"""

from setuptools import setup, find_packages

# Read the contents of the README file for long description
from pathlib import Path
this_directory = Path(__file__).parent
try:
    long_description = (this_directory / "README.md").read_text()
except FileNotFoundError:
    long_description = "Cross-Region Service Failover CDK Python Application"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file"""
    requirements_file = this_directory / "requirements.txt"
    if requirements_file.exists():
        with open(requirements_file, 'r') as f:
            # Filter out comments and empty lines
            requirements = [
                line.strip() 
                for line in f 
                if line.strip() and not line.strip().startswith('#')
            ]
        return requirements
    return []

setup(
    name="cross-region-failover-cdk",
    version="1.0.0",
    
    description="CDK Python application for cross-region service failover with VPC Lattice and Route53",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS Recipe Generator",
    author_email="recipes@aws.example.com",
    
    url="https://github.com/aws/recipes/aws/cross-region-service-failover-lattice-route53",
    
    packages=find_packages(exclude=["tests", "tests.*"]),
    
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Networking",
        "Topic :: System :: Systems Administration",
        "Operating System :: OS Independent",
    ],
    
    python_requires=">=3.8",
    
    install_requires=read_requirements(),
    
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "moto[all]>=4.2.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
    },
    
    entry_points={
        "console_scripts": [
            "deploy-failover=app:main",
        ],
    },
    
    keywords=[
        "aws",
        "cdk",
        "vpc-lattice", 
        "route53",
        "failover",
        "disaster-recovery",
        "microservices",
        "cross-region",
        "dns",
        "health-checks",
        "infrastructure-as-code",
    ],
    
    project_urls={
        "Bug Reports": "https://github.com/aws/recipes/issues",
        "Source": "https://github.com/aws/recipes/aws/cross-region-service-failover-lattice-route53",
        "Documentation": "https://docs.aws.amazon.com/",
    },
    
    include_package_data=True,
    zip_safe=False,
    
    # Package metadata for PyPI
    license="MIT",
    platforms=["any"],
    
    # Additional metadata
    maintainer="AWS Recipe Contributors",
    maintainer_email="recipes@aws.example.com",
    
    # Indicate this is a CDK application
    package_data={
        "": ["*.md", "*.txt", "*.yml", "*.yaml", "*.json"],
    },
)