"""
Setup configuration for Simple Text Processing CDK Python Application.

This setup.py file configures the Python package for the CDK application,
including dependencies, metadata, and development requirements.
"""

from setuptools import setup, find_packages

# Read the README file for long description
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "AWS CDK Python application for simple text processing with CloudShell and S3"

# Read requirements from requirements.txt
def get_requirements():
    """Parse requirements.txt and return list of dependencies."""
    try:
        with open("requirements.txt", "r", encoding="utf-8") as f:
            requirements = []
            for line in f:
                line = line.strip()
                # Skip empty lines and comments
                if line and not line.startswith("#"):
                    # Remove inline comments
                    if "#" in line:
                        line = line.split("#")[0].strip()
                    requirements.append(line)
            return requirements
    except FileNotFoundError:
        # Fallback to minimal requirements if file doesn't exist
        return [
            "aws-cdk-lib>=2.150.0",
            "constructs>=10.0.0"
        ]

setup(
    # Package metadata
    name="simple-text-processing-cdk",
    version="1.0.0",
    author="AWS CDK Generator",
    author_email="example@example.com",
    description="AWS CDK Python application for simple text processing with CloudShell and S3",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/example/simple-text-processing-cdk",
    
    # Package configuration
    packages=find_packages(exclude=["tests*"]),
    include_package_data=True,
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=get_requirements(),
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=6.2.0",
            "pytest-cdk>=1.0.0",
            "black>=22.0.0",
            "flake8>=4.0.0",
            "mypy>=0.991",
            "bandit>=1.7.5",
        ],
        "test": [
            "pytest>=6.2.0",
            "pytest-cdk>=1.0.0",
            "moto>=4.0.0",  # For mocking AWS services in tests
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.2.0",
        ]
    },
    
    # Package classification
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
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP",
        "Framework :: AWS CDK",
    ],
    
    # Keywords for package discovery
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "s3",
        "cloudshell",
        "text-processing",
        "data-analysis"
    ],
    
    # Entry points for command-line tools (if needed)
    entry_points={
        "console_scripts": [
            # Add command-line tools here if needed
            # "text-processor=simple_text_processing.cli:main",
        ],
    },
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/example/simple-text-processing-cdk/issues",
        "Source": "https://github.com/example/simple-text-processing-cdk",
        "Documentation": "https://simple-text-processing-cdk.readthedocs.io/",
    },
    
    # License
    license="MIT",
    
    # Zip safe configuration
    zip_safe=False,
)