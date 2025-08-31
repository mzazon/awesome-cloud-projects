"""
Python package setup for Simple Infrastructure Templates CDK Application

This setup.py file configures the CDK Python application as a Python package
with proper dependencies and metadata for deployment and development.
"""

import setuptools
from pathlib import Path

# Read the README file for the long description
readme_path = Path(__file__).parent / "README.md"
long_description = readme_path.read_text(encoding="utf-8") if readme_path.exists() else ""

# Read requirements from requirements.txt
requirements_path = Path(__file__).parent / "requirements.txt"
if requirements_path.exists():
    with open(requirements_path, "r", encoding="utf-8") as f:
        install_requires = [
            line.strip()
            for line in f
            if line.strip() and not line.startswith("#")
        ]
else:
    # Fallback requirements if requirements.txt is not found
    install_requires = [
        "aws-cdk-lib>=2.150.0,<3.0.0",
        "constructs>=10.3.0,<11.0.0",
    ]

setuptools.setup(
    name="simple-infrastructure-templates-cdk",
    version="1.0.0",
    description="CDK Python application for Simple Infrastructure Templates with S3",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS CDK Recipe Generator",
    author_email="your-email@example.com",
    url="https://github.com/your-org/simple-infrastructure-templates-cdk",
    
    # Package configuration
    packages=setuptools.find_packages(),
    include_package_data=True,
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Dependencies
    install_requires=install_requires,
    
    # Development dependencies (optional)
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "black>=22.0.0",
            "mypy>=1.0.0",
            "flake8>=5.0.0",
            "aws-cdk.assertions>=2.150.0,<3.0.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "aws-cdk.assertions>=2.150.0,<3.0.0",
        ],
    },
    
    # Entry points for command line scripts
    entry_points={
        "console_scripts": [
            "cdk-app=app:main",
        ],
    },
    
    # Package classification
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
    
    # Keywords for searchability
    keywords="aws cdk cloudformation s3 infrastructure-as-code devops",
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/your-org/simple-infrastructure-templates-cdk/issues",
        "Source": "https://github.com/your-org/simple-infrastructure-templates-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
    },
    
    # License
    license="Apache-2.0",
    
    # Zip safe configuration
    zip_safe=False,
)