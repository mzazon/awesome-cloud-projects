"""
Setup configuration for Progressive Web Application CDK Python project.

This setup.py file configures the Python package for the CDK application,
including dependencies, metadata, and development tools.
"""

from setuptools import setup, find_packages

# Read the README file for long description
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "Progressive Web Application infrastructure with AWS CDK Python"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file."""
    try:
        with open("requirements.txt", "r", encoding="utf-8") as f:
            return [line.strip() for line in f if line.strip() and not line.startswith("#")]
    except FileNotFoundError:
        return [
            "aws-cdk-lib>=2.110.0,<3.0.0",
            "constructs>=10.0.0,<11.0.0",
            "boto3>=1.26.0",
            "typing-extensions>=4.5.0"
        ]

setup(
    name="progressive-web-app-cdk",
    version="1.0.0",
    description="AWS CDK Python application for Progressive Web Applications with Amplify",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS CDK Team",
    author_email="aws-cdk-team@amazon.com",
    url="https://github.com/aws/aws-cdk",
    packages=find_packages(),
    python_requires=">=3.8",
    install_requires=read_requirements(),
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "sphinx>=6.0.0",
            "sphinx-rtd-theme>=1.2.0"
        ]
    },
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: System :: Systems Administration",
        "Topic :: Utilities"
    ],
    keywords="aws cdk cloud infrastructure progressive web app amplify",
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "Tracker": "https://github.com/aws/aws-cdk/issues"
    },
    include_package_data=True,
    zip_safe=False,
    # Entry point for CDK app
    entry_points={
        "console_scripts": [
            "cdk-app=app:main",
        ],
    },
    # Additional metadata
    license="Apache-2.0",
    platforms=["any"],
    maintainer="AWS CDK Team",
    maintainer_email="aws-cdk-team@amazon.com"
)