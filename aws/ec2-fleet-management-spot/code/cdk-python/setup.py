"""
Setup configuration for EC2 Fleet Management CDK Python application.

This setup.py file configures the Python package for the EC2 Fleet Management
solution, including dependencies, metadata, and build configuration.
"""

from setuptools import setup, find_packages
from pathlib import Path

# Read the contents of README file for long description
this_directory = Path(__file__).parent
long_description = (this_directory / "README.md").read_text() if (this_directory / "README.md").exists() else ""

# Read requirements from requirements.txt
requirements_path = this_directory / "requirements.txt"
install_requires = []
if requirements_path.exists():
    with open(requirements_path, "r", encoding="utf-8") as f:
        install_requires = [
            line.strip() 
            for line in f.readlines() 
            if line.strip() and not line.startswith("#")
        ]

setup(
    name="ec2-fleet-management-cdk",
    version="1.0.0",
    description="AWS CDK Python application for EC2 Fleet Management with Spot Instances",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS CDK Recipe",
    author_email="your-email@example.com",
    url="https://github.com/your-org/ec2-fleet-management-cdk",
    
    # Package configuration
    packages=find_packages(exclude=["tests*"]),
    include_package_data=True,
    zip_safe=False,
    
    # Python version requirements
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=install_requires,
    
    # Optional dependencies for development
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.2.0",
        ],
        "security": [
            "safety>=2.0.0",
            "bandit>=1.7.0",
        ],
    },
    
    # Entry points for command-line tools
    entry_points={
        "console_scripts": [
            "ec2-fleet-cdk=app:main",
        ],
    },
    
    # Package classification
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
        "Topic :: Software Development :: Code Generators",
        "Typing :: Typed",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "ec2",
        "fleet",
        "spot-instances",
        "on-demand",
        "infrastructure",
        "cloud",
        "cost-optimization",
        "auto-scaling",
    ],
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/your-org/ec2-fleet-management-cdk/issues",
        "Source": "https://github.com/your-org/ec2-fleet-management-cdk",
        "Documentation": "https://github.com/your-org/ec2-fleet-management-cdk/blob/main/README.md",
    },
    
    # Package metadata
    license="Apache-2.0",
    platforms=["any"],
    
    # Additional metadata
    maintainer="AWS CDK Recipe Team",
    maintainer_email="your-team@example.com",
)