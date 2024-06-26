# CHANGELOG

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.0.0] - 2024-01-30

This is the first documented and supported implementation. It contains some main points:

### Added

#### 1. Limit Ask
- bond/limit_ask: Add `Buy`, `Utils`
- validators: 
  Add `limit_ask.ak` with `Update`, `Buy` redeemer

#### 2. Limit Bid
- bond/limit_bid: Add `Sell`, `Utils`
- validators: 
  Add `limit_bid.ak` with `Update`, `Sell` redeemer

#### 3. Making Ask
- bond/making_ask: Add `Buy`, `Utils`
- validators: 
  Add `making_ask.ak` with `Update`, `Buy` redeemer

#### 4. Making Bid
- bond/making_bid: Add `Sell`, `Utils`
- validators: 
  Add `making_bid.ak` with `Update`, `Sell` redeemer

All future Changelog entries will reference this base

[unreleased]: https://github.com/danogo2023/bond-dex/compare/v1.0.1...HEAD
[2.0.0]: https://github.com/danogo2023/bond-dex/compare/v2.0.0...v1.0.1
[1.0.1]: https://github.com/danogo2023/bond-dex/compare/v1.0.1...v1.0.0
