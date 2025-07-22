"""
Setup script for Dead Letter Queue Processing CDK Python Application

This setup script configures the Python package for the CDK application that
implements Dead Letter Queue Processing with SQS.
"""

import setuptools

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setuptools.setup(
    name="dead-letter-queue-processing-cdk",
    version="1.0.0",
    author="AWS CDK Developer",
    author_email="developer@example.com",
    description="CDK Python application for Dead Letter Queue Processing with SQS",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/dead-letter-queue-processing",
    project_urls={
        "Bug Tracker": "https://github.com/aws-samples/dead-letter-queue-processing/issues",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source Code": "https://github.com/aws-samples/dead-letter-queue-processing",
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
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
    ],
    package_dir={"": "."},
    packages=setuptools.find_packages(where="."),
    python_requires=">=3.8",
    install_requires=[
        "aws-cdk-lib>=2.100.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
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
        "aws": [
            "boto3>=1.26.0",
            "botocore>=1.29.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "cdk-deploy=app:main",
        ],
    },
    keywords=[
        "aws",
        "cdk",
        "sqs",
        "lambda",
        "dead-letter-queue",
        "serverless",
        "error-handling",
        "message-processing",
        "resilience",
        "monitoring",
    ],
    zip_safe=False,
)