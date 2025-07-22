"""
AWS CDK Python Setup Configuration for IoT Device Shadow Synchronization

This setup.py file configures the Python package for the IoT Device Shadow
Synchronization CDK application with all necessary dependencies and metadata.

Author: AWS CDK Generator v1.3
License: MIT
"""

import setuptools
from pathlib import Path

# Read the README file for long description
readme_path = Path(__file__).parent / "README.md"
long_description = readme_path.read_text(encoding="utf-8") if readme_path.exists() else ""

# Read requirements from requirements.txt
requirements_path = Path(__file__).parent / "requirements.txt"
requirements = []
if requirements_path.exists():
    with open(requirements_path, "r", encoding="utf-8") as f:
        requirements = [
            line.strip() 
            for line in f 
            if line.strip() and not line.startswith("#")
        ]

setuptools.setup(
    name="iot-shadow-synchronization-cdk",
    version="1.0.0",
    
    description="AWS CDK Python application for Advanced IoT Device Shadow Synchronization",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS CDK Generator",
    author_email="developer@example.com",
    
    url="https://github.com/aws-samples/iot-shadow-synchronization",
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Networking",
        "Topic :: Internet :: WWW/HTTP",
        "Typing :: Typed",
    ],
    
    packages=setuptools.find_packages(),
    
    install_requires=requirements,
    
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "pre-commit>=3.0.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
            "myst-parser>=0.18.0",
        ],
    },
    
    entry_points={
        "console_scripts": [
            "iot-shadow-sync=app:main",
        ],
    },
    
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/iot-shadow-synchronization/issues",
        "Source": "https://github.com/aws-samples/iot-shadow-synchronization",
        "Documentation": "https://docs.aws.amazon.com/iot/latest/developerguide/iot-device-shadows.html",
    },
    
    keywords=[
        "aws",
        "cdk",
        "iot",
        "device-shadow",
        "synchronization",
        "conflict-resolution",
        "cloud",
        "infrastructure",
        "serverless",
        "lambda",
        "dynamodb",
        "eventbridge",
        "cloudwatch",
    ],
    
    include_package_data=True,
    zip_safe=False,
)