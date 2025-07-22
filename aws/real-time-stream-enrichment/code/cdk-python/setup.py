"""
Setup configuration for Stream Enrichment Pipeline CDK Python application.

This setup.py file configures the Python package for the real-time stream
enrichment pipeline using AWS CDK Python constructs.
"""

import setuptools
from pathlib import Path

# Read README file for long description
readme_path = Path(__file__).parent / "README.md"
long_description = readme_path.read_text(encoding="utf-8") if readme_path.exists() else ""

# Read requirements from requirements.txt
requirements_path = Path(__file__).parent / "requirements.txt"
install_requires = []
if requirements_path.exists():
    with open(requirements_path, 'r', encoding='utf-8') as f:
        install_requires = [
            line.strip() 
            for line in f 
            if line.strip() and not line.startswith('#')
        ]

setuptools.setup(
    name="stream-enrichment-pipeline",
    version="1.0.0",
    
    description="Real-time stream enrichment pipeline using AWS CDK Python",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS Recipe Generator",
    author_email="recipes@aws.com",
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: JavaScript",
        "Programming Language :: Python :: 3 :: Only",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Typing :: Typed",
    ],
    
    install_requires=install_requires,
    
    packages=setuptools.find_packages(),
    
    package_data={
        "": ["*.md", "*.txt", "*.yaml", "*.yml", "*.json"],
    },
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.5.0",
            "pre-commit>=3.3.0",
        ],
        "docs": [
            "sphinx>=7.0.0",
            "sphinx-rtd-theme>=1.3.0",
            "sphinx-autodoc-typehints>=1.24.0",
        ],
    },
    
    # Entry points for CLI tools (if needed)
    entry_points={
        "console_scripts": [
            "deploy-stream-enrichment=app:main",
        ],
    },
    
    # Project URLs
    project_urls={
        "Source": "https://github.com/aws-samples/stream-enrichment-pipeline",
        "Documentation": "https://aws.amazon.com/kinesis/",
        "Bug Reports": "https://github.com/aws-samples/stream-enrichment-pipeline/issues",
    },
    
    # Keywords for discoverability
    keywords=[
        "aws",
        "cdk",
        "kinesis",
        "eventbridge",
        "lambda",
        "s3",
        "dynamodb",
        "streaming",
        "real-time",
        "data-enrichment",
        "serverless",
        "analytics",
        "firehose",
        "pipes",
    ],
    
    # License
    license="Apache-2.0",
    
    # Platform compatibility
    platforms=["any"],
    
    # Include package data
    include_package_data=True,
    
    # Zip safety
    zip_safe=False,
)