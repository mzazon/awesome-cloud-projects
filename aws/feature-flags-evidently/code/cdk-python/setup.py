"""
Setup configuration for AWS CDK Python application.

This setup.py file defines the Python package configuration for the
Feature Flags with CloudWatch Evidently CDK application.
"""

import setuptools

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setuptools.setup(
    name="feature-flags-evidently-cdk",
    version="1.0.0",
    author="AWS CDK Recipe Generator",
    author_email="recipes@example.com",
    description="AWS CDK application for Feature Flags with CloudWatch Evidently",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/recipes",
    project_urls={
        "Bug Tracker": "https://github.com/aws-samples/recipes/issues",
        "Documentation": "https://docs.aws.amazon.com/evidently/",
        "Source": "https://github.com/aws-samples/recipes",
    },
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Framework :: AWS CDK",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Utilities",
    ],
    package_dir={"": "."},
    packages=setuptools.find_packages(where="."),
    python_requires=">=3.8",
    install_requires=[
        "aws-cdk-lib==2.160.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.34.0",
        "botocore>=1.34.0",
    ],
    extras_require={
        "dev": [
            "mypy>=1.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "synth=app:app.synth",
        ],
    },
    keywords=[
        "aws",
        "cdk",
        "cloudformation",
        "infrastructure",
        "evidently",
        "feature-flags",
        "lambda",
        "devops",
        "deployment",
    ],
    zip_safe=False,
)