"""
Setup configuration for S3 Cross-Region Replication Disaster Recovery CDK Application

This setup.py file configures the Python package for the CDK application
that implements S3 Cross-Region Replication for disaster recovery.
"""

from setuptools import setup, find_packages

# Read README file for long description
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "S3 Cross-Region Replication Disaster Recovery CDK Application"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file"""
    with open("requirements.txt", "r", encoding="utf-8") as req_file:
        return [
            line.strip() 
            for line in req_file.readlines() 
            if line.strip() and not line.startswith("#")
        ]

setup(
    name="s3-disaster-recovery-cdk",
    version="1.0.0",
    author="AWS CDK Team",
    author_email="aws-cdk-team@amazon.com",
    description="CDK Python application for S3 Cross-Region Replication disaster recovery",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws/aws-cdk",
    packages=find_packages(),
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
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: System :: Systems Administration",
        "Topic :: System :: Archiving :: Backup",
        "Topic :: System :: Distributed Computing",
        "Typing :: Typed",
    ],
    python_requires=">=3.8",
    install_requires=read_requirements(),
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "moto>=4.2.0",
            "black>=23.0.0",
            "mypy>=1.5.0",
            "flake8>=6.0.0",
        ],
        "docs": [
            "sphinx>=7.0.0",
            "sphinx-rtd-theme>=1.3.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "s3-dr-cdk=app:main",
        ],
    },
    keywords=[
        "aws",
        "cdk",
        "s3",
        "disaster-recovery",
        "cross-region-replication",
        "backup",
        "infrastructure-as-code",
    ],
    project_urls={
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "CDK Guide": "https://docs.aws.amazon.com/cdk/v2/guide/home.html",
        "API Reference": "https://docs.aws.amazon.com/cdk/api/v2/",
    },
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    include_package_data=True,
    zip_safe=False,
)