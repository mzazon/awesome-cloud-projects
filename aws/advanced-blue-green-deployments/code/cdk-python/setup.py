"""
Setup configuration for Advanced Blue-Green Deployments CDK Python application.

This setup.py file configures the Python package for the CDK application,
including dependencies, metadata, and entry points.
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
            # Skip comments and empty lines
            if line and not line.startswith('#'):
                # Extract package name (ignore version constraints for setup.py)
                package = line.split('>=')[0].split('==')[0].split('<')[0]
                requirements.append(package)
        return requirements


def read_long_description():
    """Read long description from README if it exists."""
    readme_path = os.path.join(os.path.dirname(__file__), 'README.md')
    if os.path.exists(readme_path):
        with open(readme_path, 'r', encoding='utf-8') as f:
            return f.read()
    return "Advanced Blue-Green Deployments with ECS, Lambda, and CodeDeploy using AWS CDK Python"


setup(
    name="advanced-blue-green-deployments-cdk",
    version="1.0.0",
    description="Advanced Blue-Green Deployments with ECS, Lambda, and CodeDeploy using AWS CDK Python",
    long_description=read_long_description(),
    long_description_content_type="text/markdown",
    
    # Author information
    author="AWS Solutions Architecture Team",
    author_email="aws-solutions@amazon.com",
    
    # Project URLs
    url="https://github.com/aws-samples/advanced-blue-green-deployments",
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws-samples/advanced-blue-green-deployments",
        "Tracker": "https://github.com/aws-samples/advanced-blue-green-deployments/issues",
    },
    
    # Package configuration
    packages=find_packages(exclude=["tests", "tests.*"]),
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
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.5.0",
            "pre-commit>=3.4.0",
            "tox>=4.11.0",
        ],
        "docs": [
            "sphinx>=7.1.0",
            "sphinx-rtd-theme>=1.3.0",
        ],
        "security": [
            "bandit>=1.7.5",
            "safety>=2.3.0",
        ],
    },
    
    # Entry points
    entry_points={
        "console_scripts": [
            "deploy-blue-green=app:main",
        ],
    },
    
    # Package classifiers
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: OS Independent",
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
        "Framework :: AWS CDK",
        "Framework :: AWS CDK :: 2",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "blue-green",
        "deployment",
        "ecs",
        "lambda",
        "codedeploy",
        "devops",
        "ci-cd",
        "containers",
        "serverless",
        "automation",
        "monitoring",
        "rollback",
    ],
    
    # License
    license="Apache-2.0",
    
    # Package data
    package_data={
        "": ["*.md", "*.txt", "*.yml", "*.yaml", "*.json"],
    },
    
    # Zip safe configuration
    zip_safe=False,
    
    # Additional metadata
    platforms=["any"],
    
    # Test suite configuration
    test_suite="tests",
    tests_require=[
        "pytest>=7.4.0",
        "pytest-cov>=4.1.0",
        "moto>=4.2.0",  # For mocking AWS services in tests
    ],
)