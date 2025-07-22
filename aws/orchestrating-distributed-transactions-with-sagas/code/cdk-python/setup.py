"""
Setup configuration for Saga Pattern CDK Python application.

This setup file configures the Python package for the Saga Pattern implementation
using AWS CDK Python constructs for distributed transaction orchestration.
"""

from setuptools import setup, find_packages

# Read requirements from requirements.txt
with open("requirements.txt", "r", encoding="utf-8") as fh:
    requirements = [line.strip() for line in fh if line.strip() and not line.startswith("#")]

# Read README for long description (if exists)
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "Saga Pattern with Step Functions for Distributed Transactions - CDK Python Implementation"

setup(
    name="saga-pattern-cdk",
    version="1.0.0",
    description="AWS CDK Python application for Saga Pattern with Step Functions for distributed transactions",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS CDK Developer",
    author_email="developer@example.com",
    url="https://github.com/example/saga-pattern-cdk",
    packages=find_packages(exclude=["tests*"]),
    install_requires=requirements,
    python_requires=">=3.8",
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Distributed Computing",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
    ],
    keywords="aws cdk step-functions saga-pattern distributed-transactions lambda dynamodb",
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/example/saga-pattern-cdk",
        "Tracker": "https://github.com/example/saga-pattern-cdk/issues",
    },
    entry_points={
        "console_scripts": [
            "saga-pattern-cdk=app:main",
        ],
    },
    include_package_data=True,
    zip_safe=False,
)