"""
Setup configuration for Amazon Timestream Time-Series Data Solution CDK application

This setup.py file configures the Python package for the CDK application that creates
a comprehensive time-series data solution using Amazon Timestream with IoT integration.
"""

from setuptools import setup, find_packages

# Read requirements from requirements.txt
with open("requirements.txt", "r", encoding="utf-8") as fh:
    requirements = [line.strip() for line in fh if line.strip() and not line.startswith("#")]

# Read long description from README if it exists
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "Amazon Timestream Time-Series Data Solution CDK Python application"

setup(
    name="timestream-timeseries-cdk",
    version="1.0.0",
    author="AWS Solutions Architect",
    author_email="example@amazon.com",
    description="CDK Python application for Amazon Timestream time-series data solution",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/timestream-timeseries-solution",
    packages=find_packages(),
    classifiers=[
        "Development Status :: 5 - Production/Stable",
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
        "Topic :: Database :: Database Engines/Servers",
        "Topic :: Scientific/Engineering :: Information Analysis",
    ],
    python_requires=">=3.8",
    install_requires=requirements,
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-mock>=3.10.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "pre-commit>=2.20.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
            "sphinxcontrib-apidoc>=0.3.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "timestream-cdk=app:main",
        ],
    },
    keywords=[
        "aws",
        "cdk",
        "timestream",
        "iot",
        "time-series",
        "analytics",
        "lambda",
        "cloudwatch",
        "infrastructure",
        "devops",
    ],
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/timestream-timeseries-solution/issues",
        "Source": "https://github.com/aws-samples/timestream-timeseries-solution",
        "Documentation": "https://docs.aws.amazon.com/timestream/",
        "AWS CDK": "https://docs.aws.amazon.com/cdk/",
    },
    include_package_data=True,
    zip_safe=False,
)