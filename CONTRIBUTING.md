# Contributing to Tor Guard Relay 🧅

First off, thank you for considering contributing to this project! Every contribution helps make the Tor network stronger and more accessible.

## 🌟 Ways to Contribute

### 1. Running a Relay
The best contribution is running your own Tor relay using this project! Share your experience and help others.

### 2. Reporting Issues
- 🐛 Found a bug? [Open an issue](https://github.com/r3bo0tbx1/tor-guard-relay/issues)
- 💡 Have a feature idea? Share it!
- 📖 Documentation unclear? Let us know!

### 3. Improving Documentation
- Fix typos or unclear explanations
- Add examples or use cases
- Translate documentation
- Create tutorials or guides

### 4. Code Contributions
- Bug fixes
- New features
- Performance improvements
- Test coverage

---

## 🚀 Getting Started

### Prerequisites
- Docker installed
- Git basics
- Understanding of Tor relay operation (optional but helpful)

### Fork & Clone
```bash
# Fork the repo on GitHub, then:
git clone https://github.com/YOUR_USERNAME/tor-guard-relay.git
cd tor-guard-relay

# Add upstream remote
git remote add upstream https://github.com/r3bo0tbx1/tor-guard-relay.git
```

### Local Development
```bash
# Build locally
docker build \
  --build-arg BUILD_DATE="$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
  --build-arg BUILD_VERSION="dev" \
  -t onion-relay:dev \
  -f Dockerfile .

# Test your changes
docker run --rm onion-relay:dev cat /build-info.txt

# Test with configuration
docker run -d \
  --name test-relay \
  --network host \
  -v ./examples/relay.conf.example:/etc/tor/torrc:ro \
  onion-relay:dev
```

---

## 📝 Contribution Guidelines

### Branch Naming
- `feature/your-feature-name` - New features
- `fix/bug-description` - Bug fixes
- `docs/what-you-changed` - Documentation
- `chore/maintenance-task` - Maintenance

### Commit Messages
Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add ARM64 support for Raspberry Pi
fix: correct permission handling in entrypoint
docs: update deployment guide for Cosmos
chore: bump Alpine to edge
```

**Format:**
```
<type>: <description>

[optional body]

[optional footer]
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation only
- `style`: Code style (formatting, no logic change)
- `refactor`: Code refactoring
- `perf`: Performance improvement
- `test`: Adding tests
- `chore`: Maintenance tasks
- `ci`: CI/CD changes

### Pull Request Process

1. **Create a branch** from `main`
   ```bash
   git checkout -b feature/my-feature
   ```

2. **Make your changes**
   - Keep commits atomic and focused
   - Test thoroughly
   - Update documentation if needed

3. **Push to your fork**
   ```bash
   git push origin feature/my-feature
   ```

4. **Open a Pull Request**
   - Use a clear title
   - Describe what changed and why
   - Reference any related issues
   - Add screenshots if UI-related

5. **Respond to feedback**
   - Be open to suggestions
   - Make requested changes
   - Keep discussion professional

### PR Template
```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Documentation update
- [ ] Performance improvement
- [ ] Other (specify)

## Testing
How did you test this?

## Checklist
- [ ] Code follows project style
- [ ] Documentation updated
- [ ] Tested locally
- [ ] No breaking changes (or documented)
```

---

## 🧪 Testing Guidelines

### Docker Build Testing
```bash
# Test build
docker build -f Dockerfile -t test:latest .

# Verify scripts are executable
docker run --rm test:latest ls -la /usr/local/bin/

# Test diagnostics
docker run --rm test:latest relay-status || echo "Expected to fail without config"
```

### Configuration Validation
```bash
# Test with example config
docker run --rm \
  -v ./examples/relay.conf.example:/etc/tor/torrc:ro \
  test:latest tor --verify-config -f /etc/tor/torrc
```

### Multi-Architecture Testing
```bash
# Build for specific platforms
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -f Dockerfile \
  -t test:multiarch .
```

---

## 📖 Documentation Standards

### Markdown Style
- Use headers hierarchically (h1 → h2 → h3)
- Include code blocks with language tags
- Add emoji sparingly for visual hierarchy
- Keep line length reasonable (~80-100 chars)
- Use tables for structured data

### Code Comments
```bash
#!/bin/bash
# Brief description of script purpose

# Function: what_it_does
# Parameters: $1 - description
# Returns: description
function_name() {
  # Inline comments for complex logic
  command
}
```

### Example Quality
- Provide working, copy-paste-ready examples
- Include expected output
- Explain parameters
- Note prerequisites

---

## 🔒 Security Guidelines

### Reporting Security Issues
**DO NOT** open public issues for security vulnerabilities.

Instead:
1. Email: r3bo0tbx1@brokenbotnet.com
2. Include:
   - Description of vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)

### Security Best Practices
- Never commit secrets or credentials
- Use read-only mounts for configs
- Maintain non-root user operation
- Document security implications of changes
- Test permission handling

---

## 🎨 Code Style

### Dockerfile
```dockerfile
# Group related RUN commands
RUN apk add --no-cache \
    package1 \
    package2 && \
    cleanup_command

# Use specific versions for reproducibility
FROM alpine:edge

# Document ARGs
ARG BUILD_DATE
ARG BUILD_VERSION="1.4"
```

### Bash Scripts
```bash
#!/bin/bash
set -euo pipefail  # Always use strict mode

# Use meaningful variable names
readonly CONTAINER_NAME="guard-relay"

# Check prerequisites
if ! command -v docker &> /dev/null; then
    echo "Error: Docker not found"
    exit 1
fi
```

### YAML
```yaml
# Use 2-space indentation
# Quote strings when ambiguous
# Comment complex sections

services:
  relay:
    # Service configuration
    image: "ghcr.io/r3bo0tbx1/onion-relay:latest"
```

---

## 🏷️ Issue Labels

When creating issues, use appropriate labels:

| Label | Purpose |
|-------|---------|
| `bug` | Something isn't working |
| `enhancement` | New feature or request |
| `documentation` | Improvements or additions to docs |
| `good first issue` | Good for newcomers |
| `help wanted` | Extra attention is needed |
| `question` | Further information is requested |
| `security` | Security-related issue |

---

## 🤝 Code of Conduct

### Our Pledge
We are committed to providing a welcoming and inclusive environment for everyone.

### Expected Behavior
- ✅ Be respectful and considerate
- ✅ Accept constructive criticism gracefully
- ✅ Focus on what's best for the community
- ✅ Show empathy toward others

### Unacceptable Behavior
- ❌ Harassment or discrimination
- ❌ Trolling or insulting comments
- ❌ Public or private harassment
- ❌ Publishing others' private information

### Enforcement
Violations may result in:
1. Warning
2. Temporary ban
3. Permanent ban

Report issues to: r3bo0tbx1@brokenbotnet.com

---

## 📞 Getting Help

- 💬 [GitHub Discussions](https://github.com/r3bo0tbx1/tor-guard-relay/discussions)
- 🐛 [Issue Tracker](https://github.com/r3bo0tbx1/tor-guard-relay/issues)
- 📧 Email: r3bo0tbx1@brokenbotnet.com
- 🌐 [Tor Project Forum](https://forum.torproject.net/)

---

## 🎉 Recognition

Contributors will be:
- Listed in release notes
- Mentioned in CHANGELOG
- Added to README acknowledgments (for significant contributions)

---

## 📜 License

By contributing, you agree that your contributions will be licensed under the MIT License.

---

## 🙏 Thank You!

Every contribution, no matter how small, makes a difference. Thank you for helping make the Tor network stronger and more accessible!

**Happy Contributing!** 🧅✨