"""
Setup configuration for AWS Config Auto-Remediation CDK Python Application

This setup.py file configures the Python package for the CDK application
that deploys AWS Config auto-remediation infrastructure.
"""

from setuptools import setup, find_packages

# Read the README file for the long description
with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

# Read requirements from requirements.txt
with open("requirements.txt", "r", encoding="utf-8") as fh:
    requirements = [line.strip() for line in fh if line.strip() and not line.startswith("#")]

setup(
    name="aws-config-auto-remediation-cdk",
    version="1.0.0",
    description="AWS CDK Python application for Config auto-remediation solution",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS Config Team",
    author_email="aws-config-team@example.com",
    url="https://github.com/your-org/aws-config-auto-remediation",
    
    # Package configuration
    packages=find_packages(exclude=["tests", "tests.*"]),
    include_package_data=True,
    zip_safe=False,
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=requirements,
    
    # Optional dependencies for development
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "bandit>=1.7.0",
            "safety>=2.0.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
    },
    
    # Entry points for command-line scripts
    entry_points={
        "console_scripts": [
            "deploy-config-remediation=app:main",
        ],
    },
    
    # Package classifiers
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Security",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Operating System :: OS Independent",
        "Environment :: Console",
        "Framework :: AWS CDK",
    ],
    
    # Keywords for PyPI
    keywords=[
        "aws",
        "cdk",
        "config",
        "compliance",
        "auto-remediation",
        "security",
        "governance",
        "lambda",
        "infrastructure-as-code",
        "cloud",
    ],
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/config/",
        "Source": "https://github.com/your-org/aws-config-auto-remediation",
        "Bug Reports": "https://github.com/your-org/aws-config-auto-remediation/issues",
        "AWS Config": "https://aws.amazon.com/config/",
        "AWS CDK": "https://aws.amazon.com/cdk/",
    },
    
    # License
    license="Apache License 2.0",
    
    # Additional metadata
    platforms=["any"],
    
    # Package data
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
)