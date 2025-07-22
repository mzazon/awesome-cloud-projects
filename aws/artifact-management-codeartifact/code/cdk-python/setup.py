"""
Setup configuration for AWS CodeArtifact CDK Python application.
This file defines the package metadata and dependencies for the CDK app.
"""

from setuptools import setup, find_packages

# Read the contents of README file
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "AWS CDK Python application for CodeArtifact infrastructure"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file."""
    try:
        with open("requirements.txt", "r", encoding="utf-8") as req_file:
            requirements = []
            for line in req_file:
                line = line.strip()
                # Skip comments and empty lines
                if line and not line.startswith("#"):
                    requirements.append(line)
            return requirements
    except FileNotFoundError:
        return [
            "aws-cdk-lib>=2.100.0,<3.0.0",
            "constructs>=10.3.0,<11.0.0"
        ]

setup(
    name="codeartifact-cdk-app",
    version="1.0.0",
    
    description="AWS CDK Python application for CodeArtifact artifact management infrastructure",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="Development Team",
    author_email="dev-team@company.com",
    
    url="https://github.com/company/codeartifact-infrastructure",
    
    packages=find_packages(exclude=["tests*"]),
    
    install_requires=read_requirements(),
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP :: HTTP Servers",
    ],
    
    keywords="aws cdk codeartifact infrastructure artifacts devops",
    
    entry_points={
        "console_scripts": [
            "deploy-codeartifact=app:main",
        ],
    },
    
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.5.0",
        ],
        "test": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "moto>=4.2.0",
        ],
    },
    
    project_urls={
        "Bug Reports": "https://github.com/company/codeartifact-infrastructure/issues",
        "Source": "https://github.com/company/codeartifact-infrastructure",
        "Documentation": "https://docs.company.com/codeartifact-infrastructure",
    },
    
    include_package_data=True,
    zip_safe=False,
)