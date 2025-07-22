"""
Setup configuration for the CI/CD Pipeline Container Applications CDK Python project.

This setup.py file configures the Python package for the advanced CI/CD pipeline
implementation using AWS CDK Python. It includes all necessary dependencies and
metadata for the containerized application deployment pipeline.
"""

from setuptools import setup, find_packages

# Read the requirements from requirements.txt
with open("requirements.txt", "r", encoding="utf-8") as fh:
    requirements = [line.strip() for line in fh if line.strip() and not line.startswith("#")]

# Read the README file for long description
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "Advanced CI/CD Pipeline for Container Applications using AWS CDK Python"

setup(
    name="cicd-pipeline-container-applications",
    version="1.0.0",
    description="Advanced CI/CD Pipeline for Container Applications with CodePipeline and CodeDeploy",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS CDK Team",
    author_email="aws-cdk-dev@amazon.com",
    url="https://github.com/aws/aws-cdk",
    packages=find_packages(),
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Utilities",
    ],
    python_requires=">=3.8",
    install_requires=requirements,
    entry_points={
        "console_scripts": [
            "cicd-pipeline=app:main",
        ],
    },
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "cicd",
        "pipeline",
        "containers",
        "docker",
        "ecs",
        "codepipeline",
        "codedeploy",
        "codebuild",
        "blue-green",
        "canary",
        "deployment",
        "devops",
    ],
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "Tracker": "https://github.com/aws/aws-cdk/issues",
    },
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "aws-cdk.assertions>=2.120.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",
            "aws-cdk.assertions>=2.120.0",
        ],
    },
    include_package_data=True,
    zip_safe=False,
)