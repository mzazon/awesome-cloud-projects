"""
Setup configuration for Carbon Footprint Optimization CDK Application

This setup.py file configures the Python package for the automated carbon footprint
optimization system built with AWS CDK. It defines package metadata, dependencies,
and installation requirements.
"""

import setuptools
from pathlib import Path

# Read the contents of README file for long description
this_directory = Path(__file__).parent
long_description = "AWS CDK application for automated carbon footprint optimization"

# Read requirements from requirements.txt
def parse_requirements(filename):
    """Parse requirements from requirements.txt file"""
    requirements = []
    with open(filename, 'r') as f:
        for line in f:
            line = line.strip()
            # Skip empty lines and comments
            if line and not line.startswith('#'):
                # Remove inline comments
                req = line.split('#')[0].strip()
                if req:
                    requirements.append(req)
    return requirements

setuptools.setup(
    name="carbon-footprint-optimization-cdk",
    version="1.0.0",
    
    description="AWS CDK application for automated carbon footprint optimization",
    long_description=long_description,
    long_description_content_type="text/plain",
    
    author="AWS CDK Team",
    author_email="support@example.com",
    
    url="https://github.com/aws-samples/carbon-footprint-optimization",
    
    package_dir={"": "."},
    packages=setuptools.find_packages(where="."),
    
    install_requires=parse_requirements("requirements.txt"),
    
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
        "Topic :: Software Development :: Libraries :: Application Frameworks",
        "Topic :: System :: Systems Administration",
        "Topic :: Utilities",
    ],
    
    keywords=[
        "aws",
        "cdk",
        "carbon-footprint",
        "sustainability",
        "cost-optimization",
        "environmental",
        "serverless",
        "automation"
    ],
    
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws-samples/carbon-footprint-optimization",
        "Tracker": "https://github.com/aws-samples/carbon-footprint-optimization/issues",
    },
    
    # Entry points for command line scripts
    entry_points={
        "console_scripts": [
            "carbon-optimizer=app:main",
        ],
    },
    
    # Include additional files in the package
    include_package_data=True,
    
    # Package configuration
    zip_safe=False,
    
    # Development dependencies (optional)
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.12.0",
            "flake8>=6.1.0",
            "mypy>=1.8.0",
        ],
        "docs": [
            "sphinx>=7.1.0",
            "sphinx-rtd-theme>=1.3.0",
        ],
    },
)