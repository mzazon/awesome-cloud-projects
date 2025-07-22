"""
Setup configuration for AWS CDK Python Serverless Web Application

This setup.py file configures the Python package for the serverless web application
CDK deployment. It includes all necessary dependencies and metadata for proper
package installation and development workflows.
"""

from setuptools import setup, find_packages
import os


def read_requirements():
    """Read requirements from requirements.txt file"""
    requirements_path = os.path.join(os.path.dirname(__file__), 'requirements.txt')
    with open(requirements_path, 'r', encoding='utf-8') as f:
        requirements = []
        for line in f:
            line = line.strip()
            # Skip comments and empty lines
            if line and not line.startswith('#'):
                # Remove inline comments
                if '#' in line:
                    line = line.split('#')[0].strip()
                requirements.append(line)
    return requirements


def read_long_description():
    """Read long description from README file if it exists"""
    readme_path = os.path.join(os.path.dirname(__file__), 'README.md')
    if os.path.exists(readme_path):
        with open(readme_path, 'r', encoding='utf-8') as f:
            return f.read()
    return """
    AWS CDK Python application for deploying serverless web applications
    using AWS Amplify for frontend hosting and Lambda functions for backend APIs.
    """


# Package metadata
PACKAGE_NAME = "serverless-web-app-cdk"
VERSION = "1.0.0"
AUTHOR = "AWS CDK Developer"
AUTHOR_EMAIL = "developer@example.com"
DESCRIPTION = "CDK Python app for serverless web applications with Amplify and Lambda"
URL = "https://github.com/your-org/serverless-web-app-cdk"

# Python version requirements
PYTHON_REQUIRES = ">=3.8"

# Package classifiers for PyPI
CLASSIFIERS = [
    "Development Status :: 5 - Production/Stable",
    "Intended Audience :: Developers",
    "License :: OSI Approved :: MIT License",
    "Programming Language :: Python :: 3",
    "Programming Language :: Python :: 3.8",
    "Programming Language :: Python :: 3.9",
    "Programming Language :: Python :: 3.10",
    "Programming Language :: Python :: 3.11",
    "Topic :: Software Development :: Libraries :: Python Modules",
    "Topic :: System :: Systems Administration",
    "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
    "Topic :: Internet :: WWW/HTTP :: HTTP Servers",
]

# Keywords for package discovery
KEYWORDS = [
    "aws",
    "cdk",
    "serverless",
    "lambda",
    "amplify",
    "dynamodb",
    "api-gateway",
    "cognito",
    "infrastructure",
    "cloud",
    "web-application",
    "typescript",
    "react"
]

setup(
    # Basic package information
    name=PACKAGE_NAME,
    version=VERSION,
    author=AUTHOR,
    author_email=AUTHOR_EMAIL,
    description=DESCRIPTION,
    long_description=read_long_description(),
    long_description_content_type="text/markdown",
    url=URL,
    
    # Package discovery and structure
    packages=find_packages(exclude=["tests*", "docs*"]),
    include_package_data=True,
    
    # Python version requirements
    python_requires=PYTHON_REQUIRES,
    
    # Dependencies
    install_requires=read_requirements(),
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "bandit>=1.7.0",
            "safety>=2.0.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.2.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "httpx>=0.24.0",
            "moto>=4.0.0",  # For mocking AWS services
        ]
    },
    
    # Package classification
    classifiers=CLASSIFIERS,
    keywords=" ".join(KEYWORDS),
    
    # Entry points for CLI commands
    entry_points={
        "console_scripts": [
            "deploy-serverless-app=app:main",
        ]
    },
    
    # Package data and files
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # Project URLs for PyPI
    project_urls={
        "Bug Reports": f"{URL}/issues",
        "Source": URL,
        "Documentation": f"{URL}#readme",
        "Funding": "https://github.com/sponsors/your-username",
    },
    
    # License information
    license="MIT",
    
    # Zip safe configuration
    zip_safe=False,
    
    # Platform compatibility
    platforms=["any"],
    
    # Additional metadata for modern Python packaging
    options={
        "build_scripts": {
            "executable": "/usr/bin/env python3",
        },
    },
)


# Additional setup for CDK-specific requirements
if __name__ == "__main__":
    print("Setting up AWS CDK Python Serverless Web Application...")
    print(f"Package: {PACKAGE_NAME} v{VERSION}")
    print(f"Python requirement: {PYTHON_REQUIRES}")
    print("Dependencies will be installed from requirements.txt")
    print("")
    print("After installation, you can deploy the application using:")
    print("  cdk bootstrap  # First time only")
    print("  cdk deploy     # Deploy the stack")
    print("")
    print("For development:")
    print("  pip install -e .[dev]  # Install with development dependencies")
    print("  pytest                 # Run tests")
    print("  black .               # Format code")
    print("  flake8 .              # Lint code")
    print("  mypy .                # Type checking")
    print("")
    print("For more information, see the README.md file.")