"""
Setup configuration for Infrastructure Monitoring CDK Application

This setup.py file configures the Python package for the AWS CDK application
that implements infrastructure monitoring with CloudTrail, Config, and Systems Manager.
"""

import setuptools

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setuptools.setup(
    name="infrastructure-monitoring-cdk",
    version="1.0.0",
    author="AWS CDK Developer",
    author_email="developer@example.com",
    description="AWS CDK application for infrastructure monitoring with CloudTrail, Config, and Systems Manager",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/infrastructure-monitoring-cdk",
    project_urls={
        "Bug Tracker": "https://github.com/aws-samples/infrastructure-monitoring-cdk/issues",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source Code": "https://github.com/aws-samples/infrastructure-monitoring-cdk",
    },
    classifiers=[
        "Development Status :: 4 - Beta",
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
    ],
    packages=setuptools.find_packages(),
    python_requires=">=3.8",
    install_requires=[
        "aws-cdk-lib>=2.158.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.34.0",
    ],
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "boto3-stubs[essential]>=1.34.0",
        ]
    },
    entry_points={
        "console_scripts": [
            "infrastructure-monitoring=app:main",
        ],
    },
    keywords=[
        "aws",
        "cdk",
        "infrastructure",
        "monitoring",
        "cloudtrail",
        "config",
        "systems-manager",
        "compliance",
        "security",
        "automation"
    ],
    zip_safe=False,
)