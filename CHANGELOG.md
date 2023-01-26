# Changelog

## [2.2.0](https://github.com/stordco/kafee/compare/v2.1.0...v2.2.0) (2023-01-26)


### Features

* add telemetry events ([#29](https://github.com/stordco/kafee/issues/29)) ([d6aa690](https://github.com/stordco/kafee/commit/d6aa6904cd08b05ad23e00b4bdc7fe9e270da521))
* allow messages to be json encoded ([cdbb269](https://github.com/stordco/kafee/commit/cdbb269d255fa9a777eeffd2dbaf6f229233adaf))


### Bug Fixes

* more debugging around async worker ([#27](https://github.com/stordco/kafee/issues/27)) ([62c10d7](https://github.com/stordco/kafee/commit/62c10d76f3ef9ace39e5f526dc28a62c0fddd12f))
* update dialyzer to pass jason encoding ([80265dd](https://github.com/stordco/kafee/commit/80265ddd09706fbbf23597e79601e2cab62a73dc))

## [2.1.0](https://github.com/stordco/kafee/compare/v2.0.5...v2.1.0) (2023-01-25)


### Features

* add more error handling around brod ([d5c1032](https://github.com/stordco/kafee/commit/d5c103284de4f187f8fda3958e07ba056812d4aa))
* set retry metrics for sync producer ([#21](https://github.com/stordco/kafee/issues/21)) ([c2933c2](https://github.com/stordco/kafee/commit/c2933c2eb4fbeb05667997c4901156bfacbb1886))


### Bug Fixes

* update CI tests to run on ubuntu 20.04 for old OTP releases ([#25](https://github.com/stordco/kafee/issues/25)) ([48c78f7](https://github.com/stordco/kafee/commit/48c78f77b4ae0ded1a4b7ece868e8bf76cc0bb19))

## [2.0.5](https://github.com/stordco/kafee/compare/v2.0.4...v2.0.5) (2022-11-04)


### Bug Fixes

* [SIGNAL-2969] handle already started error ([#19](https://github.com/stordco/kafee/issues/19)) ([c541aea](https://github.com/stordco/kafee/commit/c541aea24df827338803f307eee2cdd37cdbd711))

## [2.0.4](https://github.com/stordco/kafee/compare/v2.0.3...v2.0.4) (2022-10-13)


### Bug Fixes

* dont split the queue larger than the length ([#17](https://github.com/stordco/kafee/issues/17)) ([5b96b6a](https://github.com/stordco/kafee/commit/5b96b6abb99603f0578e15d4f8b0519e17b83828))

## [2.0.3](https://github.com/stordco/kafee/compare/v2.0.2...v2.0.3) (2022-10-12)


### Bug Fixes

* increase connect timeout to 10 seconds ([#15](https://github.com/stordco/kafee/issues/15)) ([e572d7e](https://github.com/stordco/kafee/commit/e572d7ecd12eb67cbd5956783853f71c9a99eefe))

## [2.0.2](https://github.com/stordco/kafee/compare/v2.0.1...v2.0.2) (2022-10-11)


### Bug Fixes

* increase default connection timeout ([#13](https://github.com/stordco/kafee/issues/13)) ([a1a18ec](https://github.com/stordco/kafee/commit/a1a18ecded32194c737fc9a60b4148f3b1858a0e))

## [2.0.1](https://github.com/stordco/kafee/compare/v2.0.0...v2.0.1) (2022-10-11)


### Bug Fixes

* run brod config init function to fix sasl auth ([#11](https://github.com/stordco/kafee/issues/11)) ([f35e791](https://github.com/stordco/kafee/commit/f35e791c614afae37848d714fc04ad1f04e52b9f))

## [2.0.0](https://github.com/stordco/kafee/compare/v1.0.3...v2.0.0) (2022-10-10)


### ⚠ BREAKING CHANGES

* add async producer (#10)

### Features

* [SRE-84] use stordco/actions-elixir/setup ([#8](https://github.com/stordco/kafee/issues/8)) ([33153a2](https://github.com/stordco/kafee/commit/33153a2324ecd25e5bdfd94b3b4cb181e68c8d3f))
* add async producer ([#10](https://github.com/stordco/kafee/issues/10)) ([cab0aee](https://github.com/stordco/kafee/commit/cab0aee3d440be8389167af6031ec40ae32463f8))
* simplify publishing ([d7f4533](https://github.com/stordco/kafee/commit/d7f4533e8bbcc5cb6dc9d50f2efc1af90b39f641))

## [1.0.3](https://github.com/stordco/kafee/compare/v1.0.2...v1.0.3) (2022-09-07)


### Bug Fixes

* publish formatter file ([05de560](https://github.com/stordco/kafee/commit/05de56017c18ce359fe09322eebe82f153201aab))
* update urls with real hex.pm and hexdocs.pm urls ([618383e](https://github.com/stordco/kafee/commit/618383eb99be359fcf09893f32fc858b9f0d9e3e))

## [1.0.2](https://github.com/stordco/kafee/compare/v1.0.1...v1.0.2) (2022-09-07)


### Bug Fixes

* add org to mix.exs package block ([117fa28](https://github.com/stordco/kafee/commit/117fa28f715dec0d548d15950d299dcda47fa1e5))

## [1.0.1](https://github.com/stordco/kafee/compare/v1.0.0...v1.0.1) (2022-09-07)


### Bug Fixes

* update gha workflows for automated releases ([e2b12b3](https://github.com/stordco/kafee/commit/e2b12b38f31928f131f347868cb6b6da08f6f53d))
* update README to always show current version in code blocks ([f59f4d6](https://github.com/stordco/kafee/commit/f59f4d6bf541e79e7683941f24bf55ab3eb57d5c))

## 1.0.0 (2022-09-07)


### ⚠ BREAKING CHANGES

* rename module to Kafee (#5)

### Features

* add synchronous producer module ([#4](https://github.com/stordco/kafee/issues/4)) ([d73e89d](https://github.com/stordco/kafee/commit/d73e89d950b0091bcffbfed1c2255c225f564ac4))
* publish package to stord hex.pm org ([#3](https://github.com/stordco/kafee/issues/3)) ([e4b48d0](https://github.com/stordco/kafee/commit/e4b48d04f39e64a97e350d80cb09e6dd6ab93637))
* rename module to Kafee ([#5](https://github.com/stordco/kafee/issues/5)) ([7f88456](https://github.com/stordco/kafee/commit/7f88456c85b0cc80661a0b25607644d2fd94de67))


### Bug Fixes

* update brod client name to avoid process collision ([#1](https://github.com/stordco/kafee/issues/1)) ([905c897](https://github.com/stordco/kafee/commit/905c897e4904416f1128b790ef9b372fdc3a14d8))

## v0.1.0 (2022-09-6)


### Features

* initial release
