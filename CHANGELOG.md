# Changelog

## [4.0.0](https://github.com/stordco/kafee/compare/v3.0.0...v4.0.0) (2023-10-12)


### ⚠ BREAKING CHANGES

* `Kafee.Testing` is now reworked to `Kafee.Test`
* add async producer ([#10](https://github.com/stordco/kafee/issues/10))
* rename module to Kafee ([#5](https://github.com/stordco/kafee/issues/5))

### Features

* [SRE-515] use testing pid for better kafka produce testing ([#58](https://github.com/stordco/kafee/issues/58)) ([cae7bce](https://github.com/stordco/kafee/commit/cae7bce4679761deace2d5ed14c064957284ab98))
* [SRE-517] create a consumer module ([#63](https://github.com/stordco/kafee/issues/63)) ([d012734](https://github.com/stordco/kafee/commit/d01273421389f72a74a48b47ddaacdb2569e81f8))
* [SRE-518] setup encoder decoder modules ([#62](https://github.com/stordco/kafee/issues/62)) ([b494049](https://github.com/stordco/kafee/commit/b494049ab18fba18ebeb8ce1e803d7c087bc8e5e))
* [SRE-84] use stordco/actions-elixir/setup ([#8](https://github.com/stordco/kafee/issues/8)) ([33153a2](https://github.com/stordco/kafee/commit/33153a2324ecd25e5bdfd94b3b4cb181e68c8d3f))
* Add async producer ([#10](https://github.com/stordco/kafee/issues/10)) ([cab0aee](https://github.com/stordco/kafee/commit/cab0aee3d440be8389167af6031ec40ae32463f8))
* Add header binary validation before producing message ([#34](https://github.com/stordco/kafee/issues/34)) ([5d217a7](https://github.com/stordco/kafee/commit/5d217a744d050e70178ea5f040f77d5a73b4e200))
* Add more error handling around brod ([d5c1032](https://github.com/stordco/kafee/commit/d5c103284de4f187f8fda3958e07ba056812d4aa))
* Add synchronous producer module ([#4](https://github.com/stordco/kafee/issues/4)) ([d73e89d](https://github.com/stordco/kafee/commit/d73e89d950b0091bcffbfed1c2255c225f564ac4))
* Add telemetry events ([#29](https://github.com/stordco/kafee/issues/29)) ([d6aa690](https://github.com/stordco/kafee/commit/d6aa6904cd08b05ad23e00b4bdc7fe9e270da521))
* Allow configurable max request size for async worker ([#46](https://github.com/stordco/kafee/issues/46)) ([7ae4738](https://github.com/stordco/kafee/commit/7ae473809ee9848e212bc07353ebd4e3c99461fe))
* Allow messages to be json encoded ([cdbb269](https://github.com/stordco/kafee/commit/cdbb269d255fa9a777eeffd2dbaf6f229233adaf))
* Integrate data-streams into kafee producer ([#52](https://github.com/stordco/kafee/issues/52)) ([ffdd5da](https://github.com/stordco/kafee/commit/ffdd5da9a09b47333d3d67267addd4ce8f1f9d1b))
* Publish package to stord hex.pm org ([#3](https://github.com/stordco/kafee/issues/3)) ([e4b48d0](https://github.com/stordco/kafee/commit/e4b48d04f39e64a97e350d80cb09e6dd6ab93637))
* Refute_producer_message/2 ([#39](https://github.com/stordco/kafee/issues/39)) ([a322541](https://github.com/stordco/kafee/commit/a3225416c12bfe9e24edd5e1d3fe825cc54013b0))
* Remove send_interval references, document new async worker options ([#44](https://github.com/stordco/kafee/issues/44)) ([3811516](https://github.com/stordco/kafee/commit/3811516431ac15d7b839e034ba8fbc7c843e7839))
* Rename module to Kafee ([#5](https://github.com/stordco/kafee/issues/5)) ([7f88456](https://github.com/stordco/kafee/commit/7f88456c85b0cc80661a0b25607644d2fd94de67))
* Set retry metrics for sync producer ([#21](https://github.com/stordco/kafee/issues/21)) ([c2933c2](https://github.com/stordco/kafee/commit/c2933c2eb4fbeb05667997c4901156bfacbb1886))
* Simplify publishing ([d7f4533](https://github.com/stordco/kafee/commit/d7f4533e8bbcc5cb6dc9d50f2efc1af90b39f641))
* Use new async queue system for faster sending ([#41](https://github.com/stordco/kafee/issues/41)) ([9f9e105](https://github.com/stordco/kafee/commit/9f9e105b63fef4fd36326f6760977e0e3a69ed2c))


### Bug Fixes

* [SIGNAL-2969] handle already started error ([#19](https://github.com/stordco/kafee/issues/19)) ([c541aea](https://github.com/stordco/kafee/commit/c541aea24df827338803f307eee2cdd37cdbd711))
* Add edge case testing around large messages ([#49](https://github.com/stordco/kafee/issues/49)) ([cb79607](https://github.com/stordco/kafee/commit/cb79607825cc7eb7630087e0bc3db7d6b910a0d1))
* Add org to mix.exs package block ([117fa28](https://github.com/stordco/kafee/commit/117fa28f715dec0d548d15950d299dcda47fa1e5))
* ArgumentError from Kafee.Producer.AsyncWorker ([3e405ba](https://github.com/stordco/kafee/commit/3e405ba89fa91c306d9897a31e8fbff3bee7279a))
* Dont split the queue larger than the length ([#17](https://github.com/stordco/kafee/issues/17)) ([5b96b6a](https://github.com/stordco/kafee/commit/5b96b6abb99603f0578e15d4f8b0519e17b83828))
* Handle not retriable error cases ([#48](https://github.com/stordco/kafee/issues/48)) ([84f8807](https://github.com/stordco/kafee/commit/84f88078b46e988c08f201805965963523ee351d))
* Increase connect timeout to 10 seconds ([#15](https://github.com/stordco/kafee/issues/15)) ([e572d7e](https://github.com/stordco/kafee/commit/e572d7ecd12eb67cbd5956783853f71c9a99eefe))
* Increase default connection timeout ([#13](https://github.com/stordco/kafee/issues/13)) ([a1a18ec](https://github.com/stordco/kafee/commit/a1a18ecded32194c737fc9a60b4148f3b1858a0e))
* More debugging around async worker ([#27](https://github.com/stordco/kafee/issues/27)) ([62c10d7](https://github.com/stordco/kafee/commit/62c10d76f3ef9ace39e5f526dc28a62c0fddd12f))
* Publish formatter file ([05de560](https://github.com/stordco/kafee/commit/05de56017c18ce359fe09322eebe82f153201aab))
* Remove extra error log statement ([e4dab28](https://github.com/stordco/kafee/commit/e4dab28f520eb4eb9a9e18a0e03702810ce72f69))
* Run brod config init function to fix sasl auth ([#11](https://github.com/stordco/kafee/issues/11)) ([f35e791](https://github.com/stordco/kafee/commit/f35e791c614afae37848d714fc04ad1f04e52b9f))
* Send whole message with sync_backend ([#37](https://github.com/stordco/kafee/issues/37)) ([1dde3fb](https://github.com/stordco/kafee/commit/1dde3fbd801bda4b4ce45babff6331c999df68d6))
* Update brod client name to avoid process collision ([#1](https://github.com/stordco/kafee/issues/1)) ([905c897](https://github.com/stordco/kafee/commit/905c897e4904416f1128b790ef9b372fdc3a14d8))
* Update CI tests to run on ubuntu 20.04 for old OTP releases ([#25](https://github.com/stordco/kafee/issues/25)) ([48c78f7](https://github.com/stordco/kafee/commit/48c78f77b4ae0ded1a4b7ece868e8bf76cc0bb19))
* Update CI to include kafka service ([#57](https://github.com/stordco/kafee/issues/57)) ([d297248](https://github.com/stordco/kafee/commit/d2972489ffccc9c196073061e410a9538bfd37b2))
* Update dialyzer to pass jason encoding ([80265dd](https://github.com/stordco/kafee/commit/80265ddd09706fbbf23597e79601e2cab62a73dc))
* Update gha workflows for automated releases ([e2b12b3](https://github.com/stordco/kafee/commit/e2b12b38f31928f131f347868cb6b6da08f6f53d))
* Update README to always show current version in code blocks ([f59f4d6](https://github.com/stordco/kafee/commit/f59f4d6bf541e79e7683941f24bf55ab3eb57d5c))
* Update telemetry error kind to struct name ([#31](https://github.com/stordco/kafee/issues/31)) ([4ee2cb2](https://github.com/stordco/kafee/commit/4ee2cb2004c339d2565ba4c6f98ba373caacc15d))
* Update urls with real hex.pm and hexdocs.pm urls ([618383e](https://github.com/stordco/kafee/commit/618383eb99be359fcf09893f32fc858b9f0d9e3e))


### Miscellaneous

* Add common-config-elixir workflow ([#53](https://github.com/stordco/kafee/issues/53)) ([4771f6f](https://github.com/stordco/kafee/commit/4771f6f5194a048477ff59bf28b21f1c8c817811))
* **ci:** Setup ci and cd with GitHub actions ([cf378ef](https://github.com/stordco/kafee/commit/cf378eff0c4e518aecdf479675f2141b977b6e45))
* **deps:** Update outdated dependencies ([#59](https://github.com/stordco/kafee/issues/59)) ([5439acb](https://github.com/stordco/kafee/commit/5439acbc08ada73687d03128b0780059fa9a2370))
* **main:** Release 1.0.0 ([#4](https://github.com/stordco/kafee/issues/4)) ([1c0bea9](https://github.com/stordco/kafee/commit/1c0bea98d1fcb426ea10b635fad28e2373632794))
* **main:** Release 1.0.1 ([#5](https://github.com/stordco/kafee/issues/5)) ([afdb3b3](https://github.com/stordco/kafee/commit/afdb3b3cdae034f97ede69c648c6a6b50ed68d0e))
* **main:** Release 1.0.2 ([#6](https://github.com/stordco/kafee/issues/6)) ([616e066](https://github.com/stordco/kafee/commit/616e066bbe961288937178971166f8a163116614))
* **main:** Release 1.0.3 ([#7](https://github.com/stordco/kafee/issues/7)) ([b045bd3](https://github.com/stordco/kafee/commit/b045bd368e090ba32e89200f584f4ba4d614bd13))
* **main:** Release 2.0.0 ([#9](https://github.com/stordco/kafee/issues/9)) ([0e6881c](https://github.com/stordco/kafee/commit/0e6881c7015eff31782a6acd146c8fec7fa23cf9))
* **main:** Release 2.0.1 ([#12](https://github.com/stordco/kafee/issues/12)) ([c418af1](https://github.com/stordco/kafee/commit/c418af1b6c068f06d268edce27fd97474e44d3ff))
* **main:** Release 2.0.2 ([#14](https://github.com/stordco/kafee/issues/14)) ([d0b711e](https://github.com/stordco/kafee/commit/d0b711efc2cff856f6c1ff18ee77bc0844bccf64))
* **main:** Release 2.0.3 ([#16](https://github.com/stordco/kafee/issues/16)) ([fc97d58](https://github.com/stordco/kafee/commit/fc97d583c2f98a2eae36369795ccae41159db960))
* **main:** Release 2.0.4 ([#18](https://github.com/stordco/kafee/issues/18)) ([ceb188e](https://github.com/stordco/kafee/commit/ceb188eae1126db58ed05ca47a3b6891f02f1b75))
* **main:** Release 2.0.5 ([#20](https://github.com/stordco/kafee/issues/20)) ([b87c65e](https://github.com/stordco/kafee/commit/b87c65e12b3b6088ad8917f0eb5a21d8951404bb))
* **main:** Release 2.1.0 ([0e2364c](https://github.com/stordco/kafee/commit/0e2364cb4f8b576f340858ce3f50c21753dca504))
* **main:** Release 2.2.0 ([#28](https://github.com/stordco/kafee/issues/28)) ([533e6b8](https://github.com/stordco/kafee/commit/533e6b85829043ae3f81403c797459e385b90cd9))
* **main:** Release 2.2.1 ([#30](https://github.com/stordco/kafee/issues/30)) ([d7e8e01](https://github.com/stordco/kafee/commit/d7e8e010d477e2ca5e5f01f6f5b923664d2b19bd))
* **main:** Release 2.2.2 ([#32](https://github.com/stordco/kafee/issues/32)) ([8c3d3db](https://github.com/stordco/kafee/commit/8c3d3db00f2767957fc0f57cec68633d83418130))
* **main:** Release 2.2.3 ([#33](https://github.com/stordco/kafee/issues/33)) ([7acfd85](https://github.com/stordco/kafee/commit/7acfd85b16f581ffa64a7c35e932a05e8aae6503))
* **main:** Release 2.3.0 ([#35](https://github.com/stordco/kafee/issues/35)) ([5f88bcd](https://github.com/stordco/kafee/commit/5f88bcd7338d535a7d4113d9797303882f9ed06f))
* **main:** Release 2.3.1 ([#38](https://github.com/stordco/kafee/issues/38)) ([b6929af](https://github.com/stordco/kafee/commit/b6929afbf5cc1fbd9c2c2cc9a7c1027abc603d40))
* **main:** Release 2.4.0 ([#40](https://github.com/stordco/kafee/issues/40)) ([80c0db6](https://github.com/stordco/kafee/commit/80c0db68c29c98d7ac4d3e69c380bc33b55a7c81))
* **main:** Release 2.5.0 ([#43](https://github.com/stordco/kafee/issues/43)) ([34667db](https://github.com/stordco/kafee/commit/34667db47dc78760f33342d2b64678228381781a))
* **main:** Release 2.6.0 ([#47](https://github.com/stordco/kafee/issues/47)) ([8bd9960](https://github.com/stordco/kafee/commit/8bd9960a323519321e4968228738b90c85d4afb9))
* **main:** Release 2.6.1 ([#50](https://github.com/stordco/kafee/issues/50)) ([718a794](https://github.com/stordco/kafee/commit/718a794aa8a184ebe95ece5945811b29338009ce))
* **main:** Release 2.6.2 ([#55](https://github.com/stordco/kafee/issues/55)) ([577cedd](https://github.com/stordco/kafee/commit/577ceddb3dd52b3aa68f2596d5d03506db0b06a4))
* **main:** Release 3.0.0 ([#60](https://github.com/stordco/kafee/issues/60)) ([3c1b238](https://github.com/stordco/kafee/commit/3c1b2387f9b8eb35ab9e81983da2c9ad8c1231f5))
* Quiet logs during tests ([#22](https://github.com/stordco/kafee/issues/22)) ([6311f51](https://github.com/stordco/kafee/commit/6311f51bd76c1f0da7f0572a07d6bfc64868e3f0))
* Remove application supervisor ([baea667](https://github.com/stordco/kafee/commit/baea66722856a150bc564f7e9b9a776d1f73cbe5))
* Remove dead releaserc config file ([2dc2bfc](https://github.com/stordco/kafee/commit/2dc2bfc2bf65a0769521780b0eeaf13558dfc5fd))
* Sync files with stordco/common-config-elixir ([#54](https://github.com/stordco/kafee/issues/54)) ([5753ed7](https://github.com/stordco/kafee/commit/5753ed7cac42823ed02e05c4dceb59ee91079537))
* Sync files with stordco/common-config-elixir ([#56](https://github.com/stordco/kafee/issues/56)) ([c283269](https://github.com/stordco/kafee/commit/c2832692183f31520ac474687e84545ce3509e1f))
* **test:** Update kafee testing ([#42](https://github.com/stordco/kafee/issues/42)) ([a8d61f8](https://github.com/stordco/kafee/commit/a8d61f8f18e1db527d72491463b01a2a269aeb08))
* Update codeowners ([#45](https://github.com/stordco/kafee/issues/45)) ([b981d70](https://github.com/stordco/kafee/commit/b981d70d013ce16cdb5c4a5044bd31250f58267e))
* Update codeowners ([#61](https://github.com/stordco/kafee/issues/61)) ([10f0290](https://github.com/stordco/kafee/commit/10f029031b9235d8cf3041d98b4f312c8ececd2b))
* Update codeowners ([#65](https://github.com/stordco/kafee/issues/65)) ([e352bc6](https://github.com/stordco/kafee/commit/e352bc6d18eb53f9448c373ecb2c846df7460f40))
* Update codeowners to Core ([#24](https://github.com/stordco/kafee/issues/24)) ([07ce694](https://github.com/stordco/kafee/commit/07ce6946011dc0201e3895f126d8e6bea08615fb))
* Update contributing guide with new release workflow ([da2044d](https://github.com/stordco/kafee/commit/da2044d5466a620e5169fdeccc1a018f62022385))
* Update README code examples ([#64](https://github.com/stordco/kafee/issues/64)) ([50bed75](https://github.com/stordco/kafee/commit/50bed7537cf18d217eb33d7b767e54bdb63a0dc3))

## [3.0.0](https://github.com/stordco/kafee/compare/v2.6.2...v3.0.0) (2023-10-12)


### ⚠ BREAKING CHANGES

* `Kafee.Testing` is now reworked to `Kafee.Test`

### Features

* [SRE-515] use testing pid for better kafka produce testing ([#58](https://github.com/stordco/kafee/issues/58)) ([cae7bce](https://github.com/stordco/kafee/commit/cae7bce4679761deace2d5ed14c064957284ab98))
* [SRE-517] create a consumer module ([#63](https://github.com/stordco/kafee/issues/63)) ([d012734](https://github.com/stordco/kafee/commit/d01273421389f72a74a48b47ddaacdb2569e81f8))
* [SRE-518] setup encoder decoder modules ([#62](https://github.com/stordco/kafee/issues/62)) ([b494049](https://github.com/stordco/kafee/commit/b494049ab18fba18ebeb8ce1e803d7c087bc8e5e))
* Integrate data-streams into kafee producer ([#52](https://github.com/stordco/kafee/issues/52)) ([ffdd5da](https://github.com/stordco/kafee/commit/ffdd5da9a09b47333d3d67267addd4ce8f1f9d1b))


### Miscellaneous

* **deps:** Update outdated dependencies ([#59](https://github.com/stordco/kafee/issues/59)) ([5439acb](https://github.com/stordco/kafee/commit/5439acbc08ada73687d03128b0780059fa9a2370))
* Update codeowners ([#61](https://github.com/stordco/kafee/issues/61)) ([10f0290](https://github.com/stordco/kafee/commit/10f029031b9235d8cf3041d98b4f312c8ececd2b))
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
