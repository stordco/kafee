# Contributing

First off, thank you for contributing to Bauer! This documentation will help explain how to report issues, create pull requests, and even how to create a new release of the project.

## Code Changes

Making code changes for Bauer should be pretty straight forward. All you need is a [working Elixir install](https://elixir-lang.org/install.html). Once you are done making changes, ensure CI will pass by running these commands:

- `mix format`
- `mix test`
- `mix credo`

### Git Commit Messages

Once you are ready to commit your code, you can run `git add` and `git commit`. Please note that we use [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) in this project to easily generate changelogs and SemVer versions. If you do not follow Conventional Commits, you will get a CI error when creating the pull request.

## Releasing

Releasing Bauer is done in a mostly automated process with GitHub actions. Once you have changes merged into the `main` branch, simply trigger the ["Release" workflow](https://github.com/doomspork/bauer/actions/workflows/release.yml) on the `main` branch. This workflow will:

- Clone the repository
- Install the Node.js packages needed to release
- Analyze all of the git commits between the last release and now
- Generate a list of changes from the git commits according to [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).
- Determine the next SemVer release version
- Update `mix.exs` and `README.md` with the new version
- Update `CHANGELOG.md`
- Create a new git tag for the release
- Create a GitHub release
- Run `mix hex.publish`
