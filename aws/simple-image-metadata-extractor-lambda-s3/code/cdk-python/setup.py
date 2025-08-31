"""
Setup configuration for the Image Metadata Extractor CDK Python application

This setup.py file configures the Python package for the CDK application
that deploys a serverless image metadata extraction system using AWS Lambda and S3.
"""

import setuptools
from pathlib import Path

# Read the long description from README if it exists
readme_path = Path(__file__).parent / "README.md"
long_description = readme_path.read_text(encoding="utf-8") if readme_path.exists() else ""

# Read requirements from requirements.txt
requirements_path = Path(__file__).parent / "requirements.txt"
with open(requirements_path, encoding="utf-8") as f:
    requirements = [
        line.strip()
        for line in f
        if line.strip() and not line.startswith("#") and not line.startswith("-")
    ]

setuptools.setup(
    name="image-metadata-extractor-cdk",
    version="1.0.0",
    
    description="CDK Python application for Simple Image Metadata Extractor with Lambda and S3",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    # Author information
    author="AWS CDK Recipe Generator",
    author_email="developer@example.com",
    
    # Package information
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Code Generators",
        "Topic :: Utilities",
        "Framework :: AWS CDK",
        "Framework :: AWS CDK :: 2",
    ],
    
    # Package discovery
    packages=setuptools.find_packages(),
    
    # Dependencies
    install_requires=requirements,
    
    # Entry points for console scripts
    entry_points={
        "console_scripts": [
            "deploy-image-metadata-extractor=app:main",
        ],
    },
    
    # Additional package data
    package_data={
        "": ["*.md", "*.txt", "*.json"],
    },
    include_package_data=True,
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Source": "https://github.com/aws/aws-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
    },
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "lambda",
        "s3",
        "image-processing",
        "metadata",
        "serverless",
    ],
    
    # Zip safe
    zip_safe=False,
)