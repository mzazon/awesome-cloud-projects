"""
Setup configuration for Advanced CodeBuild Pipeline CDK Python application

This setup.py file configures the Python package for the CDK application,
including dependencies, metadata, and entry points.
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
    long_description = "Advanced CodeBuild Pipeline with multi-stage builds, caching, and artifact management"

setup(
    name="advanced-codebuild-pipeline",
    version="1.0.0",
    description="AWS CDK Python application for advanced CodeBuild pipelines",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    # Author information
    author="AWS CDK Team",
    author_email="aws-cdk@amazon.com",
    
    # Package configuration
    packages=find_packages(exclude=["tests", "tests.*"]),
    include_package_data=True,
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=requirements,
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "pylint>=2.17.0",
            "mypy>=1.0.0",
            "flake8>=5.0.0",
            "isort>=5.12.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.2.0",
            "boto3-stubs[essential]>=1.28.0",
        ]
    },
    
    # Entry points for CLI commands
    entry_points={
        "console_scripts": [
            "deploy-pipeline=app:main",
        ],
    },
    
    # Classifiers for PyPI
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
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Utilities",
    ],
    
    # Keywords for searchability
    keywords=[
        "aws",
        "cdk",
        "codebuild",
        "cicd",
        "pipeline",
        "docker",
        "caching",
        "multi-stage",
        "artifacts",
        "devops",
        "infrastructure",
        "automation"
    ],
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
    },
    
    # License
    license="Apache License 2.0",
    
    # Zip safety
    zip_safe=False,
)