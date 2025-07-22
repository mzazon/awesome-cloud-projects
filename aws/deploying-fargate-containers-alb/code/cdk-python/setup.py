"""
Setup configuration for AWS CDK Python application.

This setup.py file configures the Python package for the Fargate Container Stack,
including metadata, dependencies, and development tools.
"""

from setuptools import setup, find_packages

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setup(
    name="fargate-container-stack",
    version="1.0.0",
    author="AWS CDK Team",
    author_email="aws-cdk-team@amazon.com",
    description="AWS CDK Python application for serverless containers with Fargate and ALB",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws/aws-cdk",
    packages=find_packages(),
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Typing :: Typed",
    ],
    python_requires=">=3.8",
    install_requires=[
        "aws-cdk-lib>=2.100.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.26.0",
    ],
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "pre-commit>=2.20.0",
        ],
        "enhanced": [
            "pydantic>=1.10.0",
            "python-dotenv>=0.20.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "fargate-container-stack=app:main",
        ],
    },
    project_urls={
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Source": "https://github.com/aws/aws-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
    },
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "fargate",
        "containers",
        "ecs",
        "docker",
        "serverless",
        "load-balancer",
        "alb",
        "ecr",
        "cloudformation",
    ],
    include_package_data=True,
    zip_safe=False,
)