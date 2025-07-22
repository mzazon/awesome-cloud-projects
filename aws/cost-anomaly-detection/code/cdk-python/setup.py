"""
Setup configuration for AWS Cost Anomaly Detection CDK Python application.

This setup.py file configures the Python package for the Cost Anomaly Detection
CDK application, including dependencies, metadata, and installation requirements.
"""

import setuptools
from pathlib import Path

# Read the README file for long description
this_directory = Path(__file__).parent
long_description = (this_directory / "README.md").read_text() if (this_directory / "README.md").exists() else ""

# Read requirements from requirements.txt
requirements_path = this_directory / "requirements.txt"
if requirements_path.exists():
    with open(requirements_path) as f:
        requirements = [line.strip() for line in f if line.strip() and not line.startswith("#")]
else:
    requirements = [
        "aws-cdk-lib==2.164.1",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.26.0",
        "botocore>=1.29.0"
    ]

setuptools.setup(
    name="cost-anomaly-detection-cdk",
    version="2.0.0",
    
    description="AWS CDK Python application for comprehensive cost anomaly detection",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS CDK Team",
    author_email="aws-cdk-team@amazon.com",
    
    url="https://github.com/aws/aws-cdk",
    
    package_dir={"": "."},
    packages=setuptools.find_packages(where="."),
    
    install_requires=requirements,
    
    python_requires=">=3.7",
    
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.7",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Code Generators",
        "Topic :: Utilities",
        "Typing :: Typed",
    ],
    
    keywords=[
        "aws",
        "cdk",
        "cost",
        "anomaly",
        "detection",
        "monitoring",
        "cloudformation",
        "infrastructure",
        "python"
    ],
    
    project_urls={
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Source": "https://github.com/aws/aws-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
    },
    
    entry_points={
        "console_scripts": [
            "cost-anomaly-cdk=app:main",
        ],
    },
    
    include_package_data=True,
    zip_safe=False,
    
    extras_require={
        "dev": [
            "pytest>=7.1.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
    },
)