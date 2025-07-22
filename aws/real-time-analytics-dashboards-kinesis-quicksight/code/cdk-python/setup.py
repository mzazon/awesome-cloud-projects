"""
Setup script for Real-time Analytics Dashboard CDK Application

This setup script configures the Python package for the CDK application
that creates real-time analytics infrastructure using Kinesis, Flink, and QuickSight.
"""

import setuptools
from pathlib import Path

# Read the README file for long description
this_directory = Path(__file__).parent
long_description = (this_directory / "README.md").read_text() if (this_directory / "README.md").exists() else ""

# Read requirements from requirements.txt
requirements = []
requirements_path = this_directory / "requirements.txt"
if requirements_path.exists():
    with open(requirements_path, 'r') as f:
        requirements = [
            line.strip() 
            for line in f 
            if line.strip() and not line.startswith('#')
        ]

setuptools.setup(
    name="real-time-analytics-dashboard-cdk",
    version="1.0.0",
    
    description="AWS CDK Python application for real-time analytics dashboards",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS CDK Developer",
    author_email="developer@example.com",
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Code Generators",
        "Topic :: Utilities",
        "Typing :: Typed",
    ],
    
    install_requires=requirements,
    
    extras_require={
        "dev": [
            "pytest>=6.2.0",
            "pytest-cov>=2.12.0",
            "mypy>=1.0.0",
            "black>=22.0.0",
            "flake8>=4.0.0",
        ],
        "docs": [
            "sphinx>=4.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
    },
    
    py_modules=["app"],
    
    entry_points={
        "console_scripts": [
            "deploy-analytics=app:main",
        ],
    },
    
    project_urls={
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Source": "https://github.com/aws/aws-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
    },
    
    keywords=[
        "aws",
        "cdk",
        "kinesis",
        "flink",
        "analytics",
        "real-time",
        "streaming",
        "quicksight",
        "dashboard",
        "infrastructure",
        "iac"
    ],
    
    zip_safe=False,
)