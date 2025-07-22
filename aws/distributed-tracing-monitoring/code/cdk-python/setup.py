"""
Setup configuration for AWS CDK Python X-Ray Monitoring Application

This setup.py file configures the Python package for the CDK application,
including dependencies, metadata, and installation requirements.
"""

import setuptools

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setuptools.setup(
    name="xray-monitoring-cdk",
    version="1.0.0",
    author="AWS CDK Team",
    author_email="aws-cdk@amazon.com",
    description="AWS CDK Python application for Infrastructure Monitoring with AWS X-Ray",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws/aws-cdk",
    project_urls={
        "Bug Tracker": "https://github.com/aws/aws-cdk/issues",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
    },
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
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: System :: Monitoring",
        "Topic :: System :: Distributed Computing",
        "Typing :: Typed",
    ],
    packages=setuptools.find_packages(exclude=["tests*"]),
    python_requires=">=3.8",
    install_requires=[
        "aws-cdk-lib>=2.115.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.34.0",
        "aws-xray-sdk>=2.12.0",
        "typing-extensions>=4.0.0",
    ],
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
        ],
        "cli": [
            "awscli>=1.32.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "xray-monitoring=app:main",
        ],
    },
    include_package_data=True,
    zip_safe=False,
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "monitoring",
        "xray",
        "tracing",
        "observability",
        "serverless",
        "lambda",
        "api-gateway",
        "dynamodb",
    ],
)