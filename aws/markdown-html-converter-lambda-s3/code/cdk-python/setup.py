"""
Setup configuration for the Markdown to HTML Converter CDK Python application.

This setup.py file defines the package metadata and dependencies for the
AWS CDK Python application that creates a serverless document converter.
"""

from setuptools import setup, find_packages

# Read the README file for long description
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "Simple Markdown to HTML Converter using AWS Lambda and S3"

# Read requirements from requirements.txt
with open("requirements.txt", "r", encoding="utf-8") as fh:
    requirements = [line.strip() for line in fh if line.strip() and not line.startswith("#")]

setup(
    name="markdown-html-converter-cdk",
    version="1.0.0",
    
    # Package metadata
    author="AWS Recipe Generator",
    author_email="developer@example.com",
    description="AWS CDK Python application for serverless Markdown to HTML conversion",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    # Project URLs
    url="https://github.com/aws-samples/markdown-html-converter",
    project_urls={
        "Bug Tracker": "https://github.com/aws-samples/markdown-html-converter/issues",
        "Documentation": "https://github.com/aws-samples/markdown-html-converter/wiki",
        "Source Code": "https://github.com/aws-samples/markdown-html-converter",
    },
    
    # Package discovery
    packages=find_packages(),
    
    # Include non-Python files
    include_package_data=True,
    
    # Dependencies
    install_requires=requirements,
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Package classifiers
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
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Utilities",
    ],
    
    # Keywords for PyPI
    keywords="aws cdk python lambda s3 markdown html converter serverless",
    
    # Entry points for command line scripts
    entry_points={
        "console_scripts": [
            "markdown-converter-deploy=app:main",
        ],
    },
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cdk>=2.0.0",
            "mypy>=1.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "isort>=5.0.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cdk>=2.0.0",
            "moto>=4.0.0",
        ],
    },
    
    # Zip safe flag
    zip_safe=False,
)