# Danogo Bonds Exchange

## Prerequisites

For now you'll need:
- rust installed, see [rustup](https://rustup.rs).

Run command:
```
cargo install aiken --version 1.0.3-alpha --root ./
or
cargo install --git https://github.com/aiken-lang/aiken.git --root ./
```
If not install direnv pls run command:
```
export PATH=$PWD/bin:$PATH
```

## Building

```sh
aiken build
```

## Testing

To run all tests, simply do:

```sh
aiken check
```

To run only tests matching the string `bond/validation_listing_test`, do:

```sh
aiken check -m bond/validation_listing_test
```

## Resources

Find more on the [Aiken's user manual](https://aiken-lang.org).

## Licensing

The primary license for Danogo V1 Core is the 
Business Source License 1.1 (`BUSL-1.1`), see [`LICENSE`](./LICENSE).
