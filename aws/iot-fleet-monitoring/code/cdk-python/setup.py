"""
Setup configuration for IoT Device Fleet Monitoring CDK Python application.

This setup.py file configures the Python package for the CDK application,
including dependencies, metadata, and entry points.
"""

import setuptools


with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()


setuptools.setup(
    name="iot-device-fleet-monitoring-cdk",
    version="1.0.0",
    author="AWS CDK Team",
    author_email="aws-cdk-team@amazon.com",
    description="CDK Python application for IoT Device Fleet Monitoring with CloudWatch and Device Defender",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/iot-device-fleet-monitoring-cdk",
    
    # Package configuration
    packages=setuptools.find_packages(),
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=[
        "aws-cdk-lib>=2.130.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.26.0",
        "botocore>=1.29.0",
    ],
    
    # Optional development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "isort>=5.0.0",
            "mypy>=1.0.0",
            "bandit>=1.7.0",
            "safety>=2.0.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
    },
    
    # Package metadata
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Monitoring",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
        "Topic :: Software Development :: Code Generators",
        "Topic :: Utilities",
    ],
    
    # Keywords for PyPI
    keywords="aws cdk iot device-defender cloudwatch monitoring fleet security",
    
    # Entry points (if needed)
    entry_points={
        "console_scripts": [
            "iot-fleet-monitoring-cdk=app:main",
        ],
    },
    
    # Package data
    package_data={
        "": ["*.md", "*.txt", "*.yaml", "*.yml", "*.json"],
    },
    
    # Include package data
    include_package_data=True,
    
    # Zip safe
    zip_safe=False,
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/iot-device-fleet-monitoring-cdk/issues",
        "Source": "https://github.com/aws-samples/iot-device-fleet-monitoring-cdk",
        "Documentation": "https://github.com/aws-samples/iot-device-fleet-monitoring-cdk/blob/main/README.md",
    },
)