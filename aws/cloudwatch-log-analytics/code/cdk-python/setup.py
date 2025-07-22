"""
Setup configuration for CloudWatch Logs Insights Analytics CDK Application.

This setup file defines the package configuration for the CDK Python application
that deploys a complete log analytics solution using AWS CloudWatch Logs Insights,
Lambda functions, and SNS for automated monitoring and alerting.
"""

from setuptools import setup, find_packages

# Read long description from README if available
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "CloudWatch Logs Insights Analytics CDK Application"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file."""
    try:
        with open("requirements.txt", "r", encoding="utf-8") as f:
            return [line.strip() for line in f if line.strip() and not line.startswith("#")]
    except FileNotFoundError:
        return [
            "aws-cdk-lib>=2.116.0",
            "constructs>=10.0.0,<11.0.0",
            "boto3>=1.34.0"
        ]

setup(
    name="log-analytics-cdk",
    version="1.0.0",
    description="AWS CDK application for CloudWatch Logs Insights analytics solution",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS Solutions Team",
    author_email="aws-solutions@amazon.com",
    url="https://github.com/aws-samples/log-analytics-cdk",
    
    # Package configuration
    packages=find_packages(exclude=["tests", "tests.*"]),
    include_package_data=True,
    zip_safe=False,
    
    # Python version requirements
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=read_requirements(),
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "bandit>=1.7.0",
            "safety>=2.3.0"
        ],
        "docs": [
            "sphinx>=7.0.0",
            "sphinx-rtd-theme>=1.3.0"
        ]
    },
    
    # Entry points
    entry_points={
        "console_scripts": [
            "log-analytics-cdk=app:main",
        ],
    },
    
    # Classifiers for PyPI
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Monitoring",
        "Topic :: System :: Systems Administration",
        "Topic :: Utilities",
    ],
    
    # Keywords for discoverability
    keywords=[
        "aws",
        "cdk",
        "cloudwatch",
        "logs",
        "insights",
        "analytics",
        "monitoring",
        "alerting",
        "lambda",
        "sns",
        "serverless",
        "infrastructure",
        "devops"
    ],
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/log-analytics-cdk/issues",
        "Source": "https://github.com/aws-samples/log-analytics-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "AWS CloudWatch Logs": "https://aws.amazon.com/cloudwatch/",
        "AWS CDK Guide": "https://docs.aws.amazon.com/cdk/v2/guide/",
    },
    
    # Package metadata
    license="MIT",
    platforms=["any"],
    
    # Configuration for package building
    options={
        "bdist_wheel": {
            "universal": False,
        },
    },
)