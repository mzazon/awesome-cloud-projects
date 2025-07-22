"""
Setup configuration for Global Load Balancing CDK Python application.

This setup.py file defines the package configuration and dependencies
for the CDK Python application that implements global load balancing
with Route53 and CloudFront.
"""

import os
from setuptools import setup, find_packages

# Read the README file for long description
def read_readme():
    """Read the README.md file if it exists."""
    readme_path = os.path.join(os.path.dirname(__file__), "README.md")
    if os.path.exists(readme_path):
        with open(readme_path, "r", encoding="utf-8") as f:
            return f.read()
    return "Global Load Balancing with Route53 and CloudFront - CDK Python Application"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file."""
    requirements_path = os.path.join(os.path.dirname(__file__), "requirements.txt")
    requirements = []
    
    if os.path.exists(requirements_path):
        with open(requirements_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                # Skip comments and empty lines
                if line and not line.startswith("#"):
                    requirements.append(line)
    
    return requirements

setup(
    name="global-load-balancing-cdk",
    version="1.0.0",
    description="AWS CDK Python application for global load balancing with Route53 and CloudFront",
    long_description=read_readme(),
    long_description_content_type="text/markdown",
    author="AWS CDK Generator",
    author_email="aws-samples@amazon.com",
    url="https://github.com/aws-samples/aws-cdk-examples",
    license="MIT-0",
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Networking",
        "Topic :: System :: Systems Administration",
        "Typing :: Typed",
    ],
    keywords="aws cdk cloudformation route53 cloudfront load-balancing global infrastructure",
    packages=find_packages(),
    python_requires=">=3.8",
    install_requires=read_requirements(),
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "mypy>=1.8.0",
            "black>=23.12.0",
            "flake8>=7.0.0",
            "isort>=5.13.0",
            "pre-commit>=3.6.0",
        ],
        "docs": [
            "sphinx>=7.2.0",
            "sphinx-rtd-theme>=2.0.0",
            "myst-parser>=2.0.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "global-lb-deploy=app:main",
        ],
    },
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws-samples/aws-cdk-examples",
        "Bug Reports": "https://github.com/aws-samples/aws-cdk-examples/issues",
        "AWS CDK": "https://aws.amazon.com/cdk/",
        "AWS Route53": "https://aws.amazon.com/route53/",
        "AWS CloudFront": "https://aws.amazon.com/cloudfront/",
    },
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    include_package_data=True,
    zip_safe=False,
)