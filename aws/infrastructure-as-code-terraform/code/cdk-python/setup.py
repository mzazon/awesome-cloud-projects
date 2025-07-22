"""
Setup configuration for Infrastructure as Code CDK Python application

This setup.py file configures the Python package for the Infrastructure as Code
demo application using AWS CDK. It includes all necessary dependencies and
metadata for proper package management and distribution.
"""

import setuptools
from typing import List


def read_requirements() -> List[str]:
    """
    Read requirements from requirements.txt file
    
    Returns:
        List[str]: List of package requirements
    """
    try:
        with open("requirements.txt", "r", encoding="utf-8") as req_file:
            requirements = []
            for line in req_file:
                line = line.strip()
                # Skip empty lines and comments
                if line and not line.startswith("#"):
                    requirements.append(line)
            return requirements
    except FileNotFoundError:
        # Fallback requirements if file not found
        return [
            "aws-cdk-lib>=2.110.0,<3.0.0",
            "constructs>=10.3.0,<11.0.0",
            "boto3>=1.28.0",
        ]


def read_long_description() -> str:
    """
    Read long description from README file
    
    Returns:
        str: Long description for the package
    """
    try:
        with open("README.md", "r", encoding="utf-8") as readme_file:
            return readme_file.read()
    except FileNotFoundError:
        return "Infrastructure as Code demo using AWS CDK Python"


setuptools.setup(
    name="infrastructure-as-code-cdk-python",
    version="1.0.0",
    
    # Package metadata
    author="Cloud Recipes Team",
    author_email="cloudrecipes@example.com",
    description="Infrastructure as Code demo using AWS CDK Python",
    long_description=read_long_description(),
    long_description_content_type="text/markdown",
    
    # URLs and classifiers
    url="https://github.com/cloudrecipes/infrastructure-as-code-terraform-aws",
    project_urls={
        "Bug Tracker": "https://github.com/cloudrecipes/infrastructure-as-code-terraform-aws/issues",
        "Documentation": "https://github.com/cloudrecipes/infrastructure-as-code-terraform-aws/blob/main/README.md",
        "Source Code": "https://github.com/cloudrecipes/infrastructure-as-code-terraform-aws",
    },
    
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
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: System :: Systems Administration",
        "Topic :: Utilities",
        "Typing :: Typed",
    ],
    
    # Package configuration
    packages=setuptools.find_packages(exclude=["tests", "tests.*"]),
    package_data={
        "": ["*.md", "*.txt", "*.yml", "*.yaml", "*.json"],
    },
    include_package_data=True,
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=read_requirements(),
    
    # Optional dependencies for development
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.7.0",
            "mypy>=1.5.0",
            "flake8>=6.0.0",
            "boto3-stubs[essential]>=1.28.0",
            "types-setuptools>=68.0.0",
        ],
        "testing": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "moto>=4.2.0",  # AWS service mocking for tests
        ],
    },
    
    # Entry points for CLI commands
    entry_points={
        "console_scripts": [
            "deploy-infrastructure=app:main",
        ],
    },
    
    # Package options
    zip_safe=False,
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "infrastructure",
        "cloud",
        "devops",
        "terraform",
        "iac",
        "python",
        "cloudformation",
        "automation",
    ],
)