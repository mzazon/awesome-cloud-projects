"""
Setup configuration for TaskCat Infrastructure Testing CDK Application

This setup.py file configures the Python package for the CDK application
that creates infrastructure for testing CloudFormation templates with TaskCat.
"""

import setuptools

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setuptools.setup(
    name="taskcat-infrastructure-testing-cdk",
    version="1.0.0",
    author="AWS Solutions",
    author_email="aws-solutions@amazon.com",
    description="CDK application for TaskCat infrastructure testing framework",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/taskcat-infrastructure-testing",
    project_urls={
        "Bug Tracker": "https://github.com/aws-samples/taskcat-infrastructure-testing/issues",
        "Documentation": "https://aws.amazon.com/solutions/constructs/",
        "Source": "https://github.com/aws-samples/taskcat-infrastructure-testing",
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
        "constructs>=10.3.0,<11.0.0",
        "boto3>=1.28.0",
        "botocore>=1.31.0",
    ],
    extras_require={
        "dev": [
            "mypy>=1.5.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "pytest>=7.4.0",
            "python-dotenv>=1.0.0",
            "pyyaml>=6.0.1",
        ],
        "testing": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "moto>=4.2.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "taskcat-cdk=app:main",
        ],
    },
    keywords=[
        "aws",
        "cdk",
        "cloudformation",
        "taskcat",
        "infrastructure",
        "testing",
        "devops",
        "automation",
        "vpc",
        "s3",
        "iam",
    ],
    include_package_data=True,
    zip_safe=False,
)

# Additional metadata for the package
__version__ = "1.0.0"
__author__ = "AWS Solutions"
__email__ = "aws-solutions@amazon.com"
__license__ = "Apache-2.0"
__copyright__ = "Copyright 2025 Amazon.com, Inc. or its affiliates. All Rights Reserved."