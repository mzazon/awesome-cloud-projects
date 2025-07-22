"""
Setup configuration for the Secure File Portal CDK Python application.

This setup.py file configures the Python package for the AWS CDK application
that deploys a secure self-service file portal using AWS Transfer Family Web Apps.
"""

from setuptools import find_packages, setup

# Read long description from README if available
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "Secure self-service file portal using AWS Transfer Family Web Apps"

# Read requirements from requirements.txt
with open("requirements.txt", "r", encoding="utf-8") as fh:
    requirements = [line.strip() for line in fh if line.strip() and not line.startswith("#")]

setup(
    name="secure-file-portal-cdk",
    version="1.0.0",
    description="AWS CDK application for deploying a secure self-service file portal",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS Recipes",
    author_email="recipes@aws.com",
    url="https://github.com/aws-samples/cloud-recipes",
    packages=find_packages(where="."),
    package_dir={"": "."},
    
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: File Transfer Protocol (FTP)",
        "Topic :: Security",
    ],
    
    python_requires=">=3.8",
    install_requires=requirements,
    
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "pre-commit>=2.20.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
            "myst-parser>=0.18.0",
        ],
    },
    
    entry_points={
        "console_scripts": [
            "secure-file-portal=app:main",
        ],
    },
    
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/cloud-recipes/issues",
        "Source": "https://github.com/aws-samples/cloud-recipes",
        "Documentation": "https://aws-samples.github.io/cloud-recipes/",
    },
    
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "transfer-family",
        "s3",
        "file-sharing",
        "identity-center",
        "security",
        "self-service",
        "web-portal",
    ],
    
    zip_safe=False,
    include_package_data=True,
    
    # CDK specific metadata
    metadata={
        "cdk_version": "2.x",
        "aws_services": [
            "AWS Transfer Family",
            "Amazon S3",
            "AWS IAM Identity Center",
            "S3 Access Grants",
            "AWS IAM",
        ],
        "recipe_id": "f4a8b2d1",
        "recipe_category": "storage",
        "recipe_difficulty": "200",
    },
)