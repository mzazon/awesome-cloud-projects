"""
Setup configuration for AWS CDK Python Service Health Notifications application.

This setup.py file configures the Python package for the CDK application,
including dependencies, metadata, and entry points.
"""

import setuptools

# Read long description from README if it exists
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "AWS CDK Python application for Service Health Notifications"

# Read requirements from requirements.txt
with open("requirements.txt", "r", encoding="utf-8") as fh:
    requirements = [
        line.strip() 
        for line in fh 
        if line.strip() and not line.startswith("#")
    ]

setuptools.setup(
    name="service-health-notifications-cdk",
    version="1.0.0",
    
    author="AWS CDK Recipe Generator",
    author_email="recipes@example.com",
    
    description="AWS CDK Python application for automated service health notifications",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    url="https://github.com/aws-samples/aws-cdk-examples",
    
    project_urls={
        "Bug Tracker": "https://github.com/aws-samples/aws-cdk-examples/issues",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source Code": "https://github.com/aws-samples/aws-cdk-examples",
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
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Monitoring",
        "Topic :: System :: Systems Administration",
    ],
    
    packages=setuptools.find_packages(),
    
    python_requires=">=3.8",
    
    install_requires=requirements,
    
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.7.0",
            "flake8>=6.0.0",
            "mypy>=1.5.0",
            "bandit>=1.7.5",
        ],
        "docs": [
            "sphinx>=7.1.0",
            "sphinx-rtd-theme>=1.3.0",
        ],
    },
    
    entry_points={
        "console_scripts": [
            "service-health-notifications=app:main",
        ],
    },
    
    keywords=[
        "aws",
        "cdk",
        "health",
        "notifications",
        "monitoring",
        "sns",
        "eventbridge",
        "infrastructure",
        "automation",
    ],
    
    zip_safe=False,
    
    # Additional metadata
    platforms=["any"],
    
    # Package data (if needed)
    include_package_data=True,
    
    # CDK-specific metadata
    options={
        "build_scripts": {
            "executable": "/usr/bin/env python3"
        }
    }
)