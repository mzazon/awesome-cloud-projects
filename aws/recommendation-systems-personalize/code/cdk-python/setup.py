"""
Setup configuration for Real-time Recommendation Systems CDK application.

This setup.py file configures the Python package for the CDK application
that deploys a serverless recommendation system using Amazon Personalize
and API Gateway.
"""

import setuptools

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setuptools.setup(
    name="recommendation-system-cdk",
    version="1.0.0",
    author="AWS CDK Team",
    author_email="cdk-team@amazon.com",
    description="CDK Python application for real-time recommendation systems",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws/aws-cdk",
    project_urls={
        "Bug Tracker": "https://github.com/aws/aws-cdk/issues",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source Code": "https://github.com/aws/aws-cdk",
    },
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Operating System :: OS Independent",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Utilities",
        "Typing :: Typed",
    ],
    package_dir={"": "."},
    packages=setuptools.find_packages(where="."),
    python_requires=">=3.8",
    install_requires=[
        "aws-cdk-lib>=2.100.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.26.0",
        "botocore>=1.29.0",
    ],
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "python-dotenv>=1.0.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "recommendation-system-cdk=app:main",
        ],
    },
    include_package_data=True,
    zip_safe=False,
)