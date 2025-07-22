"""
Setup configuration for Real-time Data Processing with Kinesis and Lambda CDK application.

This setup.py file defines the package configuration for the CDK Python application
that deploys a serverless real-time data processing pipeline.
"""

import setuptools

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setuptools.setup(
    name="real-time-data-processing-kinesis-lambda",
    version="1.0.0",
    author="AWS Recipes",
    author_email="recipes@example.com",
    description="CDK Python application for real-time data processing with Kinesis and Lambda",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-recipes/real-time-data-processing",
    project_urls={
        "Bug Tracker": "https://github.com/aws-recipes/real-time-data-processing/issues",
        "Documentation": "https://github.com/aws-recipes/real-time-data-processing/wiki",
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
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Utilities",
    ],
    package_dir={"": "."},
    packages=setuptools.find_packages(where="."),
    python_requires=">=3.8",
    install_requires=[
        "aws-cdk-lib>=2.140.0",
        "constructs>=10.0.0",
        "boto3>=1.28.0",
        "python-dotenv>=1.0.0",
    ],
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "mypy>=1.5.0",
            "black>=23.7.0",
            "flake8>=6.0.0",
            "isort>=5.12.0",
            "types-requests>=2.31.0",
            "boto3-stubs>=1.28.0",
        ],
        "test": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "moto>=4.2.0",  # For mocking AWS services in tests
        ],
    },
    entry_points={
        "console_scripts": [
            "deploy-real-time-processing=app:main",
        ],
    },
    keywords=[
        "aws",
        "cdk",
        "kinesis",
        "lambda",
        "serverless",
        "real-time",
        "data-processing",
        "streaming",
        "infrastructure-as-code",
    ],
    include_package_data=True,
    zip_safe=False,
)