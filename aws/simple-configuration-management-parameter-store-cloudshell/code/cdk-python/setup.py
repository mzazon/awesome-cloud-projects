"""
Setup configuration for Simple Configuration Management CDK Application

This setup.py file configures the Python package for the CDK application
that demonstrates Parameter Store configuration management patterns.
"""

from setuptools import setup, find_packages

# Read long description from README if it exists
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "CDK Application for Simple Configuration Management with Parameter Store and CloudShell"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file."""
    try:
        with open("requirements.txt", "r", encoding="utf-8") as req_file:
            return [
                line.strip()
                for line in req_file.readlines()
                if line.strip() and not line.startswith("#")
            ]
    except FileNotFoundError:
        return [
            "aws-cdk-lib>=2.100.0,<3.0.0",
            "constructs>=10.3.0,<11.0.0",
        ]

setup(
    name="simple-configuration-management-parameter-store",
    version="1.0.0",
    author="AWS CDK Recipe Generator",
    author_email="support@example.com",
    description="CDK Application for Simple Configuration Management with Parameter Store and CloudShell",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/cdk-recipes",
    
    # Package configuration
    packages=find_packages(exclude=["tests*"]),
    py_modules=["app"],
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=read_requirements(),
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.4.0",
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
    
    # Entry points for CLI commands
    entry_points={
        "console_scripts": [
            "deploy-config=app:main",
        ],
    },
    
    # Package classification
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP :: Site Management",
    ],
    
    # Keywords for discoverability
    keywords=[
        "aws",
        "cdk",
        "parameter-store",
        "configuration-management",
        "cloudshell",
        "infrastructure-as-code",
        "systems-manager",
    ],
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/cdk-recipes/issues",
        "Source": "https://github.com/aws-samples/cdk-recipes",
        "Documentation": "https://github.com/aws-samples/cdk-recipes/README.md",
    },
    
    # Include additional files
    include_package_data=True,
    zip_safe=False,
)