### Testing

Tests are located in the `test` directory. You can run them using the Dev Container CLI:

```bash
# Run all tests (standard and scenarios)
test/test-all.sh

# Run standard feature tests
devcontainer features test -f devcontainer-profile --project-folder .

```

### Docs
Docs are generated with  
```bash
devcontainer features generate-docs -p src -n q4rk/devcontainer-features
```
