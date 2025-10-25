# Contributing to Raspberry Pi Boot Disk Project

Thank you for your interest in contributing to the Raspberry Pi Boot Disk project! This document provides guidelines and information for contributors.

## 📋 Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Contribution Guidelines](#contribution-guidelines)
- [Testing](#testing)
- [Documentation](#documentation)
- [Submitting Changes](#submitting-changes)
- [Release Process](#release-process)

## 🤝 Code of Conduct

This project follows a simple code of conduct:
- Be respectful and inclusive
- Help others learn and contribute
- Focus on constructive feedback
- Respect different perspectives and experiences

## 🚀 Getting Started

### Prerequisites

- Linux, macOS, or Windows with WSL
- Basic knowledge of bash scripting
- Familiarity with git and GitHub
- Understanding of Raspberry Pi boot process (helpful but not required)

### Development Setup

1. **Fork and clone the repository**:
   ```bash
   git clone https://github.com/YOUR_USERNAME/build-pi-boot-disk.git
   cd build-pi-boot-disk
   ```

2. **Set up the development environment**:
   ```bash
   ./setup.sh
   ```

3. **Create a development branch**:
   ```bash
   git checkout -b feature/your-feature-name
   ```

## 📝 Contribution Guidelines

### Types of Contributions

We welcome several types of contributions:

1. **Bug Reports**: Help us identify and fix issues
2. **Feature Requests**: Suggest new functionality
3. **Code Contributions**: Implement features or fix bugs
4. **Documentation**: Improve or expand documentation
5. **Testing**: Help test on different platforms
6. **Examples**: Add usage examples and tutorials

### Bug Reports

When reporting bugs, please include:

```markdown
**Description**: Brief description of the issue

**Environment**:
- OS: (Ubuntu 22.04, macOS 13, etc.)
- Pi Model: (Pi 4, Pi 5)
- Ubuntu Version: (22.04, 24.04)

**Steps to Reproduce**:
1. Command run: `./scripts/download-image.sh`
2. Error observed: ...

**Expected Behavior**: What should have happened

**Actual Behavior**: What actually happened

**Logs**: 
```
Paste relevant logs here
```
```

### Feature Requests

For feature requests, please describe:
- **Use case**: Why is this feature needed?
- **Proposed solution**: How should it work?
- **Alternatives considered**: Other approaches you've thought of
- **Additional context**: Screenshots, mockups, etc.

### Code Style Guidelines

#### Shell Scripts
- Use `#!/bin/bash` shebang
- Follow Google Shell Style Guide principles
- Use 4-space indentation
- Include error handling with `set -e`
- Add logging functions for output
- Include comprehensive comments

#### Example:
```bash
#!/bin/bash
# Description of what this script does

set -e

# Configuration
SCRIPT_DIR="$(dirname "$0")"
CONFIG_FILE="$SCRIPT_DIR/config.conf"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Logging function
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

# Main function with error handling
main() {
    local param="$1"
    
    if [ -z "$param" ]; then
        log_error "Parameter required"
        show_usage
        exit 1
    fi
    
    # Implementation here
}

# Run main function
main "$@"
```

#### File Structure
- Keep scripts modular and focused
- Use consistent naming conventions
- Include usage/help functions
- Add proper error handling and cleanup

### Commit Message Format

Use conventional commit format:

```
type(scope): brief description

Longer description if needed

- List any breaking changes
- Reference issues: Fixes #123
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `test`: Adding tests
- `refactor`: Code refactoring
- `style`: Formatting changes
- `chore`: Maintenance tasks

**Examples:**
```
feat(download): add support for Ubuntu 24.04 LTS

Add support for downloading and using Ubuntu 24.04 LTS images
for Raspberry Pi 5.

- Updated URL patterns for new release
- Added Pi 5 detection logic
- Updated documentation

Fixes #45
```

## 🧪 Testing

### Manual Testing

Before submitting changes:

1. **Test script functionality**:
   ```bash
   # Test download script
   ./scripts/download-image.sh -l
   
   # Test with different parameters
   ./scripts/download-image.sh -r 22.04 -t pi4
   ```

2. **Test on different platforms** (if possible):
   - Ubuntu/Debian
   - macOS
   - Windows WSL

3. **Test error conditions**:
   - Invalid parameters
   - Missing dependencies
   - Network failures
   - Insufficient disk space

### Test Checklist

- [ ] Scripts run without errors
- [ ] Help/usage functions work
- [ ] Error handling works correctly
- [ ] Dependencies are properly checked
- [ ] File permissions are correct
- [ ] Logging output is clear and helpful

## 📚 Documentation

### Documentation Standards

- Use clear, concise language
- Include practical examples
- Keep documentation up-to-date with code changes
- Use proper Markdown formatting

### Areas that need documentation:
- **README.md**: Main project documentation
- **EXAMPLES.md**: Usage examples and scenarios
- **Script comments**: Inline documentation
- **Configuration files**: Comment important settings

## 🔄 Submitting Changes

### Pull Request Process

1. **Ensure your code follows guidelines**:
   - Passes manual testing
   - Includes appropriate documentation
   - Follows coding standards

2. **Create pull request**:
   - Use descriptive title
   - Include detailed description
   - Reference related issues
   - Add screenshots if applicable

3. **Pull request template**:
   ```markdown
   ## Description
   Brief description of changes
   
   ## Type of Change
   - [ ] Bug fix
   - [ ] New feature
   - [ ] Documentation update
   - [ ] Breaking change
   
   ## Testing
   - [ ] Tested on Ubuntu/Debian
   - [ ] Tested on macOS
   - [ ] Tested error conditions
   - [ ] Updated documentation
   
   ## Related Issues
   Fixes #123
   ```

### Review Process

1. Maintainers will review your PR
2. Address any feedback or requested changes
3. Once approved, your PR will be merged

## 🎯 Development Priorities

### Current Focus Areas

1. **Platform Support**: Improve macOS and Windows compatibility
2. **Error Handling**: Better error messages and recovery
3. **Performance**: Optimize backup/restore operations
4. **Documentation**: More examples and tutorials
5. **Testing**: Automated testing framework

### Future Enhancements

- GUI interface for non-technical users
- Network-based recovery options
- Cloud backup integration
- Custom image building pipeline
- Multi-Pi fleet management

## 💡 Development Tips

### Local Development

1. **Use a test environment**:
   - Virtual machines for testing
   - Separate SD cards for experiments
   - Backup important data

2. **Debug effectively**:
   ```bash
   # Enable verbose output
   set -x
   
   # Use logging functions
   log_info "Debug: Variable value is $VAR"
   
   # Check return codes
   if ! command_that_might_fail; then
       log_error "Command failed"
       return 1
   fi
   ```

3. **Test incrementally**:
   - Test small changes frequently
   - Use version control effectively
   - Document what works and what doesn't

### Common Gotchas

- **Path handling**: Use absolute paths where possible
- **Error handling**: Always check return codes
- **Platform differences**: Test on different systems
- **Permissions**: Ensure scripts are executable
- **Dependencies**: Check for required tools

## 📞 Getting Help

If you need help:

1. **Check existing documentation**:
   - README.md
   - EXAMPLES.md
   - Inline comments

2. **Search existing issues**:
   - Look for similar problems
   - Check closed issues

3. **Ask questions**:
   - Open a GitHub issue
   - Use "question" label
   - Provide context and details

## 🏷️ Labels and Project Management

### Issue Labels

- `bug`: Something isn't working
- `enhancement`: New feature or request
- `documentation`: Improvements or additions to docs
- `good first issue`: Good for newcomers
- `help wanted`: Extra attention is needed
- `question`: Further information is requested
- `testing`: Related to testing

### Project Boards

We use GitHub Projects to track:
- **Backlog**: Planned features and improvements
- **In Progress**: Currently being worked on
- **Review**: Ready for review
- **Done**: Completed items

Thank you for contributing to the Raspberry Pi Boot Disk project! Your contributions help make reliable Pi recovery accessible to everyone.