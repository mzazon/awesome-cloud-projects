"""
Setup configuration for the Static Website Hosting CDK Python application.

This setup file defines the package configuration for the CDK application
that creates a static website hosting solution with S3, CloudFront, and Route 53.
"""

import pathlib
from setuptools import setup, find_packages

# Read the contents of README file
here = pathlib.Path(__file__).parent.resolve()
long_description = (here / "README.md").read_text(encoding="utf-8") if (here / "README.md").exists() else ""

# Read requirements from requirements.txt
requirements = []
requirements_path = here / "requirements.txt"
if requirements_path.exists():
    with open(requirements_path, "r", encoding="utf-8") as f:
        requirements = [
            line.strip() for line in f
            if line.strip() and not line.startswith("#")
        ]

setup(
    name="static-website-hosting-cdk",
    version="1.0.0",
    description="AWS CDK Python application for static website hosting with S3, CloudFront, and Route 53",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS CDK Team",
    author_email="aws-cdk-team@amazon.com",
    url="https://github.com/aws/aws-cdk",
    project_urls={
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Source": "https://github.com/aws/aws-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
    },
    packages=find_packages(),
    python_requires=">=3.8",
    install_requires=requirements,
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "types-boto3>=1.0.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.2.0",
        ],
    },
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
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
    keywords="aws cdk cloudformation s3 cloudfront route53 static website hosting",
    entry_points={
        "console_scripts": [
            "deploy-website=app:main",
        ],
    },
    include_package_data=True,
    zip_safe=False,
)