"""
Setup configuration for CloudFront Real-time Monitoring and Analytics CDK Application

This setup.py file configures the Python package for the CDK application that
implements real-time monitoring and analytics for CloudFront distributions.

Author: CDK Recipe Generator
Version: 1.0
"""

from setuptools import setup, find_packages
import os

# Read the README file for long description
def read_readme():
    """Read README.md file if it exists"""
    readme_path = os.path.join(os.path.dirname(__file__), "README.md")
    if os.path.exists(readme_path):
        with open(readme_path, "r", encoding="utf-8") as f:
            return f.read()
    return "CloudFront Real-time Monitoring and Analytics CDK Application"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements.txt file and return list of dependencies"""
    requirements_path = os.path.join(os.path.dirname(__file__), "requirements.txt")
    requirements = []
    if os.path.exists(requirements_path):
        with open(requirements_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                # Skip comments and empty lines
                if line and not line.startswith("#"):
                    requirements.append(line)
    return requirements

setup(
    name="cloudfront-realtime-monitoring",
    version="1.0.0",
    description="AWS CDK application for CloudFront real-time monitoring and analytics",
    long_description=read_readme(),
    long_description_content_type="text/markdown",
    author="CDK Recipe Generator",
    author_email="recipes@aws.example.com",
    url="https://github.com/aws-samples/cloudfront-realtime-monitoring",
    
    # Package configuration
    packages=find_packages(),
    include_package_data=True,
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=read_requirements(),
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "mypy>=1.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "pre-commit>=3.0.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",
            "boto3-stubs[essential]>=1.34.0",
        ],
    },
    
    # Entry points for command line scripts
    entry_points={
        "console_scripts": [
            "cloudfront-monitoring=app:main",
        ],
    },
    
    # Package classifiers
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Monitoring",
        "Topic :: System :: Networking :: Monitoring",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
        "Typing :: Typed",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "cloudfront",
        "monitoring",
        "analytics",
        "real-time",
        "kinesis",
        "lambda",
        "opensearch",
        "cloudwatch",
        "infrastructure",
        "devops",
    ],
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws-samples/cloudfront-realtime-monitoring",
        "Tracker": "https://github.com/aws-samples/cloudfront-realtime-monitoring/issues",
        "AWS CDK": "https://aws.amazon.com/cdk/",
        "CloudFront": "https://aws.amazon.com/cloudfront/",
    },
    
    # Package data
    package_data={
        "": ["*.md", "*.txt", "*.yml", "*.yaml", "*.json"],
    },
    
    # Zip safe
    zip_safe=False,
    
    # License
    license="MIT",
    
    # Platforms
    platforms=["any"],
)