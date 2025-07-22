"""
Setup configuration for AWS CDK Python application.

This setup.py file configures the Python package for the Database Connection
Pooling with RDS Proxy CDK application, including all dependencies and
metadata required for proper installation and distribution.
"""

from setuptools import setup, find_packages
import pathlib

here = pathlib.Path(__file__).parent.resolve()

# Get the long description from the README file
long_description = (here / "README.md").read_text(encoding="utf-8") if (here / "README.md").exists() else ""

setup(
    name="database-connection-pooling-rds-proxy",
    version="1.0.0",
    description="AWS CDK Python application for Database Connection Pooling with RDS Proxy",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    # Author information
    author="AWS CDK Generator",
    author_email="support@amazonaws.com",
    
    # Project URLs
    url="https://github.com/aws-samples/aws-cdk-examples",
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/aws-cdk-examples/issues",
        "Source": "https://github.com/aws-samples/aws-cdk-examples",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
    },
    
    # Package classification
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: Database",
        "Topic :: System :: Networking",
    ],
    
    # Python version requirements
    python_requires=">=3.8",
    
    # Package discovery
    packages=find_packages(exclude=["tests", "tests.*"]),
    
    # Dependencies
    install_requires=[
        "aws-cdk-lib>=2.161.1",
        "constructs>=10.0.0,<11.0.0",
        "PyMySQL>=1.0.2",
        "boto3>=1.26.0",
    ],
    
    # Extra dependencies for development
    extras_require={
        "dev": [
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "types-boto3>=1.0.0",
            "types-requests>=2.0.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",  # Mock AWS services for testing
        ],
    },
    
    # Entry points for the application
    entry_points={
        "console_scripts": [
            "cdk-deploy=app:main",
        ],
    },
    
    # Include additional files
    include_package_data=True,
    
    # Keywords for PyPI
    keywords="aws cdk rds proxy database connection pooling serverless lambda python",
    
    # Package metadata
    zip_safe=False,
    
    # Platform compatibility
    platforms=["any"],
)