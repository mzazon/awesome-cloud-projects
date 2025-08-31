"""
Setup configuration for gRPC Microservices with VPC Lattice CDK Application.

This setup.py file configures the Python package for the CDK application,
including dependencies, metadata, and development tools configuration.
"""

from setuptools import setup, find_packages

# Read README file for long description
with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

# Read requirements from requirements.txt
with open("requirements.txt", "r", encoding="utf-8") as fh:
    requirements = [line.strip() for line in fh if line.strip() and not line.startswith("#")]

setup(
    name="grpc-microservices-lattice-cloudwatch",
    version="1.0.0",
    author="AWS Recipe Generator",
    description="CDK Python application for gRPC Microservices with VPC Lattice and CloudWatch",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/recipes",
    packages=find_packages(),
    python_requires=">=3.8",
    install_requires=[
        "aws-cdk-lib>=2.161.1",
        "constructs>=10.0.0,<11.0.0",
    ],
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "types-setuptools>=65.0.0",
            "bandit>=1.7.0",
            "isort>=5.12.0",
            "pre-commit>=3.0.0",
        ]
    },
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: Internet :: WWW/HTTP :: HTTP Servers",
        "Topic :: System :: Distributed Computing",
    ],
    keywords="aws cdk grpc microservices vpc-lattice cloudwatch monitoring",
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/recipes/issues",
        "Source": "https://github.com/aws-samples/recipes",
        "Documentation": "https://github.com/aws-samples/recipes/tree/main/aws/grpc-microservices-lattice-cloudwatch",
    },
)