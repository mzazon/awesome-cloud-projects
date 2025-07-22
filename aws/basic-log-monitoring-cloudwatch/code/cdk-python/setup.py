"""
Setup configuration for AWS CDK Python Log Monitoring Application

This setup.py file configures the Python package for the basic log monitoring
solution using AWS CDK. It includes all necessary dependencies and metadata
for the application.
"""

import setuptools
from pathlib import Path

# Read the README file for long description
this_directory = Path(__file__).parent
long_description = (this_directory / "README.md").read_text() if (this_directory / "README.md").exists() else ""

# Read requirements from requirements.txt
def parse_requirements(filename):
    """Parse requirements from requirements.txt file"""
    requirements = []
    with open(filename, 'r') as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#'):
                # Remove comments from the end of lines
                line = line.split('#')[0].strip()
                if line:
                    requirements.append(line)
    return requirements

setuptools.setup(
    name="log-monitoring-cdk",
    version="1.0.0",
    
    description="AWS CDK Python application for basic log monitoring with CloudWatch and SNS",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS CDK Generator",
    author_email="admin@example.com",
    
    # Package information
    packages=setuptools.find_packages(),
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=parse_requirements("requirements.txt"),
    
    # Entry points for command line scripts
    entry_points={
        'console_scripts': [
            'log-monitoring-deploy=app:main',
        ],
    },
    
    # Package classification
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Monitoring",
        "Topic :: System :: Logging",
    ],
    
    # Keywords for package discovery
    keywords="aws cdk cloudwatch sns logging monitoring alerts",
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Source": "https://github.com/aws/aws-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
    },
    
    # Package data to include
    include_package_data=True,
    
    # Additional metadata
    license="Apache License 2.0",
    platforms=["any"],
    
    # Optional dependencies for development
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "pytest-cov>=4.0.0",
        ],
        "docs": [
            "mkdocs>=1.4.0",
            "mkdocs-material>=8.5.0",
        ],
    },
)