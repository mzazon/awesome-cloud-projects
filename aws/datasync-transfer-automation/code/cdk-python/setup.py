"""
AWS DataSync Data Transfer Automation - CDK Python Setup

This setup.py file configures the Python package for the DataSync CDK application.
It includes all necessary dependencies and metadata for the project.
"""

import setuptools
from pathlib import Path

# Read the contents of README file if it exists
this_directory = Path(__file__).parent
readme_file = this_directory / "README.md"
long_description = ""
if readme_file.exists():
    long_description = readme_file.read_text(encoding="utf-8")

# Read requirements from requirements.txt
requirements_file = this_directory / "requirements.txt"
requirements = []
if requirements_file.exists():
    with open(requirements_file, "r", encoding="utf-8") as f:
        requirements = [
            line.strip()
            for line in f
            if line.strip() and not line.startswith("#")
        ]

setuptools.setup(
    name="datasync-data-transfer-automation",
    version="1.0.0",
    description="AWS DataSync Data Transfer Automation CDK application",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS Recipe Generator",
    author_email="support@example.com",
    url="https://github.com/example/datasync-data-transfer-automation",
    
    # Package information
    packages=setuptools.find_packages(),
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=requirements,
    
    # Entry points
    entry_points={
        "console_scripts": [
            "datasync-app=app:main",
        ],
    },
    
    # Classifiers for PyPI
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP :: HTTP Servers",
        "Environment :: Console",
        "Operating System :: OS Independent",
    ],
    
    # Keywords for discoverability
    keywords=[
        "aws",
        "cdk",
        "datasync",
        "data-transfer",
        "automation",
        "s3",
        "storage",
        "migration",
        "cloudformation",
        "infrastructure-as-code",
    ],
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/example/datasync-data-transfer-automation/issues",
        "Source": "https://github.com/example/datasync-data-transfer-automation",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "AWS DataSync": "https://docs.aws.amazon.com/datasync/",
    },
    
    # Include additional files
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # Zip safe
    zip_safe=False,
    
    # Additional metadata
    platforms=["any"],
    license="Apache-2.0",
)