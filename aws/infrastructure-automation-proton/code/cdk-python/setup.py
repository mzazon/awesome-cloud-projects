"""
Setup configuration for AWS CDK Python Infrastructure Automation application.

This setup.py file configures the Python package for the AWS Proton and CDK
infrastructure automation solution. It includes all necessary dependencies
and metadata for proper package management.
"""

import setuptools
from pathlib import Path

# Read the long description from README if it exists
readme_path = Path(__file__).parent / "README.md"
long_description = ""
if readme_path.exists():
    with open(readme_path, "r", encoding="utf-8") as fh:
        long_description = fh.read()

# Read requirements from requirements.txt
requirements_path = Path(__file__).parent / "requirements.txt"
install_requires = []
if requirements_path.exists():
    with open(requirements_path, "r", encoding="utf-8") as fh:
        install_requires = [
            line.strip() 
            for line in fh.readlines() 
            if line.strip() and not line.startswith('#')
        ]

setuptools.setup(
    name="aws-proton-cdk-automation",
    version="1.0.0",
    
    author="CDK Python Recipe Generator",
    author_email="support@example.com",
    
    description="AWS CDK Python application for Infrastructure Automation with AWS Proton",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    url="https://github.com/example/aws-proton-cdk-automation",
    
    project_urls={
        "Bug Tracker": "https://github.com/example/aws-proton-cdk-automation/issues",
        "Documentation": "https://github.com/example/aws-proton-cdk-automation#readme",
        "Source Code": "https://github.com/example/aws-proton-cdk-automation",
    },
    
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
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
        "Topic :: Software Development :: Code Generators",
    ],
    
    packages=setuptools.find_packages(),
    
    python_requires=">=3.8",
    
    install_requires=install_requires,
    
    extras_require={
        "dev": [
            "pytest>=7.1.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=0.991",
            "bandit>=1.7.0",
            "safety>=2.0.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
    },
    
    entry_points={
        "console_scripts": [
            "proton-cdk-deploy=app:main",
        ],
    },
    
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    include_package_data=True,
    
    zip_safe=False,
    
    keywords=[
        "aws",
        "cdk",
        "proton", 
        "infrastructure",
        "automation",
        "devops",
        "cloud",
        "iac",
        "infrastructure-as-code",
        "fargate",
        "ecs",
        "load-balancer",
        "vpc",
        "templates",
        "self-service",
        "standardization"
    ],
    
    # Metadata for pip and other tools
    license="MIT",
    platforms=["any"],
    
    # Additional metadata
    maintainer="Platform Engineering Team",
    maintainer_email="platform@example.com",
    
    # CDK specific metadata
    cdk_version=">=2.100.0,<3.0.0",
    
    # Python version compatibility
    python_requires_max="<4.0",
)