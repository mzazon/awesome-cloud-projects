"""
Setup configuration for the AWS CDK Python Cost Anomaly Detection application.

This setup.py file configures the Python package for the Cost Anomaly Detection
CDK application, including metadata, dependencies, and development requirements.
"""

import setuptools


def read_long_description():
    """Read the long description from README if available."""
    try:
        with open("README.md", "r", encoding="utf-8") as fh:
            return fh.read()
    except FileNotFoundError:
        return "AWS CDK Python application for automated cost anomaly detection with CloudWatch and Lambda"


# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file."""
    try:
        with open("requirements.txt", "r", encoding="utf-8") as fh:
            return [line.strip() for line in fh if line.strip() and not line.startswith("#")]
    except FileNotFoundError:
        return [
            "aws-cdk-lib>=2.80.0,<3.0.0",
            "constructs>=10.0.0,<11.0.0",
            "boto3>=1.26.0",
            "botocore>=1.29.0"
        ]


setuptools.setup(
    name="cost-anomaly-detection-cdk",
    version="1.0.0",
    
    description="AWS CDK Python application for automated cost anomaly detection",
    long_description=read_long_description(),
    long_description_content_type="text/markdown",
    
    author="AWS Solutions",
    author_email="solutions@amazon.com",
    
    license="MIT-0",
    
    url="https://github.com/aws-samples/cost-anomaly-detection-cdk",
    
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP",
        "Topic :: Office/Business :: Financial",
    ],
    
    # Specify Python version requirements
    python_requires=">=3.8",
    
    # Package discovery
    packages=setuptools.find_packages(exclude=["tests*"]),
    
    # Include package data
    include_package_data=True,
    
    # Package dependencies
    install_requires=read_requirements(),
    
    # Development dependencies
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
            "sphinx-autodoc-typehints>=1.19.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",  # AWS service mocking for tests
            "boto3-stubs[essential]>=1.26.0",  # Type stubs for boto3
        ]
    },
    
    # Entry points for command-line tools (if needed)
    entry_points={
        "console_scripts": [
            "deploy-cost-anomaly=app:main",
        ],
    },
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "cloudformation",
        "cost-management",
        "finops",
        "anomaly-detection",
        "cloudwatch",
        "lambda",
        "sns",
        "eventbridge",
        "infrastructure-as-code",
        "devops"
    ],
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/cost-anomaly-detection-cdk/issues",
        "Source": "https://github.com/aws-samples/cost-anomaly-detection-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "AWS Cost Management": "https://aws.amazon.com/aws-cost-management/",
        "AWS CDK": "https://aws.amazon.com/cdk/",
    },
    
    # Package metadata
    zip_safe=False,
    
    # Platform requirements
    platforms=["any"],
)