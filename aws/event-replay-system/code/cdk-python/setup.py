"""
Setup configuration for EventBridge Archive Event Replay Mechanisms CDK Python application.

This setup.py file configures the Python package for the CDK application that creates
a comprehensive event replay system using Amazon EventBridge Archive. The application
demonstrates event archiving, selective filtering, and controlled replay operations.
"""

from setuptools import setup, find_packages

# Read the README file for the long description
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "EventBridge Archive Event Replay Mechanisms CDK Python Application"

# Read requirements from requirements.txt
try:
    with open("requirements.txt", "r", encoding="utf-8") as fh:
        requirements = [line.strip() for line in fh if line.strip() and not line.startswith("#")]
except FileNotFoundError:
    requirements = [
        "aws-cdk-lib>=2.110.0,<3.0.0",
        "constructs>=10.3.0,<11.0.0",
        "boto3>=1.26.0",
        "typing-extensions>=4.0.0",
    ]

setup(
    name="event-replay-mechanisms-eventbridge-archive",
    version="1.0.0",
    description="CDK Python application for EventBridge Archive Event Replay Mechanisms",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS CDK Generator",
    author_email="support@aws.amazon.com",
    url="https://github.com/aws/aws-cdk",
    
    # Package configuration
    packages=find_packages(exclude=["tests*"]),
    include_package_data=True,
    zip_safe=False,
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=requirements,
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "mypy>=1.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "isort>=5.0.0",
            "moto>=4.0.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",
        ],
    },
    
    # Package classifiers
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
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Distributed Computing",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
        "Topic :: System :: Systems Administration",
        "Topic :: Software Development :: Code Generators",
        "Operating System :: OS Independent",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "eventbridge",
        "archive",
        "event-replay",
        "serverless",
        "lambda",
        "event-driven",
        "disaster-recovery",
        "infrastructure-as-code",
        "cloud-formation",
        "aws-events",
        "monitoring",
        "automation",
    ],
    
    # Entry points for command line scripts
    entry_points={
        "console_scripts": [
            "event-replay-deploy=app:main",
        ],
    },
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "AWS EventBridge": "https://docs.aws.amazon.com/eventbridge/",
        "AWS Lambda": "https://docs.aws.amazon.com/lambda/",
        "AWS CloudWatch": "https://docs.aws.amazon.com/cloudwatch/",
    },
    
    # Package metadata
    license="Apache-2.0",
    platforms=["any"],
    
    # Data files to include in the package
    package_data={
        "": ["*.md", "*.txt", "*.yaml", "*.yml", "*.json"],
    },
    
    # Manifest template for additional files
    include_package_data=True,
)