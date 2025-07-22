#!/usr/bin/env python3
"""
Setup configuration for the ML Pipeline CDK Python application.

This setup.py file configures the Python package for the CDK application,
including dependencies, metadata, and development requirements.
"""

from setuptools import setup, find_packages
import os

# Read the README file for the long description
def read_readme():
    """Read the README file for the long description."""
    readme_path = os.path.join(os.path.dirname(__file__), 'README.md')
    if os.path.exists(readme_path):
        with open(readme_path, 'r', encoding='utf-8') as f:
            return f.read()
    return "ML Pipeline CDK Python Application"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file."""
    requirements_path = os.path.join(os.path.dirname(__file__), 'requirements.txt')
    requirements = []
    if os.path.exists(requirements_path):
        with open(requirements_path, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#'):
                    requirements.append(line)
    return requirements

setup(
    name="ml-pipeline-cdk",
    version="1.0.0",
    author="AWS CDK Developer",
    author_email="developer@example.com",
    description="CDK Python application for ML Pipeline with SageMaker and Step Functions",
    long_description=read_readme(),
    long_description_content_type="text/markdown",
    url="https://github.com/example/ml-pipeline-cdk",
    
    # Package configuration
    packages=find_packages(exclude=["tests*"]),
    include_package_data=True,
    zip_safe=False,
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=read_requirements(),
    
    # Development dependencies
    extras_require={
        'dev': [
            'pytest>=7.0.0',
            'pytest-cov>=4.0.0',
            'black>=22.0.0',
            'flake8>=5.0.0',
            'mypy>=1.0.0',
            'bandit>=1.7.0',
            'safety>=2.0.0',
        ],
        'docs': [
            'sphinx>=5.0.0',
            'sphinx-rtd-theme>=1.0.0',
        ],
    },
    
    # Entry points
    entry_points={
        'console_scripts': [
            'ml-pipeline-cdk=app:main',
        ],
    },
    
    # Package metadata
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
        "Topic :: Scientific/Engineering :: Artificial Intelligence",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "sagemaker",
        "step-functions",
        "machine-learning",
        "mlops",
        "pipeline",
        "automation",
    ],
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/example/ml-pipeline-cdk/issues",
        "Source": "https://github.com/example/ml-pipeline-cdk",
        "Documentation": "https://github.com/example/ml-pipeline-cdk/docs",
    },
    
    # License
    license="MIT",
    
    # Additional metadata
    platforms=["any"],
    
    # Test configuration
    test_suite="tests",
    tests_require=[
        'pytest>=7.0.0',
        'pytest-cov>=4.0.0',
        'moto>=4.0.0',  # For mocking AWS services in tests
    ],
)