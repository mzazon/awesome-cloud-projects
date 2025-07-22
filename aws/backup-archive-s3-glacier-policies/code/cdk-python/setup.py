"""
Setup configuration for AWS CDK Python application.

This setup.py file configures the Python package for the backup and archive
strategies CDK application, including dependencies, metadata, and entry points.
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
                # Remove inline comments
                requirement = line.split('#')[0].strip()
                if requirement:
                    requirements.append(requirement)
        return requirements


def read_long_description():
    """Read long description from README if available."""
    readme_path = os.path.join(os.path.dirname(__file__), 'README.md')
    if os.path.exists(readme_path):
        with open(readme_path, 'r', encoding='utf-8') as f:
            return f.read()
    return "AWS CDK Python application for backup and archive strategies with S3 Glacier and lifecycle policies"


setup(
    name="backup-archive-strategies-cdk",
    version="1.0.0",
    
    description="AWS CDK Python application for backup and archive strategies with S3 Glacier and lifecycle policies",
    long_description=read_long_description(),
    long_description_content_type="text/markdown",
    
    author="AWS Cloud Operations Team",
    author_email="cloudops@company.com",
    
    url="https://github.com/company/backup-archive-strategies-cdk",
    
    packages=find_packages(exclude=["tests*"]),
    
    python_requires=">=3.8",
    
    install_requires=read_requirements(),
    
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: System Administrators",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: System :: Archiving :: Backup",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: Internet :: WWW/HTTP",
        "Environment :: Console",
    ],
    
    keywords=[
        "aws",
        "cdk",
        "s3",
        "glacier",
        "backup",
        "archive",
        "lifecycle",
        "storage",
        "cloudformation",
        "infrastructure-as-code"
    ],
    
    entry_points={
        "console_scripts": [
            "backup-archive-cdk=app:main",
        ],
    },
    
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.7.0",
            "flake8>=6.0.0",
            "mypy>=1.5.0",
            "pip-tools>=7.1.0",
        ],
        "test": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "aws-cdk.assertions>=2.100.0",
        ],
    },
    
    project_urls={
        "Bug Reports": "https://github.com/company/backup-archive-strategies-cdk/issues",
        "Source": "https://github.com/company/backup-archive-strategies-cdk",
        "Documentation": "https://github.com/company/backup-archive-strategies-cdk/blob/main/README.md",
    },
    
    zip_safe=False,
    
    # Package data and additional files
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # Metadata for PyPI
    license="MIT",
    platforms=["any"],
    
    # CDK-specific metadata
    data_files=[
        ("cdk", ["cdk.json"]),
    ] if os.path.exists("cdk.json") else [],
)