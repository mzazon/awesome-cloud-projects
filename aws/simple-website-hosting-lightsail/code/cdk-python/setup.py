"""
Setup configuration for the Lightsail WordPress CDK Python application.

This setup.py file configures the Python package for the CDK application,
including dependencies, metadata, and entry points.
"""

import setuptools

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setuptools.setup(
    name="lightsail-wordpress-cdk",
    version="1.0.0",
    author="AWS CDK Team",
    author_email="aws-cdk@amazon.com",
    description="AWS CDK Python application for Simple Website Hosting with Lightsail",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws/aws-cdk",
    project_urls={
        "Bug Tracker": "https://github.com/aws/aws-cdk/issues",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
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
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Typing :: Typed",
    ],
    packages=setuptools.find_packages(),
    python_requires=">=3.8",
    install_requires=[
        "aws-cdk-lib>=2.140.0",
        "constructs>=10.0.0",
        "typing-extensions>=4.0.0",
    ],
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
        ],
        "cli": [
            "awscli>=1.32.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "lightsail-wordpress-cdk=app:main",
        ],
    },
    keywords="aws cdk lightsail wordpress hosting infrastructure",
    include_package_data=True,
    zip_safe=False,
)