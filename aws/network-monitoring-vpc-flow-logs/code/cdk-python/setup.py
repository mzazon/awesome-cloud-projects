"""
Setup configuration for VPC Flow Logs Network Monitoring CDK Application

This setup.py file configures the Python package for the CDK application
that implements comprehensive network monitoring using VPC Flow Logs.
"""

import setuptools

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setuptools.setup(
    name="network-monitoring-vpc-flow-logs",
    version="1.0.0",
    author="AWS CDK Recipe",
    author_email="recipes@aws.com",
    description="CDK Python application for VPC Flow Logs network monitoring",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/aws-cdk-examples",
    project_urls={
        "Bug Tracker": "https://github.com/aws-samples/aws-cdk-examples/issues",
    },
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: System :: Monitoring",
        "Topic :: System :: Networking :: Monitoring",
        "Typing :: Typed",
    ],
    packages=setuptools.find_packages(),
    python_requires=">=3.8",
    install_requires=[
        "aws-cdk-lib==2.152.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.26.0",
    ],
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=4.0.0",
            "mypy>=0.950",
            "boto3-stubs[essential]>=1.26.0",
            "types-setuptools>=57.0.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "network-monitoring=app:main",
        ],
    },
    keywords=[
        "aws",
        "cdk",
        "cloudformation",
        "infrastructure",
        "network-monitoring",
        "vpc-flow-logs",
        "security",
        "observability",
        "analytics",
    ],
    zip_safe=False,
)