"""
Setup configuration for ECS Environment Variable Management CDK Python application.

This setup.py file configures the Python package for the CDK application that
implements comprehensive environment variable management for Amazon ECS task definitions.
"""

from setuptools import setup, find_packages

# Read the README file for long description
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "CDK Python application for ECS Task Definitions with Environment Variable Management"

# Read requirements from requirements.txt
try:
    with open("requirements.txt", "r", encoding="utf-8") as fh:
        requirements = [line.strip() for line in fh if line.strip() and not line.startswith("#")]
except FileNotFoundError:
    requirements = [
        "aws-cdk-lib==2.155.0",
        "constructs>=10.0.0,<11.0.0",
    ]

setup(
    name="ecs-environment-variable-management",
    version="1.0.0",
    description="CDK Python application for ECS Task Definitions with comprehensive environment variable management",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS Recipe Contributors",
    author_email="aws-recipes@example.com",
    url="https://github.com/aws-samples/aws-recipes",
    
    # Package discovery
    packages=find_packages(exclude=["tests", "tests.*"]),
    
    # Include package data files
    include_package_data=True,
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Package dependencies
    install_requires=requirements,
    
    # Development dependencies
    extras_require={
        "dev": [
            "mypy>=1.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "coverage>=7.0.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",
            "boto3-stubs[essential]>=1.34.0",
        ],
    },
    
    # Package classifiers for PyPI
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
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP",
        "Framework :: AWS CDK",
        "Framework :: AWS CDK :: 2",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "ecs",
        "environment-variables",
        "parameter-store",
        "secrets-manager",
        "s3",
        "containers",
        "devops",
        "infrastructure-as-code",
        "fargate",
        "docker",
        "configuration-management",
    ],
    
    # Entry points for command-line scripts
    entry_points={
        "console_scripts": [
            "ecs-envvar-deploy=app:main",
        ],
    },
    
    # Package metadata
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws-samples/aws-recipes",
        "Tracker": "https://github.com/aws-samples/aws-recipes/issues",
    },
    
    # License
    license="MIT",
    
    # Zip safe configuration
    zip_safe=False,
)