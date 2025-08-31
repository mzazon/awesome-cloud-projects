"""
Setup configuration for Simple Log Analysis CDK Python Application

This setup.py file configures the Python package for the Simple Log Analysis
CDK application, including dependencies, metadata, and development requirements.
"""

import setuptools
from pathlib import Path

# Read the README file for long description
this_directory = Path(__file__).parent
long_description = (this_directory / "README.md").read_text() if (this_directory / "README.md").exists() else ""

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file"""
    requirements_file = this_directory / "requirements.txt"
    if requirements_file.exists():
        with open(requirements_file, 'r') as f:
            requirements = []
            for line in f:
                line = line.strip()
                # Skip comments and empty lines
                if line and not line.startswith('#'):
                    # Handle version constraints and comments
                    requirement = line.split('#')[0].strip()
                    if requirement:
                        requirements.append(requirement)
            return requirements
    return []

setuptools.setup(
    name="simple-log-analysis-cdk",
    version="1.0.0",
    
    description="Simple Log Analysis with CloudWatch Insights and SNS - CDK Python Application",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS CDK Developer",
    author_email="developer@example.com",
    
    package_dir={"": "."},
    packages=setuptools.find_packages(where="."),
    
    install_requires=read_requirements(),
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Monitoring",
        "Topic :: System :: Logging",
    ],
    
    keywords="aws cdk cloudwatch logs insights sns monitoring alerting serverless",
    
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
        "Tracker": "https://github.com/aws/aws-cdk/issues",
    },
    
    # Entry point for the CDK application
    entry_points={
        "console_scripts": [
            "simple-log-analysis-cdk=app:main",
        ],
    },
    
    # Additional metadata
    zip_safe=False,
    include_package_data=True,
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "mypy>=1.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "boto3-stubs[essential]>=1.34.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",  # For mocking AWS services in tests
        ],
    },
)