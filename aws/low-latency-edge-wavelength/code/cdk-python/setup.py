"""
Setup configuration for AWS CDK Python Edge Application.

This setup.py file configures the Python package for the edge computing
application using AWS Wavelength and CloudFront.
"""

import setuptools

# Read the README file for long description
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "AWS CDK Python application for Low-Latency Edge Applications with Wavelength"

setuptools.setup(
    name="aws-wavelength-cloudfront-edge-app",
    version="1.0.0",
    author="AWS CDK Developer",
    author_email="developer@company.com",
    description="Low-latency edge application using AWS Wavelength and CloudFront",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/your-org/aws-wavelength-cloudfront-edge-app",
    project_urls={
        "Bug Tracker": "https://github.com/your-org/aws-wavelength-cloudfront-edge-app/issues",
        "Documentation": "https://docs.aws.amazon.com/wavelength/",
        "Source Code": "https://github.com/your-org/aws-wavelength-cloudfront-edge-app",
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
        "Topic :: System :: Networking",
        "Topic :: Internet :: WWW/HTTP :: HTTP Servers",
        "Topic :: System :: Distributed Computing",
    ],
    packages=setuptools.find_packages(),
    python_requires=">=3.8",
    install_requires=[
        "aws-cdk-lib==2.166.0",
        "constructs>=10.0.0,<11.0.0",
        "typing-extensions>=4.0.0",
    ],
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "bandit>=1.7.0",
            "safety>=2.3.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.2.0",
        ],
        "testing": [
            "aws-cdk.assertions>=2.150.0",
            "moto>=4.0.0",
            "boto3-stubs[essential]>=1.0.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "edge-app=app:main",
        ],
    },
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    keywords=[
        "aws",
        "cdk",
        "wavelength",
        "cloudfront",
        "edge-computing",
        "5g",
        "low-latency",
        "mobile",
        "networking",
        "infrastructure",
        "cloud",
    ],
    zip_safe=False,
)