"""
Setup configuration for Global E-commerce Platform with Aurora DSQL CDK Application

This setup.py file configures the Python package for the CDK application,
including dependencies, package metadata, and development tools.
"""

import setuptools
from pathlib import Path

# Read the contents of README file (if it exists)
this_directory = Path(__file__).parent
try:
    long_description = (this_directory / "README.md").read_text()
except FileNotFoundError:
    long_description = "Global E-commerce Platform CDK Application with Aurora DSQL"

# Read requirements from requirements.txt
def get_requirements():
    """Read requirements from requirements.txt file"""
    requirements = []
    try:
        with open("requirements.txt", "r") as f:
            for line in f:
                line = line.strip()
                # Skip empty lines and comments
                if line and not line.startswith("#"):
                    # Extract just the package name and version, ignore comments
                    if "#" in line:
                        line = line.split("#")[0].strip()
                    requirements.append(line)
    except FileNotFoundError:
        # Fallback to core dependencies if requirements.txt is missing
        requirements = [
            "aws-cdk-lib>=2.167.0,<3.0.0",
            "constructs>=10.0.0,<11.0.0",
            "boto3>=1.34.0",
        ]
    return requirements

setuptools.setup(
    name="global-ecommerce-aurora-dsql-cdk",
    version="1.0.0",
    
    description="Global E-commerce Platform CDK Application with Aurora DSQL",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="Recipe Generator",
    author_email="example@example.com",
    
    url="https://github.com/example/global-ecommerce-aurora-dsql",
    
    package_dir={"": "."},
    packages=setuptools.find_packages(where="."),
    
    install_requires=get_requirements(),
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: JavaScript",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Code Generators",
        "Topic :: Utilities",
        "Typing :: Typed",
    ],
    
    entry_points={
        "console_scripts": [
            "deploy-ecommerce=app:main",
        ],
    },
    
    keywords=[
        "aws",
        "cdk",
        "aurora-dsql",
        "ecommerce",
        "serverless",
        "lambda",
        "api-gateway",
        "cloudfront",
        "distributed-database",
        "global-platform"
    ],
    
    project_urls={
        "Bug Reports": "https://github.com/example/global-ecommerce-aurora-dsql/issues",
        "Source": "https://github.com/example/global-ecommerce-aurora-dsql",
        "Documentation": "https://github.com/example/global-ecommerce-aurora-dsql/blob/main/README.md",
    },
    
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
            "pre-commit>=2.20.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
            "myst-parser>=0.18.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto[all]>=4.0.0",
        ]
    },
    
    # Include additional files in the package
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # Ensure wheel builds are universal
    options={
        "bdist_wheel": {
            "universal": True,
        }
    },
    
    zip_safe=False,
)