# Local Development Guide

This guide explains how to test the static site generator locally without pushing to GitHub.

## Quick Start

### 1. Parse README to JSON

```bash
cd /path/to/awesome-cloud-projects
python3 .publish/scripts/parse_awesome_cloud.py README.md \
  --output .publish/data/projects.json \
  --repo-url https://github.com/mzazon/awesome-cloud-projects \
  --verbose
```

This will:
- Parse the README.md file
- Extract all project information
- Generate `.publish/data/projects.json`
- Show statistics about projects, providers, categories, etc.

### 2. Build the Static Site

```bash
python3 .publish/scripts/build_site.py
```

This will:
- Load `projects.json` and `learning-paths.json`
- Validate all data
- Generate `.publish/docs/index.html`
- Show statistics about the build

### 3. Preview Locally

```bash
cd .publish/docs
python3 -m http.server 8000
```

Then open your browser to: **http://localhost:8000**

## Development Workflow

### Making Changes to the Parser

1. Edit `.publish/scripts/parse_awesome_cloud.py`
2. Test with: `python3 .publish/scripts/parse_awesome_cloud.py README.md --output .publish/data/projects.json --verbose`
3. Check the output statistics and `.publish/data/projects.json`

### Making Changes to the Site Template

1. Edit `.publish/templates/site/index.html`
2. Rebuild: `python3 .publish/scripts/build_site.py`
3. Refresh browser (you may need to do a hard refresh: Cmd+Shift+R on Mac, Ctrl+F5 on Windows)

### Updating Learning Paths

1. Edit `.publish/data/learning-paths.json` directly
2. Rebuild: `python3 .publish/scripts/build_site.py`
3. Refresh browser

## Troubleshooting

### Parser finds wrong number of projects

- Check that README.md is formatted correctly
- Look for invalid project entries (links starting with `#` are skipped)
- Run with `--verbose` flag to see detailed parsing info

### Site doesn't display correctly

- Check browser console for JavaScript errors (F12 → Console tab)
- Verify `projects.json` has valid JSON (use `python3 -m json.tool .publish/data/projects.json`)
- Check that all project IDs in learning paths exist in projects.json

### Changes not showing up

- Do a hard refresh in your browser (Cmd+Shift+R or Ctrl+F5)
- Make sure you rebuilt the site after making changes
- Check that you're viewing the correct URL (localhost:8000)

## File Structure

```
.publish/
├── scripts/
│   ├── parse_awesome_cloud.py  # Parses README.md → projects.json
│   ├── build_site.py           # Builds static site
│   ├── init_learning_paths.py  # Initializes learning paths
│   └── generate_readme.py      # Generates README (existing)
├── data/
│   ├── projects.json           # Generated from README.md (gitignored)
│   └── learning-paths.json     # Curated learning paths
├── templates/site/
│   └── index.html              # Site template (2,500+ lines)
└── docs/
    └── index.html              # Generated site (gitignored)
```

## Tips

- **Use --verbose flag**: Shows detailed parsing statistics
- **Check projects.json**: Validate the generated data before building
- **Browser DevTools**: Use F12 to inspect elements and debug CSS/JS
- **Clear browser cache**: Sometimes needed when CSS changes don't appear
- **Use themes**: The site has 6 themes - test your changes in multiple themes

## Common Tasks

### Add a new learning path

1. Find project IDs: `python3 -c "import json; data = json.load(open('.publish/data/projects.json')); print('\n'.join([p['id'] for p in data[:20]])) "`
2. Edit `.publish/data/learning-paths.json`
3. Add new path object with `id`, `name`, `description`, and `projectIds`
4. Rebuild and test

### Test a specific filter

1. Build and serve the site locally
2. Open DevTools Console (F12)
3. Type: `PROJECTS_DATA.filter(p => p.provider === 'aws').length`
4. Test various filters to debug issues

### Validate JSON files

```bash
# Validate projects.json
python3 -m json.tool .publish/data/projects.json > /dev/null && echo "Valid JSON" || echo "Invalid JSON"

# Validate learning-paths.json
python3 -m json.tool .publish/data/learning-paths.json > /dev/null && echo "Valid JSON" || echo "Invalid JSON"
```

## Need Help?

- Check the parser script comments for format details
- Look at existing projects.json for data structure examples
- Review the HTML template for available CSS classes and JavaScript functions
