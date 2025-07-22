"""
Setup configuration for Contact Form CDK application.

This package contains the AWS CDK Python application for deploying
a serverless contact form backend infrastructure.
"""

from setuptools import setup, find_packages

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setup(
    name="contact-form-cdk",
    version="1.0.0",
    author="AWS CDK Developer",
    author_email="developer@example.com",
    description="AWS CDK Python application for serverless contact form backend",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/example/contact-form-cdk",
    packages=find_packages(),
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
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
    ],
    python_requires=">=3.8",
    install_requires=[
        "aws-cdk-lib>=2.168.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "aws-cdk.aws-lambda-python-alpha>=2.168.0a0",
    ],
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "black>=23.0.0",
            "mypy>=1.5.0",
            "flake8>=6.0.0",
        ],
    },
    keywords="aws cdk python serverless lambda ses api-gateway contact-form",
    project_urls={
        "Bug Reports": "https://github.com/example/contact-form-cdk/issues",
        "Source": "https://github.com/example/contact-form-cdk",
        "Documentation": "https://github.com/example/contact-form-cdk/blob/main/README.md",
    },
)