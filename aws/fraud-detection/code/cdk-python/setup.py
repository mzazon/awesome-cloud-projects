"""
Setup configuration for the AWS CDK Python fraud detection application.

This package contains Infrastructure as Code (IaC) for deploying a complete
fraud detection system using Amazon Fraud Detector, S3, Lambda, and IAM.
"""

from setuptools import setup, find_packages

# Read version from version file
try:
    with open("VERSION", "r", encoding="utf-8") as version_file:
        version = version_file.read().strip()
except FileNotFoundError:
    version = "1.0.0"

# Read long description from README
try:
    with open("README.md", "r", encoding="utf-8") as readme_file:
        long_description = readme_file.read()
except FileNotFoundError:
    long_description = "AWS CDK Python application for Fraud Detection with Amazon Fraud Detector"

# Read requirements from requirements.txt
with open("requirements.txt", "r", encoding="utf-8") as requirements_file:
    requirements = [
        line.strip()
        for line in requirements_file
        if line.strip() and not line.startswith("#")
    ]

setup(
    name="fraud-detection-cdk",
    version=version,
    description="AWS CDK Python application for Fraud Detection with Amazon Fraud Detector",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS Solutions Team",
    author_email="aws-solutions@amazon.com",
    url="https://github.com/aws-samples/fraud-detection-cdk",
    packages=find_packages(exclude=["tests", "tests.*"]),
    include_package_data=True,
    python_requires=">=3.8",
    install_requires=requirements,
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.7.0",
            "flake8>=6.0.0",
            "mypy>=1.5.0",
            "pre-commit>=3.3.0",
        ],
        "docs": [
            "sphinx>=7.1.0",
            "sphinx-rtd-theme>=1.3.0",
            "myst-parser>=2.0.0",
        ],
    },
    classifiers=[
        "Development Status :: 4 - Beta",
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
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Security",
        "Topic :: Scientific/Engineering :: Artificial Intelligence",
        "Typing :: Typed",
    ],
    keywords=[
        "aws",
        "cdk",
        "fraud-detection",
        "machine-learning",
        "security",
        "amazon-fraud-detector",
        "infrastructure-as-code",
        "cloud",
        "python",
    ],
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws-samples/fraud-detection-cdk",
        "Bug Reports": "https://github.com/aws-samples/fraud-detection-cdk/issues",
        "AWS CDK": "https://aws.amazon.com/cdk/",
        "Amazon Fraud Detector": "https://aws.amazon.com/fraud-detector/",
    },
    entry_points={
        "console_scripts": [
            "fraud-detection-deploy=app:main",
        ],
    },
    zip_safe=False,
    platforms=["any"],
    license="Apache-2.0",
    license_files=["LICENSE"],
)