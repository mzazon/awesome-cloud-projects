"""
Setup configuration for Amazon QLDB ACID-compliant database CDK Python application.

This setup.py file defines the package configuration, dependencies, and metadata
for the CDK Python application that deploys Amazon QLDB infrastructure.
"""

from setuptools import setup, find_packages
import os

# Read long description from README if it exists
long_description = "CDK Python application for Amazon QLDB ACID-compliant distributed database"
readme_path = os.path.join(os.path.dirname(__file__), "README.md")
if os.path.exists(readme_path):
    with open(readme_path, "r", encoding="utf-8") as fh:
        long_description = fh.read()

# Read requirements from requirements.txt
def parse_requirements():
    """Parse requirements.txt file and return list of dependencies."""
    requirements = []
    requirements_path = os.path.join(os.path.dirname(__file__), "requirements.txt")
    
    if os.path.exists(requirements_path):
        with open(requirements_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                # Skip comments and empty lines
                if line and not line.startswith("#"):
                    requirements.append(line)
    
    return requirements

setup(
    name="qldb-acid-database-cdk",
    version="1.0.0",
    author="AWS Recipe Generator",
    author_email="aws-recipes@example.com",
    description="CDK Python application for Amazon QLDB ACID-compliant distributed database",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-recipes/qldb-acid-database",
    
    # Package discovery
    packages=find_packages(),
    py_modules=["app"],
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=parse_requirements(),
    
    # Optional dependencies for development
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.5.0",
            "bandit>=1.7.0",
        ],
        "docs": [
            "sphinx>=7.0.0",
            "sphinx-rtd-theme>=1.3.0",
        ],
    },
    
    # Entry points for command line execution
    entry_points={
        "console_scripts": [
            "qldb-cdk=app:main",
        ],
    },
    
    # Classifiers for PyPI
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Operating System :: OS Independent",
        "Topic :: Database",
        "Topic :: Database :: Database Engines/Servers",
        "Topic :: System :: Distributed Computing",
    ],
    
    # Keywords for searchability
    keywords="aws cdk python qldb acid database ledger blockchain financial compliance",
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/aws-recipes/qldb-acid-database/issues",
        "Source": "https://github.com/aws-recipes/qldb-acid-database",
        "Documentation": "https://docs.aws.amazon.com/qldb/",
        "AWS CDK": "https://docs.aws.amazon.com/cdk/",
    },
    
    # Include additional files
    include_package_data=True,
    
    # License
    license="Apache-2.0",
    
    # Zip safe flag
    zip_safe=False,
)