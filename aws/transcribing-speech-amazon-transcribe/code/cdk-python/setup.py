"""
Setup configuration for Amazon Transcribe Speech Recognition CDK Application

This setup.py file configures the Python package for the CDK application,
including dependencies, metadata, and development requirements.
"""

from setuptools import setup, find_packages

# Read long description from README if available
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "Amazon Transcribe Speech Recognition CDK Application"

# Read requirements from requirements.txt
with open("requirements.txt", "r", encoding="utf-8") as fh:
    requirements = [line.strip() for line in fh if line.strip() and not line.startswith("#")]

setup(
    name="transcribe-speech-recognition-cdk",
    version="1.0.0",
    author="AWS CDK Team",
    author_email="cdk-team@amazon.com",
    description="AWS CDK application for Amazon Transcribe speech recognition solutions",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws/aws-cdk",
    packages=find_packages(),
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Utilities",
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
            "bandit>=1.7.0",
        ],
        "docs": [
            "sphinx>=7.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
        "testing": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",
            "boto3-stubs[transcribe,s3,lambda,iam,logs,cloudwatch]>=1.28.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "transcribe-cdk=app:main",
        ],
    },
    project_urls={
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Source": "https://github.com/aws/aws-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
    },
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "transcribe",
        "speech-recognition",
        "machine-learning",
        "serverless",
    ],
    zip_safe=False,
    include_package_data=True,
    package_data={
        "": ["*.json", "*.yaml", "*.yml", "*.md", "*.txt"],
    },
)