"""
Setup configuration for Document Analysis with Amazon Textract CDK application.

This setup.py file configures the Python package for the CDK application,
including dependencies, metadata, and entry points.
"""

import setuptools
from pathlib import Path

# Read the contents of README file
this_directory = Path(__file__).parent
long_description = (this_directory / "README.md").read_text() if (this_directory / "README.md").exists() else ""

# Read requirements from requirements.txt
requirements = []
requirements_path = this_directory / "requirements.txt"
if requirements_path.exists():
    with open(requirements_path) as f:
        requirements = [line.strip() for line in f if line.strip() and not line.startswith('#')]

setuptools.setup(
    name="document-analysis-textract-cdk",
    version="1.0.0",
    
    description="CDK Python application for Document Analysis with Amazon Textract",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS CDK Generator",
    author_email="developer@example.com",
    
    package_dir={"": "."},
    packages=setuptools.find_packages(where="."),
    
    install_requires=requirements,
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: JavaScript",
        "Programming Language :: Python :: 3 :: Only",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Code Generators",
        "Topic :: Utilities",
        "Typing :: Typed",
    ],
    
    entry_points={
        'console_scripts': [
            'deploy=app:main',
        ],
    },
    
    keywords="aws cdk textract document-analysis serverless",
    
    project_urls={
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Source": "https://github.com/aws/aws-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
    },
    
    zip_safe=False,
    
    # Additional metadata
    platforms=["any"],
    
    # Optional dependencies for development
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=4.0.0",
            "mypy>=0.900",
        ],
        "docs": [
            "sphinx>=4.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
    },
)