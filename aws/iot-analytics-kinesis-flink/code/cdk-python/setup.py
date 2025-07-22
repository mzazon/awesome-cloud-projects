"""
Setup configuration for Real-Time IoT Analytics CDK Python Application

This setup.py file configures the Python package for the CDK application,
including dependencies, metadata, and development requirements.
"""

from setuptools import setup, find_packages

# Read the README file for the long description
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "Real-Time IoT Analytics Pipeline with Kinesis and Managed Service for Apache Flink"

# Read requirements from requirements.txt
def read_requirements(filename: str) -> list[str]:
    """Read requirements from a file and return as a list"""
    try:
        with open(filename, "r", encoding="utf-8") as f:
            return [
                line.strip()
                for line in f
                if line.strip() and not line.startswith("#")
            ]
    except FileNotFoundError:
        return []

# Define the package metadata
setup(
    name="iot-analytics-cdk",
    version="1.0.0",
    description="AWS CDK Python application for Real-Time IoT Analytics Pipeline",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS CDK Team",
    author_email="cdk-team@example.com",
    url="https://github.com/aws/recipes",
    license="Apache-2.0",
    
    # Package configuration
    packages=find_packages(exclude=["tests*"]),
    include_package_data=True,
    zip_safe=False,
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=read_requirements("requirements.txt"),
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "autopep8>=2.0.0",
            "pylint>=3.0.0",
        ],
        "docs": [
            "sphinx>=7.0.0",
            "sphinx-rtd-theme>=1.3.0",
        ],
    },
    
    # Entry points for command-line scripts
    entry_points={
        "console_scripts": [
            "iot-analytics-cdk=app:main",
        ],
    },
    
    # Package classifiers for PyPI
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
    ],
    
    # Keywords for discovery
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "iot",
        "analytics",
        "kinesis",
        "flink",
        "streaming",
        "real-time",
        "lambda",
        "s3",
        "sns",
        "cloudwatch",
    ],
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/recipes",
        "Tracker": "https://github.com/aws/recipes/issues",
        "AWS CDK": "https://aws.amazon.com/cdk/",
    },
)