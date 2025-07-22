"""
Setup configuration for CDK Python Predictive Scaling application.

This setup.py file configures the Python package for the predictive scaling
EC2 Auto Scaling recipe implementation using AWS CDK.
"""

import setuptools
from pathlib import Path

# Read the README file for long description
this_directory = Path(__file__).parent
long_description = (this_directory / "../README.md").read_text() if (this_directory / "../README.md").exists() else "CDK Python application for implementing predictive scaling with EC2 Auto Scaling and Machine Learning"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file."""
    requirements_file = this_directory / "requirements.txt"
    if requirements_file.exists():
        with open(requirements_file, 'r') as f:
            requirements = []
            for line in f:
                line = line.strip()
                # Skip comments and empty lines
                if line and not line.startswith('#'):
                    # Remove inline comments
                    requirement = line.split('#')[0].strip()
                    if requirement:
                        requirements.append(requirement)
            return requirements
    return []

setuptools.setup(
    name="predictive-scaling-ec2-autoscaling-ml",
    version="1.0.0",
    description="CDK Python application for implementing predictive scaling with EC2 Auto Scaling and Machine Learning",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS CDK Generator",
    author_email="aws-cdk@example.com",
    
    # Package information
    python_requires=">=3.8",
    packages=setuptools.find_packages(),
    
    # Dependencies
    install_requires=read_requirements(),
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "bandit>=1.7.0",
            "safety>=2.0.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
    },
    
    # Project metadata
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP",
        "Typing :: Typed",
    ],
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws/aws-cdk",
    },
    
    # Entry points
    entry_points={
        "console_scripts": [
            "predictive-scaling-app=app:main",
        ],
    },
    
    # Include additional files
    include_package_data=True,
    package_data={
        "": ["*.txt", "*.md", "*.json", "*.yaml", "*.yml"],
    },
    
    # Keywords for PyPI
    keywords="aws cdk predictive scaling autoscaling ec2 machine learning cloudformation infrastructure",
    
    # License
    license="Apache-2.0",
    
    # Platform compatibility
    platforms=["any"],
    
    # Zip safety
    zip_safe=False,
)