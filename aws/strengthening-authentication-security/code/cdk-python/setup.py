"""
Setup configuration for Multi-Factor Authentication CDK Python application.

This package implements a comprehensive MFA solution using AWS IAM,
CloudWatch monitoring, and CloudTrail auditing.
"""

import setuptools

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setuptools.setup(
    name="mfa-iam-cdk",
    version="1.0.0",
    author="AWS CDK Team",
    author_email="aws-cdk@amazon.com",
    description="Multi-Factor Authentication implementation using AWS CDK Python",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws/aws-cdk",
    project_urls={
        "Bug Tracker": "https://github.com/aws/aws-cdk/issues",
        "Source": "https://github.com/aws/aws-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
    },
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: System :: Systems Administration",
        "Topic :: Security",
        "Topic :: Security :: Cryptography",
        "Typing :: Typed",
    ],
    packages=setuptools.find_packages(),
    python_requires=">=3.8",
    install_requires=[
        "aws-cdk-lib==2.110.1",
        "constructs>=10.0.0,<11.0.0",
        "typing-extensions>=3.10.0",
    ],
    extras_require={
        "dev": [
            "pytest>=6.2.0",
            "pytest-cov>=2.12.0",
            "black>=21.6b0",
            "flake8>=3.9.0",
            "mypy>=0.910",
            "sphinx>=4.0.0",
            "sphinx-rtd-theme>=0.5.0",
        ],
        "testing": [
            "boto3>=1.26.0",
            "botocore>=1.29.0",
            "moto>=4.0.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "mfa-iam-cdk=app:main",
        ],
    },
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "iam",
        "mfa",
        "multi-factor-authentication",
        "security",
        "monitoring",
        "cloudwatch",
        "cloudtrail",
    ],
    include_package_data=True,
    zip_safe=False,
)