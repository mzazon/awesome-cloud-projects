"""
Setup configuration for AWS WAF Rate Limiting CDK Python application.

This setup.py file configures the Python package for the AWS CDK application
that deploys Web Application Firewall with rate limiting rules and comprehensive
security monitoring capabilities.
"""

import setuptools
from pathlib import Path

# Read the long description from README if it exists
try:
    long_description = Path("README.md").read_text(encoding="utf-8")
except FileNotFoundError:
    long_description = "AWS CDK Python application for deploying WAF with rate limiting rules"

# Read requirements from requirements.txt
def read_requirements():
    """Read and parse requirements from requirements.txt file."""
    requirements_file = Path("requirements.txt")
    if requirements_file.exists():
        with open(requirements_file, 'r', encoding='utf-8') as f:
            requirements = []
            for line in f:
                line = line.strip()
                # Skip empty lines and comments
                if line and not line.startswith('#'):
                    # Remove inline comments
                    requirement = line.split('#')[0].strip()
                    if requirement:
                        requirements.append(requirement)
            return requirements
    return [
        "aws-cdk-lib>=2.100.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
    ]

setuptools.setup(
    name="waf-rate-limiting-cdk",
    version="1.0.0",
    description="AWS CDK Python application for WAF with rate limiting rules",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS Solutions Architect",
    author_email="solutions@example.com",
    url="https://github.com/aws-samples/waf-rate-limiting-cdk",
    
    # Package classification
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Security",
        "Operating System :: OS Independent",
    ],
    
    # Python version requirements
    python_requires=">=3.8",
    
    # Package dependencies
    install_requires=read_requirements(),
    
    # Development dependencies
    extras_require={
        "dev": [
            "mypy>=1.0.0",
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=6.0.0",
            "isort>=5.10.0",
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
            "boto3>=1.26.0",
            "moto>=4.0.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",
            "boto3>=1.26.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
    },
    
    # Package discovery
    packages=setuptools.find_packages(exclude=["tests", "tests.*"]),
    
    # Include additional files
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # Entry points for command-line scripts
    entry_points={
        "console_scripts": [
            "deploy-waf=app:main",
        ],
    },
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/waf-rate-limiting-cdk/issues",
        "Source": "https://github.com/aws-samples/waf-rate-limiting-cdk",
        "Documentation": "https://github.com/aws-samples/waf-rate-limiting-cdk#readme",
    },
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "waf",
        "security",
        "rate-limiting",
        "ddos-protection",
        "web-application-firewall",
        "cloudfront",
        "infrastructure-as-code",
        "python",
    ],
    
    # License information
    license="MIT",
    
    # Zip safe configuration
    zip_safe=False,
)