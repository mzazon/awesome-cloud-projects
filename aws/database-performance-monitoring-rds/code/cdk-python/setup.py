"""
Setup configuration for the Database Performance Monitoring with RDS Performance Insights CDK Python application.

This setup.py file configures the Python package for the CDK application, including
dependencies, metadata, and installation requirements.
"""

from setuptools import setup, find_packages

# Read the contents of the README file for long description
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = """
    # Database Performance Monitoring with RDS Performance Insights

    This CDK Python application creates a comprehensive database performance monitoring system
    using AWS RDS Performance Insights, Lambda functions, CloudWatch monitoring, and automated
    alerting capabilities.

    ## Features

    - RDS MySQL instance with Performance Insights enabled
    - Lambda-based automated performance analysis
    - CloudWatch alarms and custom metrics
    - S3 storage for performance reports
    - SNS notifications for alerts
    - EventBridge scheduling for automation
    - Comprehensive CloudWatch dashboard

    ## Prerequisites

    - AWS CLI configured
    - Python 3.8 or later
    - AWS CDK v2 installed
    - Appropriate AWS permissions

    ## Installation

    ```bash
    pip install -r requirements.txt
    cdk deploy
    ```
    """

setup(
    name="database-performance-monitoring-cdk",
    version="1.0.0",
    description="CDK Python application for database performance monitoring with RDS Performance Insights",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS CDK Generator",
    author_email="devops@example.com",
    url="https://github.com/your-org/database-performance-monitoring-cdk",
    
    # Package discovery
    packages=find_packages(exclude=["tests", "tests.*"]),
    include_package_data=True,
    
    # Python version requirements
    python_requires=">=3.8",
    
    # Package dependencies
    install_requires=[
        "aws-cdk-lib>=2.100.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
    ],
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=0.991",
            "boto3-stubs[rds,lambda,s3,sns,events,cloudwatch,iam,logs,ec2]",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",  # For mocking AWS services in tests
        ],
    },
    
    # Package classification
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
        "Topic :: Database",
        "Topic :: System :: Systems Administration",
    ],
    
    # Keywords for discoverability
    keywords=[
        "aws",
        "cdk",
        "database",
        "performance",
        "monitoring",
        "rds",
        "performance-insights",
        "cloudwatch",
        "lambda",
        "automation",
        "infrastructure-as-code",
        "mysql",
        "observability",
        "alerting",
    ],
    
    # Entry points for command-line tools (if any)
    entry_points={
        "console_scripts": [
            # Add any command-line tools here
            # "db-perf-monitor=database_performance_monitoring.cli:main",
        ],
    },
    
    # Additional metadata
    project_urls={
        "Bug Reports": "https://github.com/your-org/database-performance-monitoring-cdk/issues",
        "Source": "https://github.com/your-org/database-performance-monitoring-cdk",
        "Documentation": "https://github.com/your-org/database-performance-monitoring-cdk/blob/main/README.md",
    },
    
    # License
    license="MIT",
    
    # Zip safety
    zip_safe=False,
    
    # Package data
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
)