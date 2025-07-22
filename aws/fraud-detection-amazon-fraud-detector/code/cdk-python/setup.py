"""
Setup configuration for Real-Time Fraud Detection CDK Application

This setup.py file configures the Python package for the fraud detection CDK application,
including dependencies, metadata, and development requirements.
"""

import setuptools
from pathlib import Path

# Read the README file for long description
this_directory = Path(__file__).parent
long_description = ""
readme_path = this_directory / "README.md"
if readme_path.exists():
    with open(readme_path, "r", encoding="utf-8") as fh:
        long_description = fh.read()

# Read requirements from requirements.txt
requirements_path = this_directory / "requirements.txt"
install_requires = []
if requirements_path.exists():
    with open(requirements_path, "r", encoding="utf-8") as fh:
        install_requires = [
            line.strip() 
            for line in fh.readlines() 
            if line.strip() and not line.startswith("#")
        ]

setuptools.setup(
    name="real-time-fraud-detection-cdk",
    version="1.0.0",
    
    description="Real-Time Fraud Detection platform using Amazon Fraud Detector",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS Solutions",
    author_email="aws-solutions@amazon.com",
    
    url="https://github.com/aws-samples/fraud-detection-cdk",
    
    packages=setuptools.find_packages(),
    
    install_requires=install_requires,
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: Financial and Insurance Industry",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: Security",
        "Topic :: Office/Business :: Financial",
        "Topic :: Scientific/Engineering :: Artificial Intelligence",
    ],
    
    keywords=[
        "aws",
        "cdk",
        "fraud-detection",
        "machine-learning",
        "real-time",
        "amazon-fraud-detector",
        "fintech",
        "security",
        "risk-management"
    ],
    
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/frauddetector/",
        "Source": "https://github.com/aws-samples/fraud-detection-cdk",
        "Tracker": "https://github.com/aws-samples/fraud-detection-cdk/issues",
    },
    
    # Entry points for CLI commands
    entry_points={
        "console_scripts": [
            "fraud-detection-cdk=app:main",
        ],
    },
    
    # Additional package data
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "bandit>=1.7.0",
            "safety>=2.0.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",
            "boto3-stubs[essential]>=1.26.0",
        ],
    },
    
    # Include additional files in the package
    include_package_data=True,
    
    # ZIP safe
    zip_safe=False,
    
    # License
    license="MIT",
    
    # Platforms
    platforms=["any"],
)