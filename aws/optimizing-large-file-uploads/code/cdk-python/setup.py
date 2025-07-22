"""
Setup configuration for the S3 Multi-Part Upload Strategies CDK application.

This setup.py file configures the Python package for the CDK application,
including metadata, dependencies, and development tools configuration.
"""

from typing import List
import setuptools


def get_requirements() -> List[str]:
    """
    Read requirements from requirements.txt file.
    
    Returns:
        List of package requirements
    """
    try:
        with open("requirements.txt", "r", encoding="utf-8") as f:
            return [
                line.strip()
                for line in f
                if line.strip() and not line.startswith("#")
            ]
    except FileNotFoundError:
        # Fallback requirements if file doesn't exist
        return [
            "aws-cdk-lib>=2.120.0,<3.0.0",
            "constructs>=10.0.0,<11.0.0",
        ]


def get_long_description() -> str:
    """
    Get long description from README if available.
    
    Returns:
        Long description string
    """
    try:
        with open("README.md", "r", encoding="utf-8") as f:
            return f.read()
    except FileNotFoundError:
        return """
        AWS CDK Python application for demonstrating S3 multipart upload strategies.
        
        This application creates the infrastructure needed to implement and test
        S3 multipart uploads for large files, including optimized bucket configuration,
        lifecycle policies, monitoring dashboards, and IAM roles.
        """


setuptools.setup(
    # Package metadata
    name="multipart-upload-cdk",
    version="1.0.0",
    author="Cloud Recipes Team",
    author_email="recipes@example.com",
    description="CDK application for S3 multipart upload strategies",
    long_description=get_long_description(),
    long_description_content_type="text/markdown",
    url="https://github.com/cloud-recipes/aws-multipart-upload",
    
    # Package configuration
    packages=setuptools.find_packages(),
    include_package_data=True,
    zip_safe=False,
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=get_requirements(),
    
    # Development dependencies
    extras_require={
        "dev": [
            "mypy>=1.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "isort>=5.0.0",
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "sphinx>=7.0.0",
            "sphinx-rtd-theme>=1.3.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "aws-cdk.aws-s3-assertions>=2.120.0,<3.0.0",
            "boto3>=1.34.0",
        ],
    },
    
    # Entry points for command line tools
    entry_points={
        "console_scripts": [
            "multipart-upload-deploy=app:main",
        ],
    },
    
    # Package classifiers for PyPI
    classifiers=[
        "Development Status :: 4 - Beta",
        "Environment :: Console",
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
        "Topic :: Utilities",
        "Typing :: Typed",
    ],
    
    # Keywords for discovery
    keywords=[
        "aws",
        "cdk",
        "s3",
        "multipart-upload",
        "cloud",
        "infrastructure",
        "cloudformation",
        "storage",
    ],
    
    # Project URLs
    project_urls={
        "Documentation": "https://github.com/cloud-recipes/aws-multipart-upload/docs",
        "Source": "https://github.com/cloud-recipes/aws-multipart-upload",
        "Tracker": "https://github.com/cloud-recipes/aws-multipart-upload/issues",
    },
    
    # Package data to include
    package_data={
        "": [
            "*.json",
            "*.yaml",
            "*.yml",
            "*.md",
            "*.txt",
        ],
    },
)