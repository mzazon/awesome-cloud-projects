"""
Setup configuration for the Data Governance Pipeline CDK application.

This setup.py file configures the Python package for the automated data governance
solution using Amazon DataZone and AWS Config.
"""

import pathlib
from setuptools import setup, find_packages

# Read the contents of README file
HERE = pathlib.Path(__file__).parent
README = (HERE / "README.md").read_text() if (HERE / "README.md").exists() else ""

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file"""
    requirements_file = HERE / "requirements.txt"
    if requirements_file.exists():
        with open(requirements_file, 'r') as f:
            requirements = []
            for line in f:
                line = line.strip()
                if line and not line.startswith('#'):
                    # Remove version constraints for core dependencies
                    if line.startswith('aws-cdk-lib'):
                        requirements.append('aws-cdk-lib>=2.100.0')
                    elif line.startswith('constructs'):
                        requirements.append('constructs>=10.3.0')
                    elif not line.startswith(('pytest', 'black', 'mypy', 'flake8', 'isort')):
                        requirements.append(line)
            return requirements
    return []

setup(
    name="data-governance-pipeline-cdk",
    version="1.0.0",
    description="AWS CDK Python application for automated data governance pipelines",
    long_description=README,
    long_description_content_type="text/markdown",
    author="Data Governance Team",
    author_email="datagovernance@example.com",
    url="https://github.com/your-organization/data-governance-pipeline-cdk",
    license="MIT",
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Package discovery
    packages=find_packages(exclude=["tests", "tests.*"]),
    
    # Dependencies
    install_requires=read_requirements(),
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.7.0",
            "mypy>=1.5.0",
            "flake8>=6.0.0",
            "isort>=5.12.0",
        ]
    },
    
    # Package classification
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP",
        "Topic :: Database",
        "Topic :: Security",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "datazone",
        "config",
        "governance",
        "compliance",
        "automation",
        "data-management",
        "eventbridge",
        "lambda",
        "infrastructure-as-code"
    ],
    
    # Entry points for command-line scripts
    entry_points={
        "console_scripts": [
            "deploy-governance=app:main",
        ],
    },
    
    # Include additional files
    include_package_data=True,
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/your-organization/data-governance-pipeline-cdk/issues",
        "Source": "https://github.com/your-organization/data-governance-pipeline-cdk",
        "Documentation": "https://github.com/your-organization/data-governance-pipeline-cdk/wiki",
    },
    
    # Zip safety
    zip_safe=False,
)