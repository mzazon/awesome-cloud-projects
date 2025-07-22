"""
Setup configuration for Advanced Multi-Service Monitoring Dashboards CDK Python application.

This setup.py file defines the Python package configuration for the CDK application,
including dependencies, metadata, and installation requirements.
"""

from setuptools import setup, find_packages

# Read requirements from requirements.txt
with open("requirements.txt", "r", encoding="utf-8") as f:
    requirements = [line.strip() for line in f if line.strip() and not line.startswith("#")]

# Read README for long description
try:
    with open("README.md", "r", encoding="utf-8") as f:
        long_description = f.read()
except FileNotFoundError:
    long_description = "Advanced Multi-Service Monitoring Dashboards with Custom Metrics and Anomaly Detection"

setup(
    name="advanced-monitoring-dashboards",
    version="1.0.0",
    description="Advanced Multi-Service Monitoring Dashboards with Custom Metrics and Anomaly Detection",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS CDK Team",
    author_email="aws-cdk-team@amazon.com",
    url="https://github.com/aws/aws-cdk",
    license="Apache-2.0",
    
    # Package discovery
    packages=find_packages(exclude=["tests", "tests.*"]),
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=requirements,
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "boto3-stubs[essential]>=1.26.0",
            "types-requests>=2.28.0"
        ]
    },
    
    # Package metadata
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
        "Topic :: System :: Monitoring",
        "Topic :: System :: Systems Administration",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "cloudwatch",
        "monitoring",
        "dashboards",
        "metrics",
        "anomaly-detection",
        "alerting",
        "observability",
        "infrastructure"
    ],
    
    # Entry points for command line tools
    entry_points={
        "console_scripts": [
            "deploy-monitoring=app:main",
        ],
    },
    
    # Include additional files
    include_package_data=True,
    
    # Package data
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # Zip safety
    zip_safe=False,
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Source": "https://github.com/aws/aws-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Funding": "https://github.com/sponsors/aws",
    },
)