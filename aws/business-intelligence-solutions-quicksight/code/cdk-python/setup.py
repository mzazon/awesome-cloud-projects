"""
Setup configuration for QuickSight Business Intelligence CDK Python application.

This setup.py file configures the Python package for the AWS CDK application
that deploys a comprehensive business intelligence solution using Amazon QuickSight.
"""

import os
from setuptools import setup, find_packages

# Read the README file for the long description
def read_readme():
    """Read README file content for package description."""
    readme_path = os.path.join(os.path.dirname(__file__), 'README.md')
    if os.path.exists(readme_path):
        with open(readme_path, 'r', encoding='utf-8') as f:
            return f.read()
    return "AWS CDK Python application for QuickSight Business Intelligence Solutions"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements.txt file for dependencies."""
    requirements_path = os.path.join(os.path.dirname(__file__), 'requirements.txt')
    requirements = []
    
    if os.path.exists(requirements_path):
        with open(requirements_path, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                # Skip comments and empty lines
                if line and not line.startswith('#'):
                    requirements.append(line)
    
    return requirements

setup(
    name="quicksight-bi-cdk",
    version="1.0.0",
    
    description="AWS CDK Python application for QuickSight Business Intelligence Solutions",
    long_description=read_readme(),
    long_description_content_type="text/markdown",
    
    author="AWS CDK Demo",
    author_email="demo@example.com",
    
    url="https://github.com/aws-samples/quicksight-bi-cdk",
    
    packages=find_packages(exclude=["tests*"]),
    
    install_requires=read_requirements(),
    
    extras_require={
        'dev': [
            'pytest>=7.4.0',
            'pytest-cov>=4.1.0',
            'black>=23.7.0',
            'flake8>=6.0.0',
            'mypy>=1.5.0',
        ],
        'analysis': [
            'jupyter>=1.0.0',
            'matplotlib>=3.7.0',
            'seaborn>=0.12.0',
            'plotly>=5.15.0',
        ],
    },
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Utilities",
        "Operating System :: OS Independent",
    ],
    
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "quicksight",
        "business-intelligence",
        "analytics",
        "dashboard",
        "data-visualization",
        "s3",
        "rds",
        "mysql",
    ],
    
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws-samples/quicksight-bi-cdk",
        "Tracker": "https://github.com/aws-samples/quicksight-bi-cdk/issues",
        "AWS CDK": "https://aws.amazon.com/cdk/",
        "Amazon QuickSight": "https://aws.amazon.com/quicksight/",
    },
    
    entry_points={
        'console_scripts': [
            'quicksight-bi-deploy=app:main',
        ],
    },
    
    include_package_data=True,
    
    package_data={
        '': [
            '*.md',
            '*.txt',
            '*.json',
            '*.yaml',
            '*.yml',
        ],
    },
    
    zip_safe=False,
    
    # Metadata for the package
    license="Apache License 2.0",
    
    platforms=["any"],
    
    # CDK-specific metadata
    options={
        'cdk': {
            'version': '2.x',
            'language': 'python',
            'framework': 'aws-cdk-lib',
        }
    },
)