# Contributing

First off, thank you for contributing to Kafee! This documentation will help explain how to report issues, create pull requests, and even how to create a new release of the project.

## Code Changes

Making code changes for Kafee should be pretty straight forward. All you need is a [working Elixir install](https://elixir-lang.org/install.html). Once you are done making changes, ensure CI will pass by running these commands:

- `mix format`
- `mix test`
- `mix credo`

### Git Commit Messages

Once you are ready to commit your code, you can run `git add` and `git commit`. Please note that we use [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) in this project to easily generate changelogs and SemVer versions. If you do not follow Conventional Commits, you will get a CI error when creating the pull request.

## Releasing

Releasing Kafee is done in a mostly automated process with GitHub actions. Once you have changes merged into the `main` branch, a [PR will be created or updated](https://github.com/stordco/kafee/pulls?q=is%3Apr+sort%3Aupdated-desc+label%3A%22autorelease%3A+tagged%22) that includes the latest version bump, updated changelog, and everything else needed for a new release. A maintainer will double check everything looks good on that PR and merge it in. Once that PR is merged, a new GitHub release will be created automatically as well as the release being built and published on Hex.pm.
