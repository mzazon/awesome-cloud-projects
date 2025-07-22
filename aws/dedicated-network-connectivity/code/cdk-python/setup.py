"""
Setup configuration for Hybrid Cloud Connectivity CDK Python application.

This setup file configures the Python package for the hybrid cloud connectivity
solution using AWS CDK Python.
"""

import setuptools

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setuptools.setup(
    name="hybrid-cloud-connectivity-aws-direct-connect",
    version="1.0.0",
    author="Recipe Generator",
    author_email="recipes@aws.com",
    description="AWS CDK Python application for hybrid cloud connectivity with Direct Connect",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/recipes",
    packages=setuptools.find_packages(),
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: System :: Networking",
        "Topic :: System :: Systems Administration",
    ],
    python_requires=">=3.8",
    install_requires=[
        "aws-cdk-lib>=2.110.0",
        "constructs>=10.3.0",
        "typing-extensions>=4.0.0",
    ],
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "boto3>=1.26.0",
        ],
        "cli": [
            "awscli>=2.0.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "hybrid-connectivity-deploy=app:main",
        ],
    },
    keywords="aws cdk python direct-connect hybrid-cloud networking transit-gateway",
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/recipes/issues",
        "Source": "https://github.com/aws-samples/recipes",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
    },
)