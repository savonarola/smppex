# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](http://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [3.1.1] - 2023-06-03

- Drop support of old Elixir & OTP versions (OTP 24+ and Elixir 1.12+ are required).
- Remove some compatibility code.
- Update dependencies to latest minor versions.
- Update CI matrix.
- Improve SSL tests.
- Update maintenance status.
- Apply updated formatting.

## [3.0.6] - 2022-01-22

### Added
- Embedded mode for MC, i.e. a way to start it as a part of custom supervision tree ([sasa1977](https://github.com/sasa1977)).
- Optional `SMPP.Session` callback (`handle_timeout`) for customizing SMPP session
exit reason in case of timeouts ([sasa1977](https://github.com/sasa1977)).

## [3.0.5] - 2021-12-22

### Added
- Elixir 13 to CI matrix.
- OTP 24 to CI matrix.

### Changed
- Fixed some typing issues ([Fyodor Parmanchukov](https://github.com/rezerbit)).

## [3.0.4] - 2021-04-17

### Added
- Documentation of auxilary projects.

### Changed
- Organization of documents.

## [3.0.3] - 2021-04-16

### Added
- `session_module` option for MC and ESME modules to provide alternative implementations
of `SMPPEX.TransportSession` behavior.

## [3.0.2] - 2021-04-06

### Changed
- Removed `poison` from dev dependencies.

## [3.0.1] - 2020-12-13

### Changed
- Removed `poison` from production dependencies.

## [3.0.0] - 2020-12-13

### Changed
- Fixed callback flow while accepting connections in MC. `init` callbacks are now run
after socket transport handshake (as it always should have been).
- Updated Ranch to 2.0.
- Dropped OTP < 21 support for Ranch 2.0 compatibility.
- Fixed `source_subaddress` TLV spec ([Menkir](https://github.com/Menkir)).

## [2.4.0] - 2020-11-05

### Changed
- Fixed low level socket configuration in ESME ([IceDragon200](https://github.com/IceDragon200)).
- Updated dev/test dependency versions.
- Dropped Elixir < 1.7 support.

## [2.3.3] - 2020-09-09

### Changed
- Fixed submit_multi handling ([Menkir](https://github.com/Menkir)).
- Moved repo to [funbox](https://github.com/funbox) organization.
- Set the `esm_class` field for a delivery report pdu created by factory.

### Added
- Timeout argument to `Session.send_pdu/2` function.

## [2.3.2] - 2019-11-19

### Added

- Option to set arbitrary initial sequence number for SMPP sessions.

## [2.3.1] - 2019-09-19

### Added
- Elixir 1.9 builds in CI.
- Updated `excoveralls` dependency.
- Added `SMPPEX.Pdu.ValidityPeriod` module for dealing with `validity_period` PDU field.

### Removed
- Removed Elixir 1.2, 1.3 support and the corresponding builds from CI.

## [2.3.0] - 2019-04-08

### Added
- Elixir 1.8 builds in CI.

### Removed
- OTP 18 support.

### Changed
- Fixed `data_sm` packet syntax.

## [2.2.9] - 2018-11-22

### Changed
- Unfixed `ranch` from `< 1.6.0`, since its internal changes do not affect our code.

## [2.2.8] - 2018-11-11

### Changed
- Fixed automatic `enquire_link` sequence id generation.
- Fixed `ranch` to `< 1.6.0` due to its incompatible changes.

## [2.2.7] - 2018-06-08

### Added

- Parsing mudule for `network_error_code` field.
- `network_error_code` field support in `oserl` converter.

## [2.2.6] - 2018-06-05

### Added
- Handling of generic `GenServer` `call` and `cast` messages.

### Changed
- Fixed handling of PDUs with negative `send_pdu_result` status: they do not appear
in `handle_resp_timeout` callack anymore.

## [2.2.5] - 2018-05-23

### Added
- `submit_sm` factory methods with automatic TON/NPI detection.

### Changed
- Dropped Elixir 1.1.1 and OTP 17 support.
- Made `SMPPEX.ESME.Sync` be safe for making requestd from multiple processes.

## [2.2.4] - 2018-02-12

### Changed
- Updated build matrix for Travis CI. Removed assets for obsolete version builds.
- Updated build matrix for Travis CI. Added Elixir 1.6.
- Added explicit extract functions in SMPPEX.Pdu.Multipart.
- Fixed Ranch transport handling in SMPPEX.TransportSession, this fixes SSL transport support.

## [2.2.3] - 2017-09-21

### Changed
- SMPPEX.ESME.Sync: ignore successful send_pdu_result for syncronously sent PDUs.
- SMPPEX.ESME.Sync: exit with normal on socket close.

## [2.2.2] - 2017-09-21
### Changed
- Fixed handling socket close/error for SMPPEX.ESME.Sync

## [2.2.1] - 2017-09-11
### Changed
- Loosened `ranch` version requirements.

## [2.2.0] - 2017-09-10
### Changed
- Added strict response type for `terminate` callback. Also, `terminate` callback is now allowed to return some last pdus for sending.

## [2.1.0] - 2017-09-10
### Added
- Automatic handling of `enquire_link` and `enquire_link_resp` PDUs.

## [2.0.1] - 2017-09-02
### Changed
- `PduStorage` implementation to be OTP 17 compatible.

## [2.0.0] - 2017-08-30
This release contains significant architectural changes and API incompatibilities.

### Changed
- Added single `SMPPEX.Session` behavior instead of seperate `SMPPEX.ESME` and `SMPPEX.MC` behaviours.
- `SMPPEX.Session` callbacks are more `GenServer` compliant.
- Most of `SMPPEX.Session` callbacks are allowed to return stop indicating tuple.
- Most of `SMPPEX.Session` callbacks are allowed to return a list of PDUs to send.
- All methods interacting with `SMPPEX.Session` are synchronous.

### Added
- Elixir 1.5 builds in CI.

### Removed
- Usage of a separate process for ESME/MC connections.
- Usage of `ranch` supervisor of launching ESME connections.
- Special methods for sending PDU replies to ESME/MC in favor of `Pdu.as_reply_to/2` method.

## [1.0.1] - 2017-08-30
### Changed
- `ex_doc` updated to 1.x.


## [1.0.0] - 2017-08-30
This is the first stable release introduced from numerous 0.x.x versions. Although this library has been already used in production for quite a while, it's only purpose is to designate the divergence from 2.x.x branch.

### Added
- ESME functionality.
- MC functionality.
- Synchronous ESME client.
