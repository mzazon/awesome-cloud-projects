"""
Setup configuration for DNS-Based Load Balancing with Route 53 CDK Python application.

This setup.py file configures the Python package for the CDK application
that implements comprehensive DNS-based load balancing using Amazon Route 53.
"""

import setuptools
from pathlib import Path

# Read the README file for long description
readme_path = Path(__file__).parent / "README.md"
try:
    with open(readme_path, "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "DNS-Based Load Balancing with Route 53 CDK Python Application"

# Read requirements from requirements.txt
requirements_path = Path(__file__).parent / "requirements.txt"
try:
    with open(requirements_path, "r", encoding="utf-8") as fh:
        requirements = [
            line.strip() 
            for line in fh.readlines() 
            if line.strip() and not line.startswith('#') and not line.startswith('-')
        ]
except FileNotFoundError:
    requirements = [
        "aws-cdk-lib>=2.120.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "typing-extensions>=4.0.0",
    ]

setuptools.setup(
    name="dns-load-balancing-route53",
    version="1.0.0",
    
    author="AWS Recipe Generator",
    author_email="support@example.com",
    
    description="DNS-Based Load Balancing with Route 53 using AWS CDK Python",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    url="https://github.com/aws-samples/dns-load-balancing-route53",
    
    project_urls={
        "Bug Tracker": "https://github.com/aws-samples/dns-load-balancing-route53/issues",
        "Documentation": "https://docs.aws.amazon.com/route53/",
        "Source Code": "https://github.com/aws-samples/dns-load-balancing-route53",
    },
    
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Networking",
        "Topic :: Internet :: Name Service (DNS)",
    ],
    
    packages=setuptools.find_packages(),
    
    python_requires=">=3.8",
    
    install_requires=requirements,
    
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "isort>=5.0.0",
        ],
        "docs": [
            "sphinx>=4.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
    },
    
    entry_points={
        "console_scripts": [
            "dns-load-balancing=app:main",
        ],
    },
    
    keywords=[
        "aws",
        "cdk",
        "route53",
        "dns",
        "load-balancing",
        "failover",
        "health-checks",
        "multi-region",
        "infrastructure",
        "cloud",
    ],
    
    include_package_data=True,
    
    zip_safe=False,
    
    # Additional metadata
    license="MIT",
    
    # Package data to include
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
)