"""
Setup configuration for AWS CDK Python File Sharing Application.

This setup.py file configures the Python package for the CDK application
that deploys secure file sharing infrastructure using S3 presigned URLs.
"""

import setuptools
from pathlib import Path

# Read the README file for the long description
readme_path = Path(__file__).parent / "README.md"
if readme_path.exists():
    with open(readme_path, "r", encoding="utf-8") as fh:
        long_description = fh.read()
else:
    long_description = """
    AWS CDK Python application for deploying secure file sharing infrastructure
    using Amazon S3 presigned URLs. This solution provides temporary, time-limited
    access to files without requiring AWS credentials or user management.
    """

# Read requirements from requirements.txt
requirements_path = Path(__file__).parent / "requirements.txt"
install_requires = []
if requirements_path.exists():
    with open(requirements_path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            # Skip comments and empty lines
            if line and not line.startswith('#'):
                # Handle version constraints
                if '>=' in line or '==' in line or '~=' in line:
                    install_requires.append(line)
                else:
                    install_requires.append(line)

setuptools.setup(
    name="file-sharing-s3-presigned-urls-cdk",
    version="1.0.0",
    
    # Author and contact information
    author="AWS CDK Generator",
    author_email="aws-cdk@example.com",
    
    # Package description
    description="CDK Python app for secure file sharing with S3 presigned URLs",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    # Project URLs
    url="https://github.com/aws-samples/file-sharing-s3-presigned-urls",
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/file-sharing-s3-presigned-urls/issues",
        "Source": "https://github.com/aws-samples/file-sharing-s3-presigned-urls",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
    },
    
    # Package configuration
    packages=setuptools.find_packages(),
    include_package_data=True,
    package_data={
        "": ["*.json", "*.yaml", "*.yml", "*.md"],
    },
    
    # Python version requirements
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=install_requires,
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "isort>=5.12.0",
            "pre-commit>=3.0.0",
            "bandit>=1.7.5",
            "safety>=2.3.0",
        ],
        "docs": [
            "sphinx>=7.0.0",
            "sphinx-rtd-theme>=1.3.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.2.0",  # For AWS service mocking
        ],
    },
    
    # Package classification
    classifiers=[
        "Development Status :: 4 - Beta",
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
        "Topic :: Security",
        "Framework :: AWS CDK",
    ],
    
    # Keywords for searchability
    keywords=[
        "aws", "cdk", "s3", "presigned-urls", "file-sharing", 
        "security", "infrastructure", "cloud", "storage"
    ],
    
    # Entry points for command line tools
    entry_points={
        "console_scripts": [
            "file-share-deploy=app:main",
        ],
    },
    
    # License
    license="MIT",
    
    # Zip safe configuration
    zip_safe=False,
    
    # Additional metadata
    platforms=["any"],
    
    # CDK-specific metadata
    cdk_version=">=2.150.0",
)