"""
Setup configuration for Amazon QuickSight Business Intelligence Dashboard CDK Python Application

This setup.py file configures the Python package for deploying a complete QuickSight
business intelligence solution including S3 data sources, IAM roles, datasets,
analyses, and interactive dashboards.

Author: AWS CDK Generator
Version: 1.0
"""

from setuptools import setup, find_packages

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

with open("requirements.txt", "r", encoding="utf-8") as fh:
    requirements = [line.strip() for line in fh if line.strip() and not line.startswith("#")]

setup(
    name="quicksight-business-intelligence-cdk",
    version="1.0.0",
    author="AWS CDK Generator",
    author_email="aws-cdk@example.com",
    description="CDK Python application for deploying Amazon QuickSight Business Intelligence Dashboard solution",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/quicksight-business-intelligence-cdk",
    project_urls={
        "Bug Tracker": "https://github.com/aws-samples/quicksight-business-intelligence-cdk/issues",
        "Documentation": "https://docs.aws.amazon.com/quicksight/",
        "Source Code": "https://github.com/aws-samples/quicksight-business-intelligence-cdk",
    },
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP",
        "Topic :: Scientific/Engineering :: Visualization",
        "Typing :: Typed",
    ],
    packages=find_packages(exclude=["tests", "tests.*"]),
    python_requires=">=3.9",
    install_requires=requirements,
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "bandit>=1.7.0",
            "safety>=2.3.0",
        ],
        "docs": [
            "sphinx>=6.0.0",
            "sphinx-rtd-theme>=1.2.0",
        ],
        "analysis": [
            "ipython>=8.0.0",
            "jupyter>=1.0.0",
            "pandas>=2.0.0",
            "matplotlib>=3.6.0",
            "seaborn>=0.12.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "deploy-quicksight=app:main",
        ],
    },
    include_package_data=True,
    package_data={
        "": ["*.yaml", "*.yml", "*.json", "*.txt", "*.md"],
    },
    zip_safe=False,
    keywords=[
        "aws",
        "cdk",
        "quicksight",
        "business-intelligence",
        "dashboard",
        "analytics",
        "data-visualization",
        "s3",
        "cloud",
        "infrastructure",
        "iac",
        "python",
    ],
    platforms=["any"],
)