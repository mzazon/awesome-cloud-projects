"""
Setup configuration for Private API Integration CDK Python application.

This setup.py file configures the Python package for the CDK application
that deploys a complete solution for secure cross-VPC API integration
using VPC Lattice Resource Configurations and EventBridge connections.
"""

from setuptools import setup, find_packages

# Read requirements from requirements.txt
with open("requirements.txt", "r", encoding="utf-8") as fh:
    requirements = [
        line.strip() 
        for line in fh 
        if line.strip() and not line.startswith("#")
    ]

# Read long description from README if it exists
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "CDK Python application for Private API Integration with VPC Lattice and EventBridge"

setup(
    name="private-api-integration-cdk",
    version="1.0.0",
    description="CDK Python application for Private API Integration with VPC Lattice and EventBridge",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS CDK Generator",
    author_email="cdk-generator@example.com",
    url="https://github.com/aws-samples/private-api-integration-lattice-eventbridge",
    
    # Package configuration
    packages=find_packages(exclude=["tests*"]),
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=requirements,
    
    # Optional dependencies for development
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
    },
    
    # Package metadata
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Networking",
        "Topic :: Internet :: WWW/HTTP :: HTTP Servers",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "vpc-lattice",
        "eventbridge",
        "step-functions",
        "api-gateway",
        "private-api",
        "microservices",
        "event-driven",
        "infrastructure-as-code",
    ],
    
    # Entry points for command-line tools (if needed)
    entry_points={
        "console_scripts": [
            "deploy-private-api=app:main",
        ],
    },
    
    # Include additional files
    include_package_data=True,
    package_data={
        "": ["*.txt", "*.md", "*.json", "*.yaml", "*.yml"],
    },
    
    # Project URLs
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws-samples/private-api-integration-lattice-eventbridge",
        "Bug Reports": "https://github.com/aws-samples/private-api-integration-lattice-eventbridge/issues",
    },
    
    # License
    license="MIT",
    
    # Zip safety
    zip_safe=False,
)