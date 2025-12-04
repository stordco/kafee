# Changelog

## [3.6.0](https://github.com/stordco/kafee/compare/v3.5.4...v3.6.0) (2025-12-04)


### Features

* WMS-1874 adding lower level brod options support ([#140](https://github.com/stordco/kafee/issues/140)) ([c13fbf0](https://github.com/stordco/kafee/commit/c13fbf0c6b8e13f4e29c574212f452ab84016d46))


### Miscellaneous

* Sync files with stordco/common-config-elixir ([#135](https://github.com/stordco/kafee/issues/135)) ([d1f8084](https://github.com/stordco/kafee/commit/d1f80848e6306f3bb89ea805679d6137ae3fc772))

## [3.5.4](https://github.com/stordco/kafee/compare/v3.5.3...v3.5.4) (2025-01-16)


### Bug Fixes

* Test to be more accurate ([#133](https://github.com/stordco/kafee/issues/133)) ([ed7a92c](https://github.com/stordco/kafee/commit/ed7a92ca10248e2e6061619f161d7a87a47285a4))

## [3.5.3](https://github.com/stordco/kafee/compare/v3.5.2...v3.5.3) (2025-01-14)


### Miscellaneous

* Add consumer lag utility for brod ([#131](https://github.com/stordco/kafee/issues/131)) ([a03991e](https://github.com/stordco/kafee/commit/a03991ec5f85f328ea01a0cf5ab882bd9263dd30))

## [3.5.2](https://github.com/stordco/kafee/compare/v3.5.1...v3.5.2) (2024-12-17)


### Miscellaneous

* Update github codeowners ([#129](https://github.com/stordco/kafee/issues/129)) ([53e2904](https://github.com/stordco/kafee/commit/53e290447ea31f9ef24c9fd9e42d08fdc6ade881))

## [3.5.1](https://github.com/stordco/kafee/compare/v3.5.0...v3.5.1) (2024-12-13)


### Bug Fixes

* Improve Kafee exception handling ([#126](https://github.com/stordco/kafee/issues/126)) ([fa5bd44](https://github.com/stordco/kafee/commit/fa5bd443b48c48d551427485cc9ec5b671d6dbea))
* Update kafee consumer handle_failure/2 fn ([#119](https://github.com/stordco/kafee/issues/119)) ([4c12df7](https://github.com/stordco/kafee/commit/4c12df78ca8b4466879c140a0acdd04c1c4fff7f))


### Miscellaneous

* Correct documentation to include start.count metric ([#125](https://github.com/stordco/kafee/issues/125)) ([3ab284c](https://github.com/stordco/kafee/commit/3ab284cd1f55a633b4584c4cc430fe85d9f6cb8d))
* Sync files with stordco/common-config-elixir ([#128](https://github.com/stordco/kafee/issues/128)) ([3adffb8](https://github.com/stordco/kafee/commit/3adffb84415424aa8e493b3408500c9d19ec27a3))

## [3.5.0](https://github.com/stordco/kafee/compare/v3.4.1...v3.5.0) (2024-11-21)


### Features

* Set more consumer metadata on message processing ([#120](https://github.com/stordco/kafee/issues/120)) ([9f42529](https://github.com/stordco/kafee/commit/9f42529c6eaf3f8b48e11850d549531c9775cfe7))


### Miscellaneous

* A few grammar updates ([#121](https://github.com/stordco/kafee/issues/121)) ([1a01b52](https://github.com/stordco/kafee/commit/1a01b52f16cc67e1ed68ecb9741546797a59df2b))
* Fix typo in BrodAdapter ([#118](https://github.com/stordco/kafee/issues/118)) ([8ddc754](https://github.com/stordco/kafee/commit/8ddc754e0c288e2d130855c9e6e5b73d7f48d84c))
* Sync files with stordco/common-config-elixir ([#116](https://github.com/stordco/kafee/issues/116)) ([37bd7ff](https://github.com/stordco/kafee/commit/37bd7ff3052af41689281bba7020f949e1e2c7e4))
* Update documentation ([#114](https://github.com/stordco/kafee/issues/114)) ([7c9947d](https://github.com/stordco/kafee/commit/7c9947d716367a2a267f47a859388b22c2051fa8))
* Update typo in producer docs ([#117](https://github.com/stordco/kafee/issues/117)) ([ebea101](https://github.com/stordco/kafee/commit/ebea1019a325e4ed8bb943b04a0e50ea1810fa12))

## [3.4.1](https://github.com/stordco/kafee/compare/v3.4.0...v3.4.1) (2024-10-23)


### Miscellaneous

* SIGNAL-7217 increase timeout for Task.await_many to account for 15 sec DB timeouts + buffer ([#112](https://github.com/stordco/kafee/issues/112)) ([38ab6fc](https://github.com/stordco/kafee/commit/38ab6fcaeeee8796444cf9e5d0105588cfb76276))

## [3.4.0](https://github.com/stordco/kafee/compare/v3.3.1...v3.4.0) (2024-10-18)


### Features

* SIGNAL-7190 Task.await_many for batch operations ([#110](https://github.com/stordco/kafee/issues/110)) ([79c9f42](https://github.com/stordco/kafee/commit/79c9f42d2c307139d0f7e784d020be7ab3686682))

## [3.3.1](https://github.com/stordco/kafee/compare/v3.3.0...v3.3.1) (2024-10-17)


### Bug Fixes

* UPDATE: kafee async worker to log only the headers + topic for large message error instead of the payload as it can go over the datadog limit ([#108](https://github.com/stordco/kafee/issues/108)) ([1d98363](https://github.com/stordco/kafee/commit/1d98363f8970dad7ce355fff1734e76caddd388e))

## [3.3.0](https://github.com/stordco/kafee/compare/v3.2.0...v3.3.0) (2024-10-07)


### Features

* Additional options to allow for batching and asynchronous batch handling for BroadwayAdapter ([#103](https://github.com/stordco/kafee/issues/103)) ([f003f0b](https://github.com/stordco/kafee/commit/f003f0bf990b60343e09df0e8fd95f21ae290560))

## [3.2.0](https://github.com/stordco/kafee/compare/v3.1.2...v3.2.0) (2024-10-01)


### Features

* SIGNAL-7060 preemtively drop large messages from queue ([#101](https://github.com/stordco/kafee/issues/101)) ([0baeae8](https://github.com/stordco/kafee/commit/0baeae8d0bfef5ff33412287113275f8228b50ca))

## [3.1.2](https://github.com/stordco/kafee/compare/v3.1.1...v3.1.2) (2024-09-26)


### Bug Fixes

* Flaky test ([#104](https://github.com/stordco/kafee/issues/104)) ([ec5b2fb](https://github.com/stordco/kafee/commit/ec5b2fb51bc3c809adf313e77a4393c7e3e9b6e0))


### Miscellaneous

* Sync files with stordco/common-config-elixir ([#98](https://github.com/stordco/kafee/issues/98)) ([0ba2a00](https://github.com/stordco/kafee/commit/0ba2a003a4bd9fa7c60fee87e7178578568e2be7))

## [3.1.1](https://github.com/stordco/kafee/compare/v3.1.0...v3.1.1) (2024-09-23)


### Bug Fixes

* SIGNAL-7090 UPDATE async worker id setting per partition ([#97](https://github.com/stordco/kafee/issues/97)) ([060dbd7](https://github.com/stordco/kafee/commit/060dbd78534238a3de0f67d625ec9e0c821d0f95))

## [3.1.0](https://github.com/stordco/kafee/compare/v3.0.3...v3.1.0) (2024-09-19)


### Features

* SIGNAL-7060 filter out large messages during termination instead of sending to Kafka ([#95](https://github.com/stordco/kafee/issues/95)) ([3bf5f81](https://github.com/stordco/kafee/commit/3bf5f812e6ef87f9597646ed20ae7c751c01b255))


### Miscellaneous

* Sync files with stordco/common-config-elixir ([#85](https://github.com/stordco/kafee/issues/85)) ([c377a8e](https://github.com/stordco/kafee/commit/c377a8e6654d11557d5ccb8d1b750f2c3d1614c4))
* Sync files with stordco/common-config-elixir ([#87](https://github.com/stordco/kafee/issues/87)) ([5dcc51d](https://github.com/stordco/kafee/commit/5dcc51d9392a32cf2b33d23cb31b45541ecc4909))
* Sync files with stordco/common-config-elixir ([#88](https://github.com/stordco/kafee/issues/88)) ([51f6add](https://github.com/stordco/kafee/commit/51f6adddc5fdcb7e01d402fff910a7ee708813b6))
* Sync files with stordco/common-config-elixir ([#89](https://github.com/stordco/kafee/issues/89)) ([f6b8668](https://github.com/stordco/kafee/commit/f6b8668ecd9bc0d2e99ec640f98a86545746cbc8))
* Sync files with stordco/common-config-elixir ([#90](https://github.com/stordco/kafee/issues/90)) ([ba97bf3](https://github.com/stordco/kafee/commit/ba97bf3cb2398430dfa473deca181f669802832b))
* Sync files with stordco/common-config-elixir ([#91](https://github.com/stordco/kafee/issues/91)) ([2c013fe](https://github.com/stordco/kafee/commit/2c013fe7efe1b67e1030b4727a0f5ad6b5933e9b))
* Sync files with stordco/common-config-elixir ([#92](https://github.com/stordco/kafee/issues/92)) ([5da1a94](https://github.com/stordco/kafee/commit/5da1a9468c198d1866030fab03cbb50a152d399a))
* Sync files with stordco/common-config-elixir ([#94](https://github.com/stordco/kafee/issues/94)) ([33ed4d8](https://github.com/stordco/kafee/commit/33ed4d8c2bc757cd2ef5e5bffe656418be13d588))

## [3.0.3](https://github.com/stordco/kafee/compare/v3.0.2...v3.0.3) (2024-03-08)


### Bug Fixes

* Return `:commit` since `:ack` does not commit in v2 ([#84](https://github.com/stordco/kafee/issues/84)) ([15bd941](https://github.com/stordco/kafee/commit/15bd941136f386acd63115cc7264af17fc01854f))


### Miscellaneous

* PR template and checklist ([#82](https://github.com/stordco/kafee/issues/82)) ([ed71ff8](https://github.com/stordco/kafee/commit/ed71ff83a51670c1a971b0a5b1d08b2cdcba2d79))
* Sync files with stordco/common-config-elixir ([#76](https://github.com/stordco/kafee/issues/76)) ([b23560e](https://github.com/stordco/kafee/commit/b23560ef9836acd5c3792568dfd4042cfbf0649a))
* Sync files with stordco/common-config-elixir ([#81](https://github.com/stordco/kafee/issues/81)) ([58aba7b](https://github.com/stordco/kafee/commit/58aba7bf9da506316e37bed68dbb36bb489b302d))
* Update readme info about producer testing ([#73](https://github.com/stordco/kafee/issues/73)) ([00b633a](https://github.com/stordco/kafee/commit/00b633a5d7121cdfd913dd96797883c33e8f67a0))

## [3.0.2](https://github.com/stordco/kafee/compare/v3.0.1...v3.0.2) (2023-12-26)


### Bug Fixes

* Update tuple types for sasl option ([#78](https://github.com/stordco/kafee/issues/78)) ([2860d8b](https://github.com/stordco/kafee/commit/2860d8bc0cf4eb8796545db69b6765f0fc2e0b22))


### Miscellaneous

* Set main branch for release please ([c8764b0](https://github.com/stordco/kafee/commit/c8764b0dc05fac56b1c596a4350f1287c3e1e45a))

## [3.0.1](https://github.com/stordco/kafee/compare/v3.0.0...v3.0.1) (2023-11-22)


### Bug Fixes

* Update dialyzer types for producer module ([#74](https://github.com/stordco/kafee/issues/74)) ([f1fa928](https://github.com/stordco/kafee/commit/f1fa9288d9be4a38320793614966ea59a238541c))

## [3.0.0](https://github.com/stordco/kafee/compare/v2.6.2...v3.0.0) (2023-11-05)


### ⚠ BREAKING CHANGES

* `Kafee.Producer` configuration is done differently to match how `Kafee.Consumer` works.
* the use of "backend" has been renamed to "adapter"
* `Kafee.Testing` is now reworked to `Kafee.Test`

### Features

* [SRE-515] use testing pid for better kafka produce testing ([#58](https://github.com/stordco/kafee/issues/58)) ([cae7bce](https://github.com/stordco/kafee/commit/cae7bce4679761deace2d5ed14c064957284ab98))
* [SRE-517] create a consumer module ([#63](https://github.com/stordco/kafee/issues/63)) ([d012734](https://github.com/stordco/kafee/commit/d01273421389f72a74a48b47ddaacdb2569e81f8))
* [SRE-518] setup encoder decoder modules ([#62](https://github.com/stordco/kafee/issues/62)) ([b494049](https://github.com/stordco/kafee/commit/b494049ab18fba18ebeb8ce1e803d7c087bc8e5e))
* Integrate data-streams into kafee producer ([#52](https://github.com/stordco/kafee/issues/52)) ([ffdd5da](https://github.com/stordco/kafee/commit/ffdd5da9a09b47333d3d67267addd4ce8f1f9d1b))
* Update producer to match consumer style ([#70](https://github.com/stordco/kafee/issues/70)) ([39fc85a](https://github.com/stordco/kafee/commit/39fc85a19caac9b906a95a403dbb95c5e71a3cf5))


### Bug Fixes

* Fix consumer directory name typo ([#71](https://github.com/stordco/kafee/issues/71)) ([44de1d6](https://github.com/stordco/kafee/commit/44de1d6a139339dc8e26887733424422844c037a))


### Miscellaneous

* **deps:** Update outdated dependencies ([#59](https://github.com/stordco/kafee/issues/59)) ([5439acb](https://github.com/stordco/kafee/commit/5439acbc08ada73687d03128b0780059fa9a2370))
* **main:** Release 3.0.0 ([#60](https://github.com/stordco/kafee/issues/60)) ([3c1b238](https://github.com/stordco/kafee/commit/3c1b2387f9b8eb35ab9e81983da2c9ad8c1231f5))
* Sync files with stordco/common-config-elixir ([#72](https://github.com/stordco/kafee/issues/72)) ([2d458ba](https://github.com/stordco/kafee/commit/2d458ba5b2ed73eb9ba0a9b178f3986a95302e2a))
* Update backend copy to adapter to align with Elixir more ([#69](https://github.com/stordco/kafee/issues/69)) ([1c2da6b](https://github.com/stordco/kafee/commit/1c2da6b8cc4a5b3ab5ebf4fdb09467c571170949))
* Update codeowners ([#61](https://github.com/stordco/kafee/issues/61)) ([10f0290](https://github.com/stordco/kafee/commit/10f029031b9235d8cf3041d98b4f312c8ececd2b))
* Update codeowners ([#65](https://github.com/stordco/kafee/issues/65)) ([e352bc6](https://github.com/stordco/kafee/commit/e352bc6d18eb53f9448c373ecb2c846df7460f40))
* Update README code examples ([#64](https://github.com/stordco/kafee/issues/64)) ([50bed75](https://github.com/stordco/kafee/commit/50bed7537cf18d217eb33d7b767e54bdb63a0dc3))

## [2.6.2](https://github.com/stordco/kafee/compare/v2.6.1...v2.6.2) (2023-09-28)


### Bug Fixes

* Update CI to include kafka service ([#57](https://github.com/stordco/kafee/issues/57)) ([d297248](https://github.com/stordco/kafee/commit/d2972489ffccc9c196073061e410a9538bfd37b2))


### Miscellaneous

* Add common-config-elixir workflow ([#53](https://github.com/stordco/kafee/issues/53)) ([4771f6f](https://github.com/stordco/kafee/commit/4771f6f5194a048477ff59bf28b21f1c8c817811))
* Sync files with stordco/common-config-elixir ([#54](https://github.com/stordco/kafee/issues/54)) ([5753ed7](https://github.com/stordco/kafee/commit/5753ed7cac42823ed02e05c4dceb59ee91079537))
* Sync files with stordco/common-config-elixir ([#56](https://github.com/stordco/kafee/issues/56)) ([c283269](https://github.com/stordco/kafee/commit/c2832692183f31520ac474687e84545ce3509e1f))

## [2.6.1](https://github.com/stordco/kafee/compare/v2.6.0...v2.6.1) (2023-05-24)


### Bug Fixes

* add edge case testing around large messages ([#49](https://github.com/stordco/kafee/issues/49)) ([cb79607](https://github.com/stordco/kafee/commit/cb79607825cc7eb7630087e0bc3db7d6b910a0d1))

## [2.6.0](https://github.com/stordco/kafee/compare/v2.5.0...v2.6.0) (2023-05-08)


### Features

* allow configurable max request size for async worker ([#46](https://github.com/stordco/kafee/issues/46)) ([7ae4738](https://github.com/stordco/kafee/commit/7ae473809ee9848e212bc07353ebd4e3c99461fe))


### Bug Fixes

* handle not retriable error cases ([#48](https://github.com/stordco/kafee/issues/48)) ([84f8807](https://github.com/stordco/kafee/commit/84f88078b46e988c08f201805965963523ee351d))

## [2.5.0](https://github.com/stordco/kafee/compare/v2.4.0...v2.5.0) (2023-04-04)


### Features

* remove send_interval references, document new async worker options ([#44](https://github.com/stordco/kafee/issues/44)) ([3811516](https://github.com/stordco/kafee/commit/3811516431ac15d7b839e034ba8fbc7c843e7839))
* use new async queue system for faster sending ([#41](https://github.com/stordco/kafee/issues/41)) ([9f9e105](https://github.com/stordco/kafee/commit/9f9e105b63fef4fd36326f6760977e0e3a69ed2c))

## [2.4.0](https://github.com/stordco/kafee/compare/v2.3.1...v2.4.0) (2023-03-17)


### Features

* refute_producer_message/2 ([#39](https://github.com/stordco/kafee/issues/39)) ([a322541](https://github.com/stordco/kafee/commit/a3225416c12bfe9e24edd5e1d3fe825cc54013b0))

## [2.3.1](https://github.com/stordco/kafee/compare/v2.3.0...v2.3.1) (2023-03-10)


### Bug Fixes

* send whole message with sync_backend ([#37](https://github.com/stordco/kafee/issues/37)) ([1dde3fb](https://github.com/stordco/kafee/commit/1dde3fbd801bda4b4ce45babff6331c999df68d6))

## [2.3.0](https://github.com/stordco/kafee/compare/v2.2.3...v2.3.0) (2023-02-08)


### Features

* add header binary validation before producing message ([#34](https://github.com/stordco/kafee/issues/34)) ([5d217a7](https://github.com/stordco/kafee/commit/5d217a744d050e70178ea5f040f77d5a73b4e200))

## [2.2.3](https://github.com/stordco/kafee/compare/v2.2.2...v2.2.3) (2023-02-06)


### Bug Fixes

* remove extra error log statement ([e4dab28](https://github.com/stordco/kafee/commit/e4dab28f520eb4eb9a9e18a0e03702810ce72f69))

## [2.2.2](https://github.com/stordco/kafee/compare/v2.2.1...v2.2.2) (2023-01-31)


### Bug Fixes

* update telemetry error kind to struct name ([#31](https://github.com/stordco/kafee/issues/31)) ([4ee2cb2](https://github.com/stordco/kafee/commit/4ee2cb2004c339d2565ba4c6f98ba373caacc15d))

## [2.2.1](https://github.com/stordco/kafee/compare/v2.2.0...v2.2.1) (2023-01-27)


### Bug Fixes

* ArgumentError from Kafee.Producer.AsyncWorker ([3e405ba](https://github.com/stordco/kafee/commit/3e405ba89fa91c306d9897a31e8fbff3bee7279a))

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
