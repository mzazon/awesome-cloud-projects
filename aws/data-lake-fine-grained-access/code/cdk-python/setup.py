"""
Setup configuration for the Data Lake Formation Fine-Grained Access Control CDK application.

This setup.py file configures the Python package for the CDK application,
including dependencies, metadata, and entry points.
"""

import setuptools
from pathlib import Path

# Read the README file for long description
long_description = ""
readme_path = Path(__file__).parent / "README.md"
if readme_path.exists():
    with open(readme_path, "r", encoding="utf-8") as fh:
        long_description = fh.read()

# Read requirements from requirements.txt
requirements = []
requirements_path = Path(__file__).parent / "requirements.txt"
if requirements_path.exists():
    with open(requirements_path, "r", encoding="utf-8") as fh:
        requirements = [
            line.strip() 
            for line in fh.readlines() 
            if line.strip() and not line.startswith("#")
        ]

setuptools.setup(
    name="data-lake-formation-fgac",
    version="1.0.0",
    
    description="AWS CDK application for implementing Data Lake Formation with Fine-Grained Access Control",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS CDK Team",
    author_email="aws-cdk@amazon.com",
    
    url="https://github.com/aws/aws-cdk",
    
    package_dir={"": "."},
    packages=setuptools.find_packages(where="."),
    
    install_requires=requirements,
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
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
    
    keywords="aws cdk cloud infrastructure lake-formation data-governance security",
    
    project_urls={
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
    },
    
    entry_points={
        "console_scripts": [
            "data-lake-formation-fgac=app:main",
        ],
    },
    
    # Additional metadata
    zip_safe=False,
    include_package_data=True,
    
    # Optional dependencies for development
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "mypy>=1.0.0",
            "flake8>=5.0.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",
        ],
    },
)