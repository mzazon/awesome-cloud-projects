"""
Setup configuration for Advanced Serverless Data Lake CDK Application

This setup.py file configures the Python package for the serverless data lake
CDK application, including dependencies, metadata, and development tools.
"""

import setuptools
from pathlib import Path

# Read the contents of README file
this_directory = Path(__file__).parent
long_description = (this_directory / "README.md").read_text() if (this_directory / "README.md").exists() else ""

# Read requirements from requirements.txt
with open("requirements.txt") as fp:
    requirements = [
        line.strip() for line in fp.readlines()
        if line.strip() and not line.startswith("#")
    ]

setuptools.setup(
    name="advanced-serverless-datalake-cdk",
    version="1.0.0",
    
    description="Advanced Serverless Data Lake Architecture using AWS CDK",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS Solutions Architecture Team",
    author_email="aws-solutions@amazon.com",
    
    python_requires=">=3.9",
    
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Code Generators",
        "Topic :: Utilities",
        "Typing :: Typed",
    ],
    
    install_requires=requirements,
    
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.7.0",
            "flake8>=6.0.0",
            "mypy>=1.5.0",
            "types-boto3>=1.0.2",
        ],
        "docs": [
            "sphinx>=7.1.0",
            "sphinx-rtd-theme>=1.3.0",
        ]
    },
    
    packages=setuptools.find_packages(exclude=["tests*"]),
    
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.yaml", "*.yml", "*.json"],
    },
    
    entry_points={
        "console_scripts": [
            "cdk-deploy=app:main",
        ],
    },
    
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "Tracker": "https://github.com/aws/aws-cdk/issues",
    },
    
    keywords=[
        "aws",
        "cdk",
        "serverless",
        "data-lake",
        "lambda",
        "glue",
        "eventbridge",
        "s3",
        "dynamodb",
        "analytics",
        "etl",
        "cloud-infrastructure",
        "infrastructure-as-code"
    ],
    
    zip_safe=False,
)