"""
Setup configuration for the Image Analysis CDK Application.

This setup.py file configures the Python package for the CDK application,
including dependencies, metadata, and development requirements.
"""

from setuptools import setup, find_packages
import os

# Read the README file for long description
def read_readme():
    """Read the README file if it exists."""
    readme_path = os.path.join(os.path.dirname(__file__), "README.md")
    if os.path.exists(readme_path):
        with open(readme_path, "r", encoding="utf-8") as f:
            return f.read()
    return "AWS CDK Application for Image Analysis with Amazon Rekognition"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file."""
    requirements_path = os.path.join(os.path.dirname(__file__), "requirements.txt")
    if os.path.exists(requirements_path):
        with open(requirements_path, "r", encoding="utf-8") as f:
            return [
                line.strip() 
                for line in f 
                if line.strip() and not line.startswith("#")
            ]
    return []

setup(
    name="image-analysis-cdk",
    version="1.0.0",
    
    description="AWS CDK Application for Image Analysis with Amazon Rekognition",
    long_description=read_readme(),
    long_description_content_type="text/markdown",
    
    author="AWS CDK Generator",
    author_email="developer@example.com",
    
    url="https://github.com/aws-samples/image-analysis-cdk",
    
    packages=find_packages(exclude=["tests*"]),
    
    python_requires=">=3.8",
    
    install_requires=read_requirements(),
    
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0", 
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
        ]
    },
    
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
        "Topic :: System :: Systems Administration",
        "Topic :: Utilities",
    ],
    
    keywords="aws cdk cloudformation infrastructure rekognition image-analysis s3",
    
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/image-analysis-cdk/issues",
        "Source": "https://github.com/aws-samples/image-analysis-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
    },
    
    entry_points={
        "console_scripts": [
            "image-analysis-cdk=app:main",
        ],
    },
)