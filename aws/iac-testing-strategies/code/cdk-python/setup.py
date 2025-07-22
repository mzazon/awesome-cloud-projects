"""
Setup configuration for the Infrastructure as Code Testing CDK application.

This setup.py file configures the Python package for the CDK application
that creates automated testing infrastructure for Infrastructure as Code.
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
        for line in fh:
            line = line.strip()
            # Skip comments and empty lines
            if line and not line.startswith("#"):
                # Remove inline comments
                requirement = line.split("#")[0].strip()
                if requirement:
                    install_requires.append(requirement)

setuptools.setup(
    name="iac-testing-cdk",
    version="1.0.0",
    
    description="CDK application for automated testing strategies for Infrastructure as Code",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS CDK Team",
    author_email="aws-cdk@amazon.com",
    
    python_requires=">=3.9",
    
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: Apache Software License",
        "Programming Language :: JavaScript",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Code Generators",
        "Topic :: Utilities",
        "Typing :: Typed",
    ],
    
    install_requires=install_requires,
    
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "pytest-mock>=3.12.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.5.0",
            "isort>=5.12.0",
        ],
        "testing": [
            "moto>=4.2.0",
            "cfn-lint>=0.83.0",
            "checkov>=3.0.0",
        ]
    },
    
    packages=setuptools.find_packages(exclude=["tests", "tests.*"]),
    
    entry_points={
        "console_scripts": [
            "iac-testing-cdk=app:main",
        ],
    },
    
    project_urls={
        "Bug Reports": "https://github.com/aws/aws-cdk/issues",
        "Source": "https://github.com/aws/aws-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
    },
    
    keywords="aws cdk infrastructure-as-code testing automation devops ci-cd",
    
    zip_safe=False,
    
    include_package_data=True,
    
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
)