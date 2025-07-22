"""
Setup configuration for Enterprise Migration Assessment CDK Application
"""

from setuptools import setup, find_packages

# Read the README file for long description
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "Enterprise Migration Assessment CDK Application"

# Read requirements from requirements.txt
with open("requirements.txt", "r", encoding="utf-8") as fh:
    requirements = [line.strip() for line in fh if line.strip() and not line.startswith("#")]

setup(
    name="enterprise-migration-assessment-cdk",
    version="1.0.0",
    author="AWS Solutions",
    author_email="aws-solutions@amazon.com",
    description="CDK application for Enterprise Migration Assessment with AWS Application Discovery Service",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/enterprise-migration-assessment",
    packages=find_packages(),
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: System :: Archiving :: Mirroring",
    ],
    python_requires=">=3.8",
    install_requires=requirements,
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "mypy>=1.0.0",
            "flake8>=5.0.0",
            "pre-commit>=2.20.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
            "myst-parser>=0.18.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "deploy-migration-assessment=app:main",
        ],
    },
    keywords="aws, cdk, migration, discovery, assessment, enterprise",
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/enterprise-migration-assessment/issues",
        "Source": "https://github.com/aws-samples/enterprise-migration-assessment",
        "Documentation": "https://docs.aws.amazon.com/application-discovery/",
    },
    include_package_data=True,
    zip_safe=False,
)