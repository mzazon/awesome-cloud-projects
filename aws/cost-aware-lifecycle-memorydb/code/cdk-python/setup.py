"""
Setup configuration for the Cost-Aware MemoryDB Resource Lifecycle CDK Python application.

This setup.py file defines the package metadata and dependencies for the CDK application
that implements intelligent cost optimization for MemoryDB clusters using EventBridge Scheduler.
"""

import setuptools

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setuptools.setup(
    name="cost-aware-memorydb-lifecycle",
    version="1.0.0",
    author="AWS CDK",
    author_email="",
    description="Cost-aware resource lifecycle management with EventBridge Scheduler and MemoryDB",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws/aws-cdk",
    project_urls={
        "Bug Tracker": "https://github.com/aws/aws-cdk/issues",
    },
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: JavaScript",
        "Programming Language :: Python :: 3 :: Only",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Code Generators",
        "Topic :: Utilities",
        "Typing :: Typed",
    ],
    package_dir={"": "src"},
    packages=setuptools.find_packages(where="src"),
    python_requires=">=3.8",
    install_requires=[
        "aws-cdk-lib>=2.160.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
    ],
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
        ]
    },
)