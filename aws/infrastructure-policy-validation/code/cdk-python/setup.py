"""
Setup configuration for CloudFormation Guard Policy Validation CDK application.

This setup.py file configures the Python package for the CDK application
that creates infrastructure for automated policy validation using
CloudFormation Guard.
"""

import setuptools
from pathlib import Path

# Read long description from README if it exists
long_description = "CloudFormation Guard Policy Validation CDK Application"
readme_path = Path(__file__).parent / "README.md"
if readme_path.exists():
    with open(readme_path, "r", encoding="utf-8") as fh:
        long_description = fh.read()

# Read requirements from requirements.txt
install_requires = []
requirements_path = Path(__file__).parent / "requirements.txt"
if requirements_path.exists():
    with open(requirements_path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if line and not line.startswith("#"):
                # Remove comments from the line
                package = line.split("#")[0].strip()
                if package:
                    install_requires.append(package)

setuptools.setup(
    # Package metadata
    name="cloudformation-guard-validation-cdk",
    version="1.0.0",
    author="Infrastructure Team",
    author_email="infrastructure@example.com",
    description="AWS CDK application for CloudFormation Guard policy validation infrastructure",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/your-org/cloudformation-guard-validation",
    
    # Package configuration
    packages=setuptools.find_packages(),
    include_package_data=True,
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=install_requires,
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "isort>=5.0.0",
            "autoflake>=1.4.0",
            "bandit>=1.7.0",
            "safety>=2.0.0"
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0"
        ]
    },
    
    # Package classification
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
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Utilities",
        "Framework :: AWS CDK",
        "Framework :: AWS CDK :: 2"
    ],
    
    # Keywords for discoverability
    keywords=[
        "aws",
        "cdk",
        "cloudformation",
        "guard",
        "policy",
        "validation",
        "infrastructure",
        "compliance",
        "governance",
        "security"
    ],
    
    # Entry points for command line tools (if any)
    entry_points={
        "console_scripts": [
            # Add any CLI tools here if needed
        ],
    },
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/your-org/cloudformation-guard-validation/issues",
        "Source": "https://github.com/your-org/cloudformation-guard-validation",
        "Documentation": "https://your-org.github.io/cloudformation-guard-validation/",
    },
    
    # Additional metadata
    platforms=["any"],
    zip_safe=False,
    
    # Package data
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
)