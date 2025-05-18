# Contributing to Sum

Thank you for taking the time to contribute!

## Proposing Changes

1. Fork this repository and create a feature branch.
2. Make your changes with clear commit messages.
3. Ensure the project builds and tests pass.
4. Open a pull request against `main` explaining your changes.

## Running Tests

Execute the tests with `xcodebuild` on an iOS simulator:

```bash
xcodebuild test -scheme Sum -destination 'platform=iOS Simulator,name=iPhone 15'
```

Use a simulator available on your machine if the example name does not match.

## Contribution Standards

- Follow the existing Swift style and keep changes focused.
- Update documentation when you modify or add features.
- Pull requests run through continuous integration, so please make sure tests succeed before submitting.
