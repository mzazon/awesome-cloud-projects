"""
Setup configuration for Visual Serverless Application CDK Python project

This setup.py file configures the Python package for the CDK application that creates
a complete serverless architecture with AWS Application Composer and CodeCatalyst integration.
"""

from setuptools import setup, find_packages

# Read requirements from requirements.txt
with open("requirements.txt", "r", encoding="utf-8") as f:
    requirements = [
        line.strip() for line in f.readlines() 
        if line.strip() and not line.startswith("#")
    ]

# Read long description from README if it exists
long_description = ""
try:
    with open("README.md", "r", encoding="utf-8") as f:
        long_description = f.read()
except FileNotFoundError:
    long_description = "CDK Python application for Visual Serverless Applications"

setup(
    name="visual-serverless-application-cdk",
    version="1.0.0",
    description="CDK Python application for Visual Serverless Applications with Infrastructure Composer",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS Recipes",
    author_email="noreply@aws.amazon.com",
    url="https://github.com/aws-recipes/visual-serverless-applications",
    packages=find_packages(),
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=requirements,
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.5.0",
            "isort>=5.12.0",
        ],
        "test": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "moto>=4.2.0",
            "pytest-mock>=3.11.0",
        ],
    },
    
    # Package classification
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
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
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "serverless",
        "infrastructure",
        "application-composer",
        "codecatalyst",
        "lambda",
        "apigateway",
        "dynamodb",
        "devops",
        "ci-cd",
        "cloud",
        "infrastructure-as-code",
    ],
    
    # Entry points for CLI commands
    entry_points={
        "console_scripts": [
            "visual-serverless-deploy=app:main",
        ],
    },
    
    # Package data
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.yml", "*.yaml", "*.json"],
    },
    
    # ZIP safe
    zip_safe=False,
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/aws-recipes/visual-serverless-applications/issues",
        "Source": "https://github.com/aws-recipes/visual-serverless-applications",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "AWS CDK": "https://aws.amazon.com/cdk/",
        "AWS Application Composer": "https://aws.amazon.com/application-composer/",
        "AWS CodeCatalyst": "https://aws.amazon.com/codecatalyst/",
    },
)