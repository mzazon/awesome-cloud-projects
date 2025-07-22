"""
Setup configuration for the Real-time Anomaly Detection CDK Python application.

This setup.py file configures the Python package for the CDK application,
including dependencies, metadata, and installation requirements.
"""

import setuptools
from pathlib import Path

# Read the README file for the long description
readme_path = Path(__file__).parent / "README.md"
long_description = readme_path.read_text(encoding="utf-8") if readme_path.exists() else ""

# Read requirements from requirements.txt
requirements_path = Path(__file__).parent / "requirements.txt"
requirements = []
if requirements_path.exists():
    with open(requirements_path, "r", encoding="utf-8") as f:
        requirements = [
            line.strip()
            for line in f
            if line.strip() and not line.startswith("#")
        ]

setuptools.setup(
    name="real-time-anomaly-detection-cdk",
    version="1.0.0",
    
    description="AWS CDK Python application for real-time anomaly detection using Kinesis Data Analytics",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="Data Engineering Team",
    author_email="data-engineering@company.com",
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Monitoring",
        "Topic :: Scientific/Engineering :: Information Analysis",
    ],
    
    packages=setuptools.find_packages(),
    
    install_requires=requirements,
    
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.5.0",
            "bandit>=1.7.5",
            "safety>=2.3.0",
        ],
        "docs": [
            "sphinx>=7.1.0",
            "sphinx-rtd-theme>=1.3.0",
        ],
    },
    
    entry_points={
        "console_scripts": [
            "anomaly-detection-cdk=app:main",
        ],
    },
    
    package_data={
        "": [
            "*.json",
            "*.yaml",
            "*.yml",
            "*.md",
            "*.txt",
        ],
    },
    
    include_package_data=True,
    
    keywords=[
        "aws",
        "cdk",
        "kinesis",
        "analytics",
        "anomaly-detection",
        "real-time",
        "streaming",
        "apache-flink",
        "machine-learning",
        "monitoring",
    ],
    
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws-samples/cdk-examples",
        "Tracker": "https://github.com/aws/aws-cdk/issues",
    },
    
    # Ensure compatibility with CDK versioning
    zip_safe=False,
)