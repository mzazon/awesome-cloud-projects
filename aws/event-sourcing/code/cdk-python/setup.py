"""
Setup configuration for Event Sourcing Architecture CDK Application

This setup.py file configures the Python package for the CDK application,
including dependencies, metadata, and development tools configuration.
"""

from setuptools import setup, find_packages

# Read long description from README (if available)
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "Event Sourcing Architecture CDK Application"

# Read requirements from requirements.txt
with open("requirements.txt", "r", encoding="utf-8") as fh:
    requirements = [line.strip() for line in fh if line.strip() and not line.startswith("#")]

setup(
    name="event-sourcing-cdk",
    version="1.0.0",
    author="AWS CDK Team",
    author_email="cdk-team@example.com",
    description="CDK application for Event Sourcing Architecture with EventBridge and DynamoDB",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/event-sourcing-cdk",
    packages=find_packages(),
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: System :: Distributed Computing",
        "Topic :: Database :: Database Engines/Servers",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content"
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
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0"
        ],
        "testing": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",
            "boto3-stubs>=1.26.0"
        ]
    },
    entry_points={
        "console_scripts": [
            "event-sourcing-cdk=app:main",
        ],
    },
    keywords=[
        "aws",
        "cdk",
        "event-sourcing",
        "cqrs",
        "eventbridge",
        "dynamodb",
        "lambda",
        "serverless",
        "financial-services",
        "microservices"
    ],
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/event-sourcing-cdk/issues",
        "Source": "https://github.com/aws-samples/event-sourcing-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "AWS EventBridge": "https://aws.amazon.com/eventbridge/",
        "AWS DynamoDB": "https://aws.amazon.com/dynamodb/",
        "AWS Lambda": "https://aws.amazon.com/lambda/"
    },
    include_package_data=True,
    zip_safe=False
)