"""
Setup configuration for the Advanced Data Lake Governance CDK Python application.

This setup.py file configures the Python package for the Data Lake Governance
solution that implements AWS Lake Formation and Amazon DataZone for enterprise
data governance, security, and discovery.
"""

import setuptools
from pathlib import Path

# Read the README file for long description
readme_path = Path(__file__).parent / "README.md"
long_description = ""
if readme_path.exists():
    with open(readme_path, "r", encoding="utf-8") as fh:
        long_description = fh.read()

# Read requirements from requirements.txt
requirements_path = Path(__file__).parent / "requirements.txt"
install_requires = []
if requirements_path.exists():
    with open(requirements_path, "r", encoding="utf-8") as fh:
        install_requires = [
            line.strip() 
            for line in fh.readlines() 
            if line.strip() and not line.startswith("#")
        ]

setuptools.setup(
    name="advanced-data-lake-governance-cdk",
    version="1.0.0",
    
    # Package description
    description="AWS CDK Python application for Advanced Data Lake Governance with Lake Formation and DataZone",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    # Author information
    author="AWS Solutions Architecture",
    author_email="solutions@aws.amazon.com",
    
    # Package metadata
    url="https://github.com/aws-samples/data-lake-governance-cdk",
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/data-lake-governance-cdk/issues",
        "Source": "https://github.com/aws-samples/data-lake-governance-cdk",
        "Documentation": "https://docs.aws.amazon.com/lake-formation/",
    },
    
    # Package classification
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Database :: Database Engines/Servers",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: JavaScript",
        "Operating System :: OS Independent",
    ],
    
    # Python version requirements
    python_requires=">=3.8",
    
    # Package dependencies
    install_requires=install_requires,
    
    # Optional dependencies for different use cases
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "pylint>=2.17.0",
        ],
        "testing": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "boto3>=1.34.0",
            "moto>=4.2.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.2.0",
            "sphinx-autoapi>=2.1.0",
        ],
        "security": [
            "safety>=2.3.0",
            "bandit>=1.7.0",
        ],
    },
    
    # Package discovery
    packages=setuptools.find_packages(exclude=["tests", "tests.*"]),
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    include_package_data=True,
    
    # Entry points for command-line tools
    entry_points={
        "console_scripts": [
            "deploy-data-lake-governance=app:main",
        ],
    },
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "cloud development kit",
        "infrastructure as code",
        "data lake",
        "data governance",
        "lake formation",
        "datazone",
        "aws glue",
        "data catalog",
        "analytics",
        "big data",
        "data security",
        "compliance",
        "data discovery",
        "data lineage",
    ],
    
    # License
    license="MIT",
    
    # Zip safety
    zip_safe=False,
)