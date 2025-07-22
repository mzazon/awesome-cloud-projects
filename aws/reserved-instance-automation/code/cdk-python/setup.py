"""
Setup configuration for Reserved Instance Management Automation CDK Application

This setup.py file configures the Python package for the CDK application that
deploys automated Reserved Instance management infrastructure on AWS.
"""

import setuptools

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setuptools.setup(
    name="reserved-instance-management-automation",
    version="1.0.0",
    author="AWS CDK Developer",
    author_email="developer@example.com",
    description="CDK application for automated Reserved Instance management with Cost Explorer integration",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/example/reserved-instance-management-automation",
    project_urls={
        "Bug Tracker": "https://github.com/example/reserved-instance-management-automation/issues",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source Code": "https://github.com/example/reserved-instance-management-automation",
    },
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
        "Topic :: System :: Systems Administration",
        "Topic :: Office/Business :: Financial",
        "Typing :: Typed",
    ],
    package_dir={"": "."},
    packages=setuptools.find_packages(where="."),
    python_requires=">=3.8",
    install_requires=[
        "aws-cdk-lib>=2.100.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.26.0",
        "botocore>=1.26.0",
    ],
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cdk>=0.4.0",
            "black>=22.0.0",
            "flake8>=4.0.0",
            "mypy>=0.910",
            "boto3-stubs[cost-explorer,lambda,events,s3,dynamodb,sns,iam,ec2,logs]>=1.26.0",
        ],
        "docs": [
            "sphinx>=4.0.0",
            "sphinx-rtd-theme>=1.0.0",
            "sphinx-autodoc-typehints>=1.12.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "ri-management=app:main",
        ],
    },
    keywords=[
        "aws",
        "cdk",
        "reserved-instances",
        "cost-optimization",
        "cost-explorer",
        "lambda",
        "eventbridge",
        "automation",
        "infrastructure-as-code",
        "cloud-financial-management",
    ],
    zip_safe=False,
)