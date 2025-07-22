"""
Setup configuration for Analytics Workload Isolation CDK Python application.

This setup.py file configures the Python package for the CDK application that implements
Amazon Redshift Workload Management (WLM) for analytics workload isolation.
"""

from setuptools import setup, find_packages
import os


def read_requirements():
    """Read requirements from requirements.txt file."""
    requirements_path = os.path.join(os.path.dirname(__file__), 'requirements.txt')
    with open(requirements_path, 'r', encoding='utf-8') as f:
        requirements = []
        for line in f:
            line = line.strip()
            if line and not line.startswith('#'):
                requirements.append(line)
        return requirements


def read_long_description():
    """Read long description from README if it exists."""
    readme_path = os.path.join(os.path.dirname(__file__), 'README.md')
    if os.path.exists(readme_path):
        with open(readme_path, 'r', encoding='utf-8') as f:
            return f.read()
    return "CDK Python application for implementing analytics workload isolation with Amazon Redshift WLM"


setup(
    name="analytics-workload-isolation-redshift-wlm",
    version="1.0.0",
    description="CDK Python application for implementing analytics workload isolation with Amazon Redshift WLM",
    long_description=read_long_description(),
    long_description_content_type="text/markdown",
    author="AWS CDK Generator",
    author_email="aws-cdk@example.com",
    url="https://github.com/aws-samples/analytics-workload-isolation",
    license="MIT",
    
    # Package configuration
    packages=find_packages(exclude=["tests*"]),
    include_package_data=True,
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=read_requirements(),
    
    # Optional dependencies for development
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0", 
            "black>=23.7.0",
            "flake8>=6.0.0",
            "mypy>=1.5.0",
            "isort>=5.12.0",
            "bandit>=1.7.5",
            "safety>=2.3.0"
        ],
        "docs": [
            "sphinx>=7.1.0",
            "sphinx-rtd-theme>=1.3.0"
        ]
    },
    
    # Entry points for CLI commands
    entry_points={
        "console_scripts": [
            "redshift-wlm-deploy=app:main",
        ],
    },
    
    # Package classifiers
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
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
        "Topic :: Database",
        "Topic :: Scientific/Engineering :: Information Analysis",
        "Typing :: Typed",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "redshift", 
        "workload-management",
        "wlm",
        "analytics",
        "data-warehouse",
        "infrastructure-as-code",
        "cloud-formation",
        "multi-tenant",
        "performance-monitoring"
    ],
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/redshift/latest/mgmt/workload-mgmt.html",
        "Source": "https://github.com/aws-samples/analytics-workload-isolation",
        "Bug Reports": "https://github.com/aws-samples/analytics-workload-isolation/issues",
        "AWS CDK": "https://aws.amazon.com/cdk/",
        "Amazon Redshift": "https://aws.amazon.com/redshift/"
    },
    
    # Data files to include
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # Exclude files from package
    exclude_package_data={
        "": ["tests/*", "*.pyc", "__pycache__/*"],
    },
    
    # Zip safe configuration
    zip_safe=False,
)