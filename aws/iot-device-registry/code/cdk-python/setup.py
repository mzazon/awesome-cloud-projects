"""
Setup configuration for AWS CDK IoT Device Management Application

This setup.py file configures the Python package for the IoT Device Management
CDK application, including dependencies, metadata, and installation requirements.
"""

from setuptools import setup, find_packages
import pathlib

# Get the long description from the README file
here = pathlib.Path(__file__).parent.resolve()
long_description = (here / "../README.md").read_text(encoding="utf-8") if (here / "../README.md").exists() else ""

setup(
    name="iot-device-management-cdk",
    version="1.0.0",
    description="AWS CDK Python application for IoT Device Management with AWS IoT Core",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/iot-device-management-cdk",
    author="AWS Solutions Architecture",
    author_email="aws-solutions@amazon.com",
    
    # Classifiers help users find your project by categorizing it
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: System :: Systems Administration",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
        "Topic :: System :: Networking :: Monitoring",
    ],
    
    # Keywords that describe your project
    keywords="aws, cdk, iot, device-management, lambda, cloudwatch, infrastructure-as-code",
    
    # Package discovery
    packages=find_packages(exclude=["tests", "tests.*"]),
    
    # Python version requirement
    python_requires=">=3.8, <4",
    
    # Runtime dependencies
    install_requires=[
        "aws-cdk-lib>=2.160.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.26.0",
        "botocore>=1.29.0",
    ],
    
    # Optional dependencies for development
    extras_require={
        "dev": [
            "mypy>=1.0.0",
            "types-boto3>=1.0.0",
            "black>=22.0.0",
            "flake8>=4.0.0",
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "Sphinx>=4.5.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
        "testing": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",  # Mock AWS services for testing
            "pytest-mock>=3.6.0",
        ],
        "iot": [
            "jsonschema>=4.0.0",
            "cryptography>=3.4.0",
            "paho-mqtt>=1.6.0",
        ]
    },
    
    # Entry points for command line tools
    entry_points={
        "console_scripts": [
            "iot-device-management=app:main",
        ],
    },
    
    # Additional files to include in the package
    package_data={
        "": ["*.json", "*.yaml", "*.yml", "*.md"],
    },
    
    # Include additional files specified in MANIFEST.in
    include_package_data=True,
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/iot-device-management-cdk/issues",
        "Source": "https://github.com/aws-samples/iot-device-management-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "AWS IoT Core": "https://aws.amazon.com/iot-core/",
    },
    
    # License
    license="MIT",
    
    # Zip safe
    zip_safe=False,
)