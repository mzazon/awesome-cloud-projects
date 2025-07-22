"""
Setup configuration for the API Composition CDK Python application.

This setup.py file configures the Python package for the CDK application,
including dependencies, metadata, and installation requirements.
"""

import setuptools
from pathlib import Path

# Read the requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file."""
    requirements_file = Path(__file__).parent / "requirements.txt"
    if requirements_file.exists():
        with open(requirements_file, 'r', encoding='utf-8') as f:
            requirements = []
            for line in f:
                line = line.strip()
                # Skip comments and empty lines
                if line and not line.startswith('#'):
                    requirements.append(line)
            return requirements
    return []

# Read the README file for long description
def read_readme():
    """Read README file for long description."""
    readme_file = Path(__file__).parent / "README.md"
    if readme_file.exists():
        with open(readme_file, 'r', encoding='utf-8') as f:
            return f.read()
    return "CDK Python application for API Composition with Step Functions and API Gateway"

setuptools.setup(
    name="api-composition-cdk",
    version="1.0.0",
    
    description="CDK Python application for API Composition with Step Functions and API Gateway",
    long_description=read_readme(),
    long_description_content_type="text/markdown",
    
    author="AWS Solutions Architecture Team",
    author_email="solutions-team@amazon.com",
    
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
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Code Generators",
        "Topic :: Utilities",
        "Typing :: Typed",
    ],
    
    packages=setuptools.find_packages(),
    
    install_requires=read_requirements(),
    
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
        ],
        "docs": [
            "sphinx>=7.0.0",
            "sphinx-rtd-theme>=1.3.0",
        ],
    },
    
    entry_points={
        "console_scripts": [
            "api-composition-cdk=app:main",
        ],
    },
    
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/cloud-recipes/issues",
        "Documentation": "https://github.com/aws-samples/cloud-recipes/blob/main/aws/api-composition-step-functions-api-gateway/README.md",
        "Source": "https://github.com/aws-samples/cloud-recipes",
    },
    
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "step-functions",
        "api-gateway",
        "serverless",
        "microservices",
        "api-composition",
        "orchestration"
    ],
    
    include_package_data=True,
    zip_safe=False,
)