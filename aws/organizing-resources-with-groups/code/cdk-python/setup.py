"""
Setup configuration for AWS CDK Resource Group Automated Management application.

This package contains the CDK Python application for implementing automated
resource management using AWS Resource Groups, Systems Manager, CloudWatch,
and SNS.
"""

import setuptools
from pathlib import Path

# Read the README file for long description
readme_path = Path(__file__).parent / "README.md"
if readme_path.exists():
    with open(readme_path, "r", encoding="utf-8") as fh:
        long_description = fh.read()
else:
    long_description = "AWS CDK Python application for Resource Group Automated Management"

# Read requirements from requirements.txt
requirements_path = Path(__file__).parent / "requirements.txt"
with open(requirements_path, "r", encoding="utf-8") as fh:
    requirements = [
        line.strip() 
        for line in fh 
        if line.strip() and not line.startswith("#")
    ]

setuptools.setup(
    name="resource-group-automated-management",
    version="1.0.0",
    author="AWS CDK Developer",
    author_email="developer@example.com",
    description="AWS CDK application for automated resource management using Resource Groups",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/your-org/resource-group-automated-management",
    project_urls={
        "Bug Tracker": "https://github.com/your-org/resource-group-automated-management/issues",
        "Documentation": "https://docs.aws.amazon.com/resourcegroups/",
        "Source Code": "https://github.com/your-org/resource-group-automated-management",
    },
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Utilities",
        "Typing :: Typed",
    ],
    packages=setuptools.find_packages(),
    python_requires=">=3.8",
    install_requires=requirements,
    extras_require={
        "dev": [
            "pytest>=6.0",
            "pytest-cov>=2.0",
            "black>=21.0",
            "flake8>=3.8",
            "mypy>=0.910",
            "pre-commit>=2.0",
        ],
        "docs": [
            "sphinx>=4.0",
            "sphinx-rtd-theme>=0.5",
            "myst-parser>=0.15",
        ],
    },
    entry_points={
        "console_scripts": [
            "deploy-resource-management=app:main",
        ],
    },
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.yaml", "*.yml", "*.json"],
    },
    zip_safe=False,
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "resource-groups",
        "automation",
        "monitoring",
        "systems-manager",
        "cloudwatch",
        "sns",
        "devops",
        "cost-optimization",
        "compliance",
    ],
)