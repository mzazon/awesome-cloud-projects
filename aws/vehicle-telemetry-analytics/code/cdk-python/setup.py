"""
Setup configuration for the Vehicle Telemetry Analytics CDK Python application.

This setup file configures the Python package for the AWS CDK application
that implements real-time vehicle telemetry analytics using AWS IoT FleetWise
and Amazon Timestream.
"""

import setuptools

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setuptools.setup(
    name="vehicle-telemetry-analytics-cdk",
    version="1.0.0",
    author="AWS Solutions Architecture",
    author_email="solutions-architecture@amazon.com",
    description="CDK application for real-time vehicle telemetry analytics with AWS IoT FleetWise and Timestream",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/vehicle-telemetry-analytics",
    project_urls={
        "Bug Tracker": "https://github.com/aws-samples/vehicle-telemetry-analytics/issues",
        "Documentation": "https://docs.aws.amazon.com/iot-fleetwise/",
        "Source Code": "https://github.com/aws-samples/vehicle-telemetry-analytics",
    },
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
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: Internet :: WWW/HTTP :: Applications",
        "Topic :: System :: Monitoring",
        "Topic :: Scientific/Engineering :: Information Analysis",
    ],
    package_dir={"": "src"},
    packages=setuptools.find_packages(where="src"),
    python_requires=">=3.8",
    install_requires=[
        "aws-cdk-lib>=2.160.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "python-dotenv>=1.0.0,<2.0.0",
        "pyyaml>=6.0.0,<7.0.0",
    ],
    extras_require={
        "dev": [
            "pytest>=7.0.0,<8.0.0",
            "pytest-cov>=4.0.0,<5.0.0",
            "black>=22.0.0,<24.0.0",
            "mypy>=1.0.0,<2.0.0",
            "flake8>=5.0.0,<7.0.0",
            "types-requests>=2.28.0,<3.0.0",
            "boto3-stubs[essential]>=1.34.0,<2.0.0",
        ],
        "docs": [
            "sphinx>=5.0.0,<7.0.0",
            "sphinx-rtd-theme>=1.0.0,<2.0.0",
            "myst-parser>=0.18.0,<1.0.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "deploy-telemetry-stack=app:main",
        ],
    },
    keywords=[
        "aws",
        "cdk",
        "iot",
        "fleetwise",
        "timestream",
        "vehicle",
        "telemetry",
        "analytics",
        "grafana",
        "monitoring",
        "time-series",
        "fleet-management",
    ],
    zip_safe=False,
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.yaml", "*.yml", "*.json"],
    },
)