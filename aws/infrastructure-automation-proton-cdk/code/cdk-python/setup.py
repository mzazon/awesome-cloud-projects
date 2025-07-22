"""
Setup configuration for AWS CDK Python application
Infrastructure Automation with AWS Proton and CDK
"""

import os
from setuptools import setup, find_packages

# Read README for long description
def read_readme():
    """Read README.md for long description."""
    readme_path = os.path.join(os.path.dirname(__file__), 'README.md')
    if os.path.exists(readme_path):
        with open(readme_path, 'r', encoding='utf-8') as f:
            return f.read()
    return "AWS CDK Python application for Infrastructure Automation with AWS Proton"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt."""
    requirements_path = os.path.join(os.path.dirname(__file__), 'requirements.txt')
    requirements = []
    if os.path.exists(requirements_path):
        with open(requirements_path, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#'):
                    requirements.append(line)
    return requirements

setup(
    name="proton-infrastructure-automation-cdk",
    version="1.0.0",
    description="AWS CDK Python application for Infrastructure Automation with AWS Proton",
    long_description=read_readme(),
    long_description_content_type="text/markdown",
    author="Cloud Platform Team",
    author_email="platform-team@example.com",
    url="https://github.com/your-org/proton-infrastructure-automation",
    
    # Package configuration
    packages=find_packages(exclude=["tests", "tests.*"]),
    include_package_data=True,
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=read_requirements(),
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "isort>=5.12.0",
            "mypy>=1.5.0",
            "bandit>=1.7.0",
        ]
    },
    
    # Entry points
    entry_points={
        "console_scripts": [
            "deploy-proton-infrastructure=app:main",
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
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
    ],
    
    # Keywords for package discovery
    keywords="aws cdk proton infrastructure automation devops platform",
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/your-org/proton-infrastructure-automation/issues",
        "Source": "https://github.com/your-org/proton-infrastructure-automation",
        "Documentation": "https://docs.aws.amazon.com/proton/",
    },
    
    # Package data
    package_data={
        "": ["*.yaml", "*.yml", "*.json", "*.md"],
    },
    
    # Zip safe
    zip_safe=False,
)