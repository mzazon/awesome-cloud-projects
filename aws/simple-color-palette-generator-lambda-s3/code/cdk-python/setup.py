"""
Setup configuration for the Color Palette Generator CDK Python application.

This setup.py file configures the Python package for the CDK application,
including metadata, dependencies, and entry points.
"""

import setuptools

# Read the README file for the long description
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "Simple Color Palette Generator with AWS Lambda and S3 using CDK Python"

# Read requirements from requirements.txt
with open("requirements.txt", "r", encoding="utf-8") as fh:
    requirements = [
        line.strip() 
        for line in fh 
        if line.strip() and not line.startswith("#")
    ]

setuptools.setup(
    name="color-palette-generator-cdk",
    version="1.0.0",
    
    author="AWS CDK Developer",
    author_email="developer@example.com",
    
    description="CDK Python application for Simple Color Palette Generator with Lambda and S3",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    url="https://github.com/example/color-palette-generator-cdk",
    
    packages=setuptools.find_packages(),
    
    install_requires=requirements,
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Utilities",
    ],
    
    keywords="aws cdk lambda s3 serverless color palette generator",
    
    project_urls={
        "Bug Reports": "https://github.com/example/color-palette-generator-cdk/issues",
        "Source": "https://github.com/example/color-palette-generator-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
    },
    
    entry_points={
        "console_scripts": [
            "color-palette-generator=app:main",
        ],
    },
    
    # Include additional files
    include_package_data=True,
    
    # Package data
    package_data={
        "": ["*.md", "*.txt", "*.json"],
    },
    
    # Exclude test files from distribution
    exclude_package_data={
        "": ["tests/*", "test_*"],
    },
    
    # Additional metadata
    platforms=["any"],
    zip_safe=False,
)