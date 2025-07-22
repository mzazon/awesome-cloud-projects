#!/usr/bin/env python3
"""
Setup configuration for Fault-Tolerant HPC Workflows CDK Python application.
"""

from setuptools import setup, find_packages

# Read the contents of requirements.txt
with open("requirements.txt", "r", encoding="utf-8") as fh:
    requirements = [line.strip() for line in fh if line.strip() and not line.startswith("#")]

# Read the contents of README.md if it exists
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "Fault-Tolerant HPC Workflows with Step Functions and Spot Fleet - AWS CDK Python Implementation"

setup(
    name="fault-tolerant-hpc-workflows",
    version="1.0.0",
    author="AWS Solutions Team",
    author_email="aws-solutions@amazon.com",
    description="AWS CDK Python implementation for fault-tolerant HPC workflows using Step Functions and Spot Fleet",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/fault-tolerant-hpc-workflows",
    packages=find_packages(),
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "Intended Audience :: Science/Research",
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: System :: Distributed Computing",
        "Topic :: Scientific/Engineering",
        "Topic :: System :: Systems Administration",
    ],
    python_requires=">=3.8",
    install_requires=requirements,
    extras_require={
        "dev": [
            "pytest>=7.0.0,<8.0.0",
            "pytest-cov>=4.0.0,<5.0.0",
            "black>=23.0.0,<24.0.0",
            "flake8>=6.0.0,<7.0.0",
            "mypy>=1.0.0,<2.0.0",
            "isort>=5.0.0,<6.0.0",
            "bandit>=1.7.0,<2.0.0",
            "safety>=2.0.0,<3.0.0",
        ],
        "docs": [
            "sphinx>=5.0.0,<6.0.0",
            "sphinx-rtd-theme>=1.0.0,<2.0.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "deploy-hpc-workflow=app:main",
        ],
    },
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/fault-tolerant-hpc-workflows/issues",
        "Source": "https://github.com/aws-samples/fault-tolerant-hpc-workflows",
        "Documentation": "https://docs.aws.amazon.com/step-functions/",
        "AWS Batch": "https://docs.aws.amazon.com/batch/",
        "AWS EC2 Spot": "https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-spot-instances.html",
    },
    keywords=[
        "aws",
        "cdk",
        "step-functions",
        "batch",
        "hpc",
        "high-performance-computing",
        "spot-instances",
        "fault-tolerance",
        "workflow-orchestration",
        "scientific-computing",
        "cloud-computing",
        "infrastructure-as-code",
    ],
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    include_package_data=True,
    zip_safe=False,
    platforms=["any"],
    license="Apache-2.0",
)