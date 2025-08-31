"""
Setup configuration for Canary Deployments with VPC Lattice and Lambda CDK application.

This setup file defines the Python package configuration for a CDK application
that implements progressive canary deployments using AWS VPC Lattice for traffic
routing and AWS Lambda for serverless compute.
"""

import setuptools

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setuptools.setup(
    name="canary-deployments-lattice-lambda",
    version="1.0.0",
    author="AWS CDK Developer",
    author_email="developer@example.com",
    description="CDK application for canary deployments using VPC Lattice and Lambda",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/example/canary-deployments-lattice-lambda",
    project_urls={
        "Bug Tracker": "https://github.com/example/canary-deployments-lattice-lambda/issues",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "AWS VPC Lattice": "https://docs.aws.amazon.com/vpc-lattice/",
        "AWS Lambda": "https://docs.aws.amazon.com/lambda/"
    },
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Distributed Computing",
        "Topic :: Internet :: WWW/HTTP :: HTTP Servers",
        "Topic :: System :: Networking"
    ],
    package_dir={"": "."},
    packages=setuptools.find_packages(where="."),
    python_requires=">=3.8",
    install_requires=[
        "aws-cdk-lib>=2.167.1",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.34.0"
    ],
    extras_require={
        "dev": [
            "mypy>=1.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "python-dotenv>=1.0.0"
        ]
    },
    entry_points={
        "console_scripts": [
            "canary-deployments=app:main",
        ],
    },
    keywords=[
        "aws",
        "cdk",
        "vpc-lattice",
        "lambda",
        "canary-deployment",
        "progressive-delivery",
        "traffic-routing",
        "service-mesh",
        "serverless",
        "infrastructure-as-code"
    ],
    zip_safe=False,
)