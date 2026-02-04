# GitHub workflow parts

[![CI](https://github.com/devpro/github-workflow-parts/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/devpro/github-workflow-parts/actions/workflows/ci.yml)

Repository of workflow parts to be used in GitHub Actions.

## Actions

Technology | Role     | Action                                                  | Detail
-----------|----------|---------------------------------------------------------|----------------------------------------------------------------------------
Docker     | CD       | [Build & Push](docker/build-push/action.yml)            | Build a new container image with Docker, and push it to a container registry
Docker     | CI       | [Build & Scan](docker/build-scan/action.yml)            | Build a new container image with Docker, and scan it
.NET       | CI       | [Build, lint & test](dotnet/build-lint-test/action.yml) | Build .NET code, check the code with linter and Sonar, and run tests
MongoDB    | Services | [Start](mongodb/start/action.yml)                       | Start a local MongoDB database
