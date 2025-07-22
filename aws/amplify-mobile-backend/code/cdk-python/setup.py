"""
Setup configuration for Mobile Backend Services CDK Python application.
This file configures the Python package for the AWS CDK infrastructure code.
"""

import setuptools
from pathlib import Path

# Read the README file for long description
readme_path = Path(__file__).parent / "README.md"
long_description = readme_path.read_text(encoding="utf-8") if readme_path.exists() else ""

# Read requirements from requirements.txt
requirements_path = Path(__file__).parent / "requirements.txt"
if requirements_path.exists():
    with open(requirements_path, "r", encoding="utf-8") as f:
        requirements = [
            line.strip() 
            for line in f 
            if line.strip() and not line.startswith("#")
        ]
else:
    requirements = [
        "aws-cdk-lib>=2.125.0",
        "constructs>=10.0.0,<11.0.0",
        "aws-cdk.aws-appsync-alpha>=2.125.0a0"
    ]

setuptools.setup(
    name="mobile-backend-services-amplify",
    version="1.0.0",
    description="AWS CDK application for Mobile Backend Services with Amplify-compatible infrastructure",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    # Author information
    author="AWS Cloud Recipe Team",
    author_email="recipes@aws.com",
    
    # Package configuration
    packages=setuptools.find_packages(),
    python_requires=">=3.8",
    install_requires=requirements,
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=6.2.5",
            "pytest-cov>=2.12.1",
            "black>=21.9.0",
            "isort>=5.9.3",
            "flake8>=3.9.2",
            "mypy>=0.910",
            "safety>=2.3.0",
            "bandit>=1.7.0"
        ],
        "docs": [
            "sphinx>=4.2.0",
            "sphinx-rtd-theme>=1.0.0"
        ]
    },
    
    # Project metadata
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Utilities"
    ],
    
    # Project URLs
    project_urls={
        "Documentation": "https://github.com/aws-samples/cloud-recipes",
        "Source": "https://github.com/aws-samples/cloud-recipes",
        "Bug Reports": "https://github.com/aws-samples/cloud-recipes/issues"
    },
    
    # Keywords for PyPI search
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "mobile",
        "backend",
        "amplify",
        "cognito",
        "appsync",
        "dynamodb",
        "lambda",
        "pinpoint",
        "graphql",
        "serverless"
    ],
    
    # Entry points for command-line scripts
    entry_points={
        "console_scripts": [
            "deploy-mobile-backend=app:main",
        ],
    },
    
    # Include additional files
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.yaml", "*.yml", "*.json"],
    },
    
    # Exclude files from package
    exclude_package_data={
        "": ["*.pyc", "*.pyo", "__pycache__/*"],
    },
    
    # Zip safety
    zip_safe=False,
)