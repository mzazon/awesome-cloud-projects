"""
Setup configuration for AWS CDK Python Live Streaming Solutions.

This package provides Infrastructure as Code (IaC) for deploying a complete
live streaming solution using AWS Elemental MediaLive, MediaPackage, and CloudFront.
"""

from setuptools import setup, find_packages

# Read long description from README
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = __doc__

# Read requirements from requirements.txt
try:
    with open("requirements.txt", "r", encoding="utf-8") as fh:
        requirements = [line.strip() for line in fh if line.strip() and not line.startswith("#")]
except FileNotFoundError:
    requirements = [
        "aws-cdk-lib>=2.114.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.26.0",
    ]

setup(
    name="live-streaming-cdk",
    version="1.0.0",
    author="AWS CDK Team",
    author_email="aws-cdk-team@amazon.com",
    description="AWS CDK Python application for Live Streaming Solutions with AWS Elemental MediaLive",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws/aws-cdk",
    packages=find_packages(exclude=["tests", "tests.*"]),
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Multimedia :: Video :: Conversion",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
        "Typing :: Typed",
    ],
    python_requires=">=3.8",
    install_requires=requirements,
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "pre-commit>=3.0.0",
            "bandit>=1.7.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
        "typing": [
            "boto3-stubs[medialive,mediapackage,cloudfront,s3,sns,cloudwatch]>=1.26.0",
            "types-boto3>=1.0.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "deploy-live-streaming=app:main",
        ],
    },
    project_urls={
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Source": "https://github.com/aws/aws-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "CDK Workshop": "https://cdkworkshop.com/",
        "AWS CDK Examples": "https://github.com/aws-samples/aws-cdk-examples",
    },
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "live-streaming",
        "medialive",
        "mediapackage",
        "cloudfront",
        "video",
        "broadcast",
        "streaming",
        "adaptive-bitrate",
        "hls",
        "dash",
        "rtmp",
    ],
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    include_package_data=True,
    zip_safe=False,
)