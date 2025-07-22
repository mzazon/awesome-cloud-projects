"""
Setup configuration for Analytics-Optimized Data Storage with S3 Tables CDK Application

This setup.py file configures the Python package for the CDK application that deploys
analytics-optimized infrastructure using Amazon S3 Tables with Apache Iceberg support.

The package includes:
- CDK constructs for S3 Tables analytics infrastructure
- IAM roles and policies for secure access
- AWS Glue Data Catalog integration
- Amazon Athena workgroup configuration
- Sample data infrastructure for testing
"""

import setuptools
from pathlib import Path

# Read the long description from README.md if it exists
readme_path = Path(__file__).parent / "README.md"
long_description = readme_path.read_text(encoding="utf-8") if readme_path.exists() else ""

# Read requirements from requirements.txt
requirements_path = Path(__file__).parent / "requirements.txt"
install_requires = []

if requirements_path.exists():
    with open(requirements_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            # Skip comments, empty lines, and development dependencies
            if (
                line 
                and not line.startswith("#") 
                and not line.startswith("pytest")
                and not line.startswith("black")
                and not line.startswith("flake8")
                and not line.startswith("mypy")
                and not line.startswith("isort")
                and not line.startswith("sphinx")
                and not line.startswith("bandit")
                and not line.startswith("safety")
                and not line.startswith("moto")
            ):
                install_requires.append(line)

setuptools.setup(
    name="analytics-optimized-s3-tables",
    version="1.0.0",
    
    description="CDK application for analytics-optimized data storage with Amazon S3 Tables",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS CDK Team",
    author_email="aws-cdk-dev@amazon.com",
    
    package_dir={"": "."},
    packages=setuptools.find_packages(where="."),
    
    install_requires=install_requires,
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: JavaScript",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Code Generators",
        "Topic :: Utilities",
        "Typing :: Typed",
    ],
    
    keywords=[
        "aws",
        "cdk",
        "s3-tables",
        "apache-iceberg",
        "analytics",
        "data-lake",
        "athena",
        "glue",
        "quicksight",
        "infrastructure-as-code",
    ],
    
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "Tracker": "https://github.com/aws/aws-cdk/issues",
    },
    
    # CDK-specific metadata
    extras_require={
        "dev": [
            "pytest>=7.4.0,<8.0.0",
            "pytest-cov>=4.1.0,<5.0.0",
            "black>=23.0.0,<24.0.0",
            "flake8>=6.0.0,<7.0.0",
            "mypy>=1.5.0,<2.0.0",
            "isort>=5.12.0,<6.0.0",
            "bandit>=1.7.0,<2.0.0",
            "safety>=2.3.0,<3.0.0",
            "moto>=4.2.0,<5.0.0",
        ],
        "docs": [
            "sphinx>=7.0.0,<8.0.0",
            "sphinx-rtd-theme>=1.3.0,<2.0.0",
        ],
    },
    
    # Entry points for CLI tools if needed
    entry_points={
        "console_scripts": [
            # Add any CLI tools here if needed
        ],
    },
    
    # Include additional files in the package
    include_package_data=True,
    package_data={
        "": [
            "cdk.json",
            "*.md",
            "*.yaml",
            "*.yml",
        ],
    },
    
    # Exclude development and build artifacts
    exclude_package_data={
        "": [
            "*.pyc",
            "__pycache__",
            "*.egg-info",
            ".pytest_cache",
            ".coverage",
            "htmlcov",
            ".mypy_cache",
            ".git",
            ".gitignore",
            "Dockerfile",
            "docker-compose.yml",
        ],
    },
    
    # Zip safety
    zip_safe=False,
    
    # Platform compatibility
    platforms=["any"],
    
    # License information
    license="Apache-2.0",
    license_files=["LICENSE"],
    
    # Metadata for package repositories
    maintainer="AWS CDK Team",
    maintainer_email="aws-cdk-dev@amazon.com",
    
    # Additional metadata
    obsoletes_dist=[],
    provides_dist=[],
    requires_dist=[],
    requires_external=[],
    requires_python=">=3.8",
)