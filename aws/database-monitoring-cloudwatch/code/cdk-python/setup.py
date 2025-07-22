"""
Setup configuration for Database Monitoring Dashboards CDK Python application.

This setup.py file configures the Python package for the CDK application that creates
comprehensive database monitoring infrastructure with CloudWatch dashboards and alarms.
"""

import setuptools


with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()


setuptools.setup(
    name="database-monitoring-dashboards-cloudwatch",
    version="1.0.0",
    author="AWS CDK Python Generator",
    author_email="admin@example.com",
    description="AWS CDK Python application for database monitoring dashboards with CloudWatch",
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
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Monitoring",
        "Topic :: Database",
        "Typing :: Typed",
    ],
    package_dir={"": "."},
    packages=setuptools.find_packages(where="."),
    python_requires=">=3.8",
    install_requires=[
        "aws-cdk-lib>=2.116.0,<3.0.0",
        "constructs>=10.3.0,<11.0.0",
    ],
    extras_require={
        "dev": [
            "pytest>=6.2.5",
            "pytest-cov>=2.12.1",
            "black>=21.9b0",
            "flake8>=3.9.2",
            "mypy>=0.910",
            "boto3>=1.34.0",
            "botocore>=1.34.0",
        ]
    },
    entry_points={
        "console_scripts": [
            "cdk-deploy=app:main",
        ],
    },
    keywords=[
        "aws",
        "cdk",
        "cloudwatch",
        "rds",
        "database",
        "monitoring",
        "dashboards",
        "alarms",
        "sns",
        "notifications",
        "infrastructure",
        "devops",
    ],
    zip_safe=False,
)