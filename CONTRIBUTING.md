# Contributing to Thread

Thank you for your interest in contributing to thread! We welcome contributions from the community.

## Code of Conduct

This project follows a code of conduct to ensure a welcoming environment for all contributors. Please be respectful and constructive in all interactions.

## How to Contribute

1. **Fork the repository** and create a feature branch from `main`.
2. **Make your changes** following the coding standards.
3. **Test your changes** thoroughly.
4. **Commit with conventional format** (see below).
5. **Submit a pull request** with a clear description.

## Development Setup

See the [README](README.md) for installation and setup instructions.

### Pre-commit Hooks

We use pre-commit hooks for code quality. Install them with:

```bash
pip install pre-commit
pre-commit install
```

Run manually with `pre-commit run --all-files`.

## Coding Standards

- **Python**: Follow PEP 8, use Ruff for linting/formatting
- **C/C++/CUDA**: 2-space indentation, clang-format style
- **YAML**: 2-space indentation, yamllint compliant
- **Commits**: Use conventional commit format

### Conventional Commits

Format: `type(scope): description`

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `ci`, `build`, `revert`

Examples:
- `feat(api): add user authentication`
- `fix(ci): resolve build failure`
- `docs(readme): update installation guide`

## Testing

- Run unit tests: `python -m pytest tests/`
- Run C/C++ tests: `cd build && ctest`
- Ensure all CI checks pass

## Pull Request Process

1. Ensure your PR has a clear title and description.
2. Reference any related issues.
3. Keep PRs focused on a single feature/fix.
4. Allow maintainers to request changes.

## Reporting Issues

Use GitHub issues for bugs, features, or questions. Provide:
- Clear description
- Steps to reproduce
- Expected vs actual behavior
- Environment details

## License

By contributing, you agree to license your work under the BSD 3-Clause license.

Thank you for contributing to thread!

---

© 2026 bniladridas; BSD 3-Clause license, see [LICENSE](LICENSE)
