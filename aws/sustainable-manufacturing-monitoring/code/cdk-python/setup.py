"""
Setup configuration for Sustainable Manufacturing Monitoring CDK Application

This setup.py file defines the package configuration for the CDK Python application
that deploys sustainable manufacturing monitoring infrastructure with AWS IoT SiteWise
and CloudWatch Carbon Insights.
"""

import setuptools


with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()


setuptools.setup(
    name="sustainable-manufacturing-monitoring-cdk",
    version="1.0.0",
    author="AWS Solutions Architecture Team",
    author_email="solutions-architecture@amazon.com",
    description="CDK Python application for sustainable manufacturing monitoring with ESG reporting",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/sustainable-manufacturing-monitoring",
    project_urls={
        "Bug Tracker": "https://github.com/aws-samples/sustainable-manufacturing-monitoring/issues",
        "Documentation": "https://docs.aws.amazon.com/iot-sitewise/latest/userguide/",
        "Source Code": "https://github.com/aws-samples/sustainable-manufacturing-monitoring",
    },
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: Manufacturing",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Monitoring",
        "Topic :: Scientific/Engineering :: Information Analysis",
    ],
    package_dir={"": "src"},
    packages=setuptools.find_packages(where="src"),
    python_requires=">=3.8",
    install_requires=[
        "aws-cdk-lib>=2.100.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.26.0",
        "botocore>=1.29.0",
    ],
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "boto3-stubs[essential]>=1.26.0",
            "types-requests>=2.28.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
            "myst-parser>=0.18.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "deploy-sustainable-manufacturing=app:main",
        ],
    },
    keywords=[
        "aws",
        "cdk",
        "iot",
        "sitewise",
        "sustainability",
        "manufacturing",
        "esg",
        "carbon",
        "emissions",
        "monitoring",
        "cloudwatch",
        "lambda",
        "quicksight",
    ],
    zip_safe=False,
    include_package_data=True,
    package_data={
        "": ["*.json", "*.yaml", "*.yml", "*.md"],
    },
)