"""
Setup configuration for Industrial IoT Data Collection CDK Python application

This setup file configures the Python package for the AWS CDK application
that implements industrial IoT data collection using AWS IoT SiteWise.
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
    long_description = "Industrial IoT Data Collection solution using AWS IoT SiteWise"

setup(
    name="industrial-iot-data-collection",
    version="1.0.0",
    author="AWS CDK Generator",
    author_email="support@example.com",
    description="AWS CDK Python application for Industrial IoT Data Collection with IoT SiteWise",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/industrial-iot-sitewise-cdk",
    packages=find_packages(),
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
        "Topic :: System :: Monitoring",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
    ],
    python_requires=">=3.8",
    install_requires=requirements,
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "types-boto3>=1.0.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "industrial-iot-cdk=app:main",
        ],
    },
    include_package_data=True,
    package_data={
        "": ["*.txt", "*.md", "*.json", "*.yaml", "*.yml"],
    },
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/industrial-iot-sitewise-cdk/issues",
        "Source": "https://github.com/aws-samples/industrial-iot-sitewise-cdk",
        "Documentation": "https://docs.aws.amazon.com/iot-sitewise/",
    },
    keywords=[
        "aws",
        "cdk",
        "iot",
        "sitewise",
        "industrial",
        "timestream",
        "monitoring",
        "manufacturing",
        "sensors",
        "data-collection",
    ],
)