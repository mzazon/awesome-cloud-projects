"""
Setup configuration for AWS CDK Python application.

This setup.py file configures the Python package for the Self-Service File Management
with AWS Transfer Family Web Apps CDK application.
"""

from setuptools import setup, find_packages

# Read the README file for long description
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "AWS CDK Python application for Self-Service File Management with Transfer Family Web Apps"

# Read requirements from requirements.txt
with open("requirements.txt", "r", encoding="utf-8") as fh:
    requirements = [line.strip() for line in fh if line.strip() and not line.startswith("#")]

setup(
    name="transfer-family-file-management-cdk",
    version="1.0.0",
    author="AWS CDK Developer",
    author_email="developer@example.com",
    description="AWS CDK Python application for Self-Service File Management with Transfer Family Web Apps",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/your-org/transfer-family-file-management-cdk",
    packages=find_packages(),
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Operating System :: OS Independent",
        "Framework :: AWS CDK",
    ],
    python_requires=">=3.8",
    install_requires=requirements,
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "isort>=5.12.0",
            "mypy>=1.0.0",
        ],
        "docs": [
            "sphinx>=7.0.0",
            "sphinx-rtd-theme>=1.3.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "transfer-family-file-management=app:main",
        ],
    },
    keywords=[
        "aws",
        "cdk",
        "infrastructure",
        "transfer-family",
        "s3",
        "identity-center",
        "access-grants",
        "file-management",
        "web-apps",
        "secure-file-sharing",
    ],
    project_urls={
        "Bug Reports": "https://github.com/your-org/transfer-family-file-management-cdk/issues",
        "Source": "https://github.com/your-org/transfer-family-file-management-cdk",
        "Documentation": "https://github.com/your-org/transfer-family-file-management-cdk/wiki",
    },
    include_package_data=True,
    zip_safe=False,
)