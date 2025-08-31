"""
Setup configuration for Cross-Account Service Discovery CDK Python application.

This setup.py file configures the Python package for the CDK application
that deploys cross-account service discovery infrastructure using VPC Lattice
and Amazon ECS.
"""

import setuptools

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setuptools.setup(
    name="cross-account-service-discovery",
    version="1.0.0",
    author="AWS CDK Team",
    description="Cross-Account Service Discovery with VPC Lattice and ECS",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/aws-cdk-examples",
    packages=setuptools.find_packages(),
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Code Generators",
        "Topic :: Utilities",
        "Typing :: Typed",
    ],
    python_requires=">=3.8",
    install_requires=[
        "aws-cdk-lib==2.177.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.34.0",
        "botocore>=1.34.0",
    ],
    extras_require={
        "dev": [
            "mypy>=1.5.0",
            "black>=23.0.0",
            "pylint>=2.17.0",
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "moto>=4.2.0",
        ],
        "docs": [
            "sphinx>=7.0.0",
            "sphinx-rtd-theme>=1.3.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "cdk-deploy=app:main",
        ],
    },
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "vpc-lattice",
        "ecs",
        "service-discovery",
        "cross-account",
        "microservices",
        "container",
        "networking",
        "eventbridge",
        "cloudwatch",
        "monitoring",
    ],
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
    },
)