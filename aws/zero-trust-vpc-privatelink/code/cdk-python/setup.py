"""
Setup configuration for Zero Trust Network Architecture CDK Python application.

This setup.py file configures the Python package for the CDK application
that implements a complete zero trust network architecture using AWS VPC
endpoints and PrivateLink services.
"""

import setuptools

# Read the README file for long description
with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

# Read requirements from requirements.txt
with open("requirements.txt", "r", encoding="utf-8") as fh:
    requirements = [line.strip() for line in fh if line.strip() and not line.startswith("#")]

setuptools.setup(
    name="zero-trust-network-cdk",
    version="1.0.0",
    
    author="AWS CDK Team",
    author_email="aws-cdk-dev@amazon.com",
    
    description="CDK Python application for Zero Trust Network Architecture with VPC Endpoints and PrivateLink",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    url="https://github.com/aws/aws-cdk",
    
    packages=setuptools.find_packages(),
    
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
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: System :: Networking",
        "Topic :: Security",
        "Typing :: Typed",
    ],
    
    python_requires=">=3.8",
    
    install_requires=requirements,
    
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
    },
    
    entry_points={
        "console_scripts": [
            "zero-trust-network=app:main",
        ],
    },
    
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "zero-trust",
        "vpc-endpoints",
        "privatelink",
        "networking",
        "security"
    ],
    
    project_urls={
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Source": "https://github.com/aws/aws-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "AWS CDK Guide": "https://docs.aws.amazon.com/cdk/latest/guide/",
    },
)