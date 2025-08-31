"""
Setup configuration for Microservice Authorization with VPC Lattice and IAM CDK Python application.

This setup.py file defines the package configuration for the CDK Python application
that implements fine-grained microservice authorization using VPC Lattice and IAM.
"""

import setuptools
from pathlib import Path

# Read the README file for long description
this_directory = Path(__file__).parent
long_description = (this_directory / "README.md").read_text() if (this_directory / "README.md").exists() else ""

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file."""
    requirements_file = this_directory / "requirements.txt"
    if requirements_file.exists():
        with open(requirements_file, 'r') as f:
            requirements = []
            for line in f:
                line = line.strip()
                # Skip comments and empty lines
                if line and not line.startswith('#'):
                    # Remove inline comments
                    requirement = line.split('#')[0].strip()
                    if requirement:
                        requirements.append(requirement)
            return requirements
    return []

setuptools.setup(
    name="microservice-authorization-vpc-lattice-iam",
    version="1.0.0",
    
    description="CDK Python application for implementing microservice authorization with VPC Lattice and IAM",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS Solutions Architecture",
    author_email="aws-solutions@amazon.com",
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: System :: Networking",
        "Topic :: Security",
        "Topic :: Internet :: WWW/HTTP :: HTTP Servers",
    ],
    
    keywords=[
        "aws",
        "cdk",
        "vpc-lattice",
        "iam",
        "microservices",
        "authorization",
        "zero-trust",
        "networking",
        "security",
        "lambda",
        "cloudwatch"
    ],
    
    packages=setuptools.find_packages(),
    
    install_requires=read_requirements(),
    
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.0.0",
            "mypy>=1.5.0",
            "flake8>=6.0.0",
            "isort>=5.12.0",
        ]
    },
    
    entry_points={
        "console_scripts": [
            "microservice-auth-deploy=app:main",
        ],
    },
    
    project_urls={
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Source": "https://github.com/aws/aws-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "VPC Lattice Docs": "https://docs.aws.amazon.com/vpc-lattice/",
    },
    
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    include_package_data=True,
    zip_safe=False,
)