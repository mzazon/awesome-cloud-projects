"""
Setup configuration for S3 Intelligent Tiering CDK Python Application

This setup.py file configures the Python package for the CDK application
that implements S3 Intelligent Tiering and Lifecycle Management.
"""

import setuptools

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setuptools.setup(
    name="s3-intelligent-tiering-cdk",
    version="1.0.0",
    author="AWS CDK Generator",
    author_email="admin@example.com",
    description="CDK Python application for S3 Intelligent Tiering and Lifecycle Management",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/your-org/s3-intelligent-tiering-cdk",
    project_urls={
        "Bug Tracker": "https://github.com/your-org/s3-intelligent-tiering-cdk/issues",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
    },
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Utilities",
        "Typing :: Typed",
    ],
    package_dir={"": "."},
    packages=setuptools.find_packages(where="."),
    python_requires=">=3.8",
    install_requires=[
        "aws-cdk-lib>=2.100.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
    ],
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "black>=22.0.0",
            "flake8>=4.0.0",
            "mypy>=0.991",
        ],
        "test": [
            "pytest>=7.0.0",
            "moto>=4.0.0",
            "boto3>=1.26.0",
        ],
        "docs": [
            "sphinx>=4.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "s3-intelligent-tiering=app:main",
        ],
    },
    keywords=[
        "aws",
        "cdk",
        "s3",
        "intelligent-tiering",
        "lifecycle",
        "storage",
        "cost-optimization",
        "infrastructure-as-code",
    ],
    include_package_data=True,
    zip_safe=False,
)