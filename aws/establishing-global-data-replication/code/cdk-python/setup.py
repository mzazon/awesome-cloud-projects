"""
Setup configuration for Multi-Region S3 Data Replication CDK Python Application

This setup.py file configures the Python package for the CDK application,
including dependencies, metadata, and entry points.
"""

from setuptools import setup, find_packages

# Read requirements from requirements.txt
with open("requirements.txt", "r", encoding="utf-8") as fh:
    requirements = [line.strip() for line in fh if line.strip() and not line.startswith("#")]

# Read README for long description (if it exists)
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "AWS CDK Python application for Multi-Region S3 Data Replication"

setup(
    name="multi-region-s3-replication-cdk",
    version="1.0.0",
    description="AWS CDK Python application for implementing multi-region S3 data replication with encryption, monitoring, and intelligent tiering",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS CDK Python Generator",
    author_email="your-email@example.com",
    url="https://github.com/your-org/multi-region-s3-replication",
    
    # Package configuration
    packages=find_packages(),
    include_package_data=True,
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=requirements,
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.5.0",
            "boto3-stubs[essential]>=1.34.0",
            "types-boto3>=1.0.2"
        ]
    },
    
    # Entry points
    entry_points={
        "console_scripts": [
            "multi-region-s3-replication=app:main",
        ],
    },
    
    # Package classifiers
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP",
        "Topic :: Cloud Computing",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "s3",
        "replication",
        "multi-region",
        "encryption",
        "kms",
        "cloudwatch",
        "monitoring",
        "disaster-recovery",
        "backup",
        "infrastructure-as-code",
        "cloud",
        "storage"
    ],
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/your-org/multi-region-s3-replication/issues",
        "Source": "https://github.com/your-org/multi-region-s3-replication",
        "Documentation": "https://github.com/your-org/multi-region-s3-replication/blob/main/README.md",
    },
    
    # Package data
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # Zip safety
    zip_safe=False,
)