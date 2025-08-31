"""
Setup configuration for Advanced Request Routing CDK Python application.

This setup.py file configures the Python package for the CDK application
that demonstrates sophisticated layer 7 routing across multiple VPCs using
VPC Lattice service networks integrated with Application Load Balancers.

Author: AWS CDK Team
Version: 1.0
"""

import setuptools
from pathlib import Path

# Read the README file for the long description
readme_path = Path(__file__).parent / "README.md"
long_description = readme_path.read_text(encoding="utf-8") if readme_path.exists() else ""

# Read requirements from requirements.txt
requirements_path = Path(__file__).parent / "requirements.txt"
install_requires = []
if requirements_path.exists():
    with open(requirements_path, 'r', encoding='utf-8') as f:
        install_requires = [
            line.strip() 
            for line in f 
            if line.strip() and not line.startswith('#') and not line.startswith('-')
        ]

setuptools.setup(
    name="advanced-request-routing-lattice-alb",
    version="1.0.0",
    
    description="AWS CDK application for advanced request routing with VPC Lattice and ALB",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS CDK Team",
    author_email="aws-cdk-team@amazon.com",
    
    python_requires=">=3.8",
    
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
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP",
        "Topic :: System :: Networking",
        "Typing :: Typed",
    ],
    
    keywords=[
        "aws",
        "cdk",
        "cloud-development-kit",
        "infrastructure-as-code",
        "vpc-lattice",
        "application-load-balancer",
        "microservices",
        "routing",
        "networking",
        "layer-7",
        "service-mesh"
    ],
    
    packages=setuptools.find_packages(exclude=["tests*"]),
    
    install_requires=install_requires,
    
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "pre-commit>=2.20.0",
        ],
        "security": [
            "cdk-nag>=2.0.0",
            "bandit>=1.7.0",
            "safety>=2.0.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
            "myst-parser>=0.18.0",
        ]
    },
    
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "VPC Lattice Documentation": "https://docs.aws.amazon.com/vpc-lattice/",
        "Application Load Balancer Documentation": "https://docs.aws.amazon.com/elasticloadbalancing/latest/application/",
    },
    
    # Entry points for CLI commands (if needed)
    entry_points={
        "console_scripts": [
            "deploy-advanced-routing=app:main",
        ],
    },
    
    # Package data and additional files
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.yaml", "*.yml", "*.json"],
    },
    
    # Zip safety
    zip_safe=False,
)