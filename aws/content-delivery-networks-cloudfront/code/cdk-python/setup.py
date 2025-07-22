"""
Setup configuration for AWS CDK Python CloudFront CDN Application

This setup.py file configures the Python package for the advanced CloudFront
CDN application built with AWS CDK. It defines package metadata, dependencies,
and entry points for the CDK application.
"""

import setuptools

# Read the README file for long description
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "Advanced CloudFront CDN built with AWS CDK Python"

# Read requirements from requirements.txt
with open("requirements.txt", "r", encoding="utf-8") as fh:
    requirements = [line.strip() for line in fh if line.strip() and not line.startswith("#")]

setuptools.setup(
    name="cloudfront-advanced-cdn",
    version="1.0.0",
    
    # Author and contact information
    author="AWS CDK Developer",
    author_email="developer@example.com",
    
    # Package description
    description="Advanced CloudFront CDN with Lambda@Edge, WAF, and monitoring",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    # Package URL and source
    url="https://github.com/example/cloudfront-advanced-cdn",
    
    # Package discovery and structure
    packages=setuptools.find_packages(),
    
    # Dependencies
    install_requires=requirements,
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Package classifiers for PyPI
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: Internet :: WWW/HTTP",
        "Topic :: System :: Networking",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws", "cdk", "cloudfront", "cdn", "content-delivery-network",
        "lambda-edge", "waf", "security", "monitoring", "infrastructure"
    ],
    
    # Entry points for console scripts
    entry_points={
        "console_scripts": [
            "deploy-cdn=app:main",
        ],
    },
    
    # Additional package data
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # Include additional files in the package
    include_package_data=True,
    
    # Zip safe setting
    zip_safe=False,
    
    # Development dependencies (extras_require)
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "boto3-stubs[essential]>=1.26.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
            "sphinx-autodoc-typehints>=1.19.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",
            "responses>=0.22.0",
        ],
    },
    
    # Project URLs for PyPI
    project_urls={
        "Bug Reports": "https://github.com/example/cloudfront-advanced-cdn/issues",
        "Source": "https://github.com/example/cloudfront-advanced-cdn",
        "Documentation": "https://cloudfront-advanced-cdn.readthedocs.io/",
        "Funding": "https://github.com/sponsors/example",
    },
    
    # Package configuration options
    options={
        "bdist_wheel": {
            "universal": False,
        },
    },
)