"""
Setup configuration for Savings Plans Recommendations CDK Python Application.

This setup file configures the Python package for the CDK application that
creates infrastructure for automated Savings Plans analysis using Cost Explorer.
"""

from setuptools import setup, find_packages

# Read the README file for long description
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "CDK Python application for automated Savings Plans recommendations analysis"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file."""
    try:
        with open("requirements.txt", "r", encoding="utf-8") as req_file:
            return [
                line.strip() 
                for line in req_file 
                if line.strip() and not line.startswith("#")
            ]
    except FileNotFoundError:
        return [
            "aws-cdk-lib>=2.111.0",
            "constructs>=10.0.0,<11.0.0",
            "boto3>=1.28.0",
            "botocore>=1.31.0",
        ]

setup(
    name="savings-plans-recommendations-cdk",
    version="1.0.0",
    author="AWS Cost Optimization Team",
    author_email="cost-optimization@example.com",
    description="CDK Python application for automated Savings Plans recommendations using Cost Explorer",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/example/savings-plans-recommendations-cdk",
    packages=find_packages(),
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: System :: Systems Administration",
        "Topic :: Office/Business :: Financial",
        "Typing :: Typed",
    ],
    python_requires=">=3.8",
    install_requires=read_requirements(),
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "pytest-mock>=3.0.0",
            "moto>=4.0.0",
            "black>=22.0.0",
            "isort>=5.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "cdk-deploy=app:main",
        ],
    },
    package_data={
        "": ["*.json", "*.yaml", "*.yml", "*.md"],
    },
    include_package_data=True,
    zip_safe=False,
    keywords=[
        "aws",
        "cdk",
        "cost-optimization",
        "savings-plans",
        "cost-explorer",
        "infrastructure-as-code",
        "serverless",
        "lambda",
        "financial-management",
    ],
    project_urls={
        "Bug Reports": "https://github.com/example/savings-plans-recommendations-cdk/issues",
        "Source": "https://github.com/example/savings-plans-recommendations-cdk",
        "Documentation": "https://github.com/example/savings-plans-recommendations-cdk/docs",
    },
)