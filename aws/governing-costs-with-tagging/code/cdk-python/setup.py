"""
Setup configuration for AWS CDK Python Resource Tagging Strategies Application

This setup.py file configures the Python package for the CDK application
that implements resource tagging strategies for cost management.
"""

from setuptools import setup, find_packages

# Read requirements from requirements.txt
with open("requirements.txt", "r", encoding="utf-8") as f:
    requirements = [line.strip() for line in f if line.strip() and not line.startswith("#")]

# Read long description from README if it exists
try:
    with open("README.md", "r", encoding="utf-8") as f:
        long_description = f.read()
except FileNotFoundError:
    long_description = "AWS CDK Python application for implementing resource tagging strategies and cost management"

setup(
    name="resource-tagging-cdk",
    version="1.0.0",
    description="AWS CDK Python application for implementing resource tagging strategies and cost management",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    # Author information
    author="AWS CDK Generator",
    author_email="admin@company.com",
    
    # Package discovery
    packages=find_packages(),
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=requirements,
    
    # Development dependencies (optional)
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "aws-cdk.assertions>=2.0.0",
        ]
    },
    
    # Package metadata
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
        "Topic :: Office/Business :: Financial",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "cloud-development-kit",
        "infrastructure-as-code",
        "tagging",
        "cost-management",
        "aws-config",
        "lambda",
        "sns",
        "resource-groups",
        "governance",
        "compliance"
    ],
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "Tracker": "https://github.com/aws/aws-cdk/issues",
    },
    
    # Include additional files
    include_package_data=True,
    zip_safe=False,
    
    # Entry points (if needed for CLI tools)
    entry_points={
        "console_scripts": [
            # Add any console scripts here if needed
            # "resource-tagging-cli=resource_tagging.cli:main",
        ],
    },
)