"""
Setup configuration for the cloud-based development workflows CDK application.

This setup.py file configures the Python package for the CDK application that
creates infrastructure for cloud-based development workflows using AWS CloudShell
and CodeCommit.
"""

from setuptools import setup, find_packages

# Read the README file for the long description
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = (
        "AWS CDK application for cloud-based development workflows using "
        "AWS CloudShell and CodeCommit. Creates secure, scalable infrastructure "
        "for browser-based development environments."
    )

# Read requirements from requirements.txt
def read_requirements():
    """Read and parse requirements from requirements.txt file."""
    requirements = []
    try:
        with open("requirements.txt", "r", encoding="utf-8") as req_file:
            for line in req_file:
                line = line.strip()
                # Skip comments and empty lines
                if line and not line.startswith("#"):
                    # Remove inline comments
                    req = line.split("#")[0].strip()
                    if req:
                        requirements.append(req)
    except FileNotFoundError:
        # Fallback requirements if file doesn't exist
        requirements = [
            "aws-cdk-lib>=2.120.0,<3.0.0",
            "constructs>=10.0.0,<11.0.0",
        ]
    return requirements

setup(
    name="cloud-based-development-workflows-cdk",
    version="1.0.0",
    author="AWS Solutions Architecture",
    author_email="solutions-architecture@amazon.com",
    description="AWS CDK application for cloud-based development workflows",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/cloud-recipes",
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/cloud-recipes/issues",
        "Source": "https://github.com/aws-samples/cloud-recipes",
        "Documentation": "https://docs.aws.amazon.com/cloudshell/",
    },
    packages=find_packages(exclude=["tests", "tests.*"]),
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Build Tools",
        "Topic :: Software Development :: Version Control :: Git",
        "Topic :: System :: Systems Administration",
        "Framework :: AWS CDK",
        "Framework :: AWS CDK :: 2",
    ],
    python_requires=">=3.8",
    install_requires=read_requirements(),
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
            "isort>=5.12.0",
            "bandit>=1.7.0",
            "safety>=2.3.0",
        ],
        "docs": [
            "sphinx>=6.0.0",
            "sphinx-rtd-theme>=1.2.0",
        ],
        "test": [
            "moto>=4.2.0",
            "localstack>=3.0.0",
            "boto3>=1.26.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "deploy-dev-workflow=app:main",
        ],
    },
    include_package_data=True,
    package_data={
        "": [
            "*.md",
            "*.txt",
            "*.yml",
            "*.yaml",
            "*.json",
        ],
    },
    zip_safe=False,
    keywords=[
        "aws",
        "cdk",
        "cloudshell",
        "codecommit",
        "git",
        "development",
        "workflow",
        "devops",
        "infrastructure",
        "cloud",
        "browser-based",
        "version-control",
        "collaboration",
    ],
    platforms=["any"],
    license="MIT",
    license_files=["LICENSE"],
)