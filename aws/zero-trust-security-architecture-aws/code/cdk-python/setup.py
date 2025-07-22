"""
Setup configuration for AWS Zero Trust Security Architecture CDK Application

This setup.py file configures the Python package for the CDK application
implementing a comprehensive zero trust security architecture on AWS.
"""

from setuptools import setup, find_packages

# Read long description from README if it exists
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "AWS Zero Trust Security Architecture CDK Application"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file."""
    try:
        with open("requirements.txt", "r", encoding="utf-8") as f:
            return [line.strip() for line in f if line.strip() and not line.startswith("#")]
    except FileNotFoundError:
        # Fallback requirements if file doesn't exist
        return [
            "aws-cdk-lib>=2.164.0",
            "constructs>=10.0.0",
            "boto3>=1.34.0"
        ]

setup(
    # Package metadata
    name="zero-trust-security-cdk",
    version="1.0.0",
    author="AWS CDK Generator",
    author_email="aws-cdk@example.com",
    description="AWS CDK application for implementing zero trust security architecture",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/aws-zero-trust-security-architecture",
    
    # Package configuration
    packages=find_packages(exclude=["tests*"]),
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
        "Topic :: Security",
        "Topic :: System :: Systems Administration",
        "Topic :: Software Development :: Libraries :: Python Modules",
    ],
    
    # Python version requirements
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=read_requirements(),
    
    # Development dependencies
    extras_require={
        "dev": [
            "black>=23.0.0",
            "pytest>=7.0.0",
            "mypy>=1.0.0",
            "bandit>=1.7.0",
            "safety>=2.0.0",
            "pre-commit>=3.0.0",
        ],
        "docs": [
            "sphinx>=6.0.0",
            "sphinx-rtd-theme>=1.2.0",
            "myst-parser>=1.0.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",
        ]
    },
    
    # Entry points
    entry_points={
        "console_scripts": [
            "cdk-deploy=app:main",
        ],
    },
    
    # Include additional files
    include_package_data=True,
    zip_safe=False,
    
    # Keywords for discovery
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "security",
        "zero-trust",
        "iam",
        "guardduty",
        "security-hub",
        "compliance"
    ],
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/aws-zero-trust-security-architecture/issues",
        "Source": "https://github.com/aws-samples/aws-zero-trust-security-architecture",
        "Documentation": "https://aws-zero-trust-security-architecture.readthedocs.io/",
    },
)