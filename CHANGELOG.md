# kitchen-cloudstack Changelog

## [1.1.0](https://github.com/test-kitchen/kitchen-cloudstack/compare/v1.0.0...v1.1.0) (2026-08-24)


### Features

* implement the driver doctor hook ([#59](https://github.com/test-kitchen/kitchen-cloudstack/issues/59)) ([bf2c7ce](https://github.com/test-kitchen/kitchen-cloudstack/commit/bf2c7cedc5fb783d77c46f3dc388c89b4a3fad48))

## [1.0.0](https://github.com/test-kitchen/kitchen-cloudstack/compare/v0.24.0...v1.0.0) (2026-08-22)

### Bug Fixes

* bump tk dep to allow tk 4 ([#41](https://github.com/test-kitchen/kitchen-cloudstack/issues/41)) ([82383d0](https://github.com/test-kitchen/kitchen-cloudstack/commit/82383d08437662da3c6a6573b2fbaff8b47aba3c))


### Continuous Integration

* add release-please automation and cut 1.0.0 ([#47](https://github.com/test-kitchen/kitchen-cloudstack/issues/47)) ([fabac36](https://github.com/test-kitchen/kitchen-cloudstack/commit/fabac36aa2029adec217502498b28daf08a80958))

### Other Changes

* Initial commit - no code ([1ea643f](https://github.com/test-kitchen/kitchen-cloudstack/commit/1ea643f))
* README should now be mostly complete. ([314456f](https://github.com/test-kitchen/kitchen-cloudstack/commit/314456f))
* Initial code commit. ([8be8f29](https://github.com/test-kitchen/kitchen-cloudstack/commit/8be8f29))
* Functional code. Starts instances with config pulled from YAML. ([80e1c37](https://github.com/test-kitchen/kitchen-cloudstack/commit/80e1c37))
* Fully functional code. Starts instances with config pulled from YAML. Fixed issue where I was pulling some config options in the wrong order causing things to fail. ([08b7bb4](https://github.com/test-kitchen/kitchen-cloudstack/commit/08b7bb4))
* Changed the default authentication mechanism to the CloudStack keys if specified, then failing back to password if available. ([890f33b](https://github.com/test-kitchen/kitchen-cloudstack/commit/890f33b))
* Added configurable sync time for cloud-set-guest-sshkey/password Changed default behavior to use private keys if specified before passwords. Added method to search for .PEM file in the current working directory, ~, and ~/.ssh/ ([9341cf1](https://github.com/test-kitchen/kitchen-cloudstack/commit/9341cf1))
* Updated docs to reflect changes. ([3a7a5c2](https://github.com/test-kitchen/kitchen-cloudstack/commit/3a7a5c2))
* Changed "SSH Key" to "keypair" to be more consistent with CloudStack terminology. ([270e4b0](https://github.com/test-kitchen/kitchen-cloudstack/commit/270e4b0))
* Provided mechanism to failback to password if keypair PEM is not available ([8012223](https://github.com/test-kitchen/kitchen-cloudstack/commit/8012223))
* Gem version bump. ([e9a9510](https://github.com/test-kitchen/kitchen-cloudstack/commit/e9a9510))
* Fixing password based key installation if a key is specified but file not present. ([56472e4](https://github.com/test-kitchen/kitchen-cloudstack/commit/56472e4))
* Fixing password based key installation if a key is specified but file not present...as well as the keypair based installation I broke with my last commit. ([81a1fd7](https://github.com/test-kitchen/kitchen-cloudstack/commit/81a1fd7))
* VM creation has been tested in all iterations of template configuration and config file configuration regarding authentication (password enabled on/off with or without keypairs specified as well as if the keypair file exists). ([38495b5](https://github.com/test-kitchen/kitchen-cloudstack/commit/38495b5))
* Added user-configurable search path for keys. ([66c2042](https://github.com/test-kitchen/kitchen-cloudstack/commit/66c2042))
* Updated gemspec to support latest test-kitchen release ([69e12a0](https://github.com/test-kitchen/kitchen-cloudstack/commit/69e12a0))
* Fixed bug with specifying network ids. ([d40f0d7](https://github.com/test-kitchen/kitchen-cloudstack/commit/d40f0d7))
* Removed requirement that appeared necessary in debugging and instead seems to be a fog dependency. ([fac6dd4](https://github.com/test-kitchen/kitchen-cloudstack/commit/fac6dd4))
* Adding some additional rescues. ([cc8631a](https://github.com/test-kitchen/kitchen-cloudstack/commit/cc8631a))
* Adding some additional debugging and validation of system availability. ([335403d](https://github.com/test-kitchen/kitchen-cloudstack/commit/335403d))
* Added name generator taken from kitchen-openstack. ([85adb04](https://github.com/test-kitchen/kitchen-cloudstack/commit/85adb04))
* Updated README and GemSpec to use the new URL. ([4565ef8](https://github.com/test-kitchen/kitchen-cloudstack/commit/4565ef8))
* Support advanced networking public ip if a mapping is done manually. ([#2](https://github.com/test-kitchen/kitchen-cloudstack/pull/2)) ([6ca0fbc](https://github.com/test-kitchen/kitchen-cloudstack/commit/6ca0fbc))
* changed the mechanisms for testing SSH connectivity. ([7d7ca9b](https://github.com/test-kitchen/kitchen-cloudstack/commit/7d7ca9b))
* Updated to support Fog 1.23.0 ([9ca6ac3](https://github.com/test-kitchen/kitchen-cloudstack/commit/9ca6ac3))
* Merge branch 'master' of github.com:test-kitchen/kitchen-cloudstack ([e509290](https://github.com/test-kitchen/kitchen-cloudstack/commit/e509290))
* Additional debug info ([1bed586](https://github.com/test-kitchen/kitchen-cloudstack/commit/1bed586))
* Even more debugging. ([743ddd2](https://github.com/test-kitchen/kitchen-cloudstack/commit/743ddd2))
* Use options hash for mandatory arguments for deploy_virtual_machine ([#7](https://github.com/test-kitchen/kitchen-cloudstack/pull/7)) ([e237869](https://github.com/test-kitchen/kitchen-cloudstack/commit/e237869))
* Update to use hashes for options and fix some behavoral changes in the next version of Fog. ([baff7e3](https://github.com/test-kitchen/kitchen-cloudstack/commit/baff7e3))
* Allow specifying a password for existing user on a template ([#10](https://github.com/test-kitchen/kitchen-cloudstack/pull/10)) ([e2c7af2](https://github.com/test-kitchen/kitchen-cloudstack/commit/e2c7af2))
* Finally fixing the bug where VM destruction wasn't working. ([a8fe76d](https://github.com/test-kitchen/kitchen-cloudstack/commit/a8fe76d))
* Fail when server does not start ([#8](https://github.com/test-kitchen/kitchen-cloudstack/pull/8)) ([227e612](https://github.com/test-kitchen/kitchen-cloudstack/commit/227e612))
* Moved the wait_for_sshd inside the keypair/password/fixed password logic ([#12](https://github.com/test-kitchen/kitchen-cloudstack/pull/12)) ([7817e8b](https://github.com/test-kitchen/kitchen-cloudstack/commit/7817e8b))
* Removes the default 45s sleep ([#13](https://github.com/test-kitchen/kitchen-cloudstack/pull/13)) ([8467398](https://github.com/test-kitchen/kitchen-cloudstack/commit/8467398))
* Bumping version to release updated gem ([fd8af44](https://github.com/test-kitchen/kitchen-cloudstack/commit/fd8af44))
* Disk Offering ID Support ([#15](https://github.com/test-kitchen/kitchen-cloudstack/pull/15)) ([a404c42](https://github.com/test-kitchen/kitchen-cloudstack/commit/a404c42))
* Hostname setting ([#16](https://github.com/test-kitchen/kitchen-cloudstack/pull/16)) ([e1680f9](https://github.com/test-kitchen/kitchen-cloudstack/commit/e1680f9))
* Makes it possible to expunge instances when destroying. ([#17](https://github.com/test-kitchen/kitchen-cloudstack/pull/17)) ([75be2ea](https://github.com/test-kitchen/kitchen-cloudstack/commit/75be2ea))
* add support for projectid and userdata ([#18](https://github.com/test-kitchen/kitchen-cloudstack/pull/18)) ([c8e2e81](https://github.com/test-kitchen/kitchen-cloudstack/commit/c8e2e81))
* support for associating public ip ([#20](https://github.com/test-kitchen/kitchen-cloudstack/pull/20)) ([49bc35d](https://github.com/test-kitchen/kitchen-cloudstack/commit/49bc35d))
* Make sure Etc.getlogin is not nil before reading its length ([#21](https://github.com/test-kitchen/kitchen-cloudstack/pull/21)) ([d37882e](https://github.com/test-kitchen/kitchen-cloudstack/commit/d37882e))
* Loosen the Test Kitchen + dev deps ([#23](https://github.com/test-kitchen/kitchen-cloudstack/pull/23)) ([ab4fd77](https://github.com/test-kitchen/kitchen-cloudstack/commit/ab4fd77))
* Add option to automatically create SSH firewall rule ([#22](https://github.com/test-kitchen/kitchen-cloudstack/pull/22)) ([4717020](https://github.com/test-kitchen/kitchen-cloudstack/commit/4717020))
* Pass Network ID when associating public IP address ([#24](https://github.com/test-kitchen/kitchen-cloudstack/pull/24)) ([562c0b1](https://github.com/test-kitchen/kitchen-cloudstack/commit/562c0b1))
* Added additional options ([#25](https://github.com/test-kitchen/kitchen-cloudstack/pull/25)) ([3196156](https://github.com/test-kitchen/kitchen-cloudstack/commit/3196156))
* Replaced fog dependency with fog-cloudstack. ([#26](https://github.com/test-kitchen/kitchen-cloudstack/pull/26)) ([703fb08](https://github.com/test-kitchen/kitchen-cloudstack/commit/703fb08))
* Update cane requirement from ~&gt; 2 to ~&gt; 3 ([#27](https://github.com/test-kitchen/kitchen-cloudstack/pull/27)) ([6675ae4](https://github.com/test-kitchen/kitchen-cloudstack/commit/6675ae4))
* Optimize our requires ([#28](https://github.com/test-kitchen/kitchen-cloudstack/pull/28)) ([7b663a3](https://github.com/test-kitchen/kitchen-cloudstack/commit/7b663a3))
* Setup testing with GitHub Actions ([#29](https://github.com/test-kitchen/kitchen-cloudstack/pull/29)) ([90fb8bd](https://github.com/test-kitchen/kitchen-cloudstack/commit/90fb8bd))
* Upgrade to GitHub-native Dependabot ([#30](https://github.com/test-kitchen/kitchen-cloudstack/pull/30)) ([271d278](https://github.com/test-kitchen/kitchen-cloudstack/commit/271d278))
* Configure Renovate ([#34](https://github.com/test-kitchen/kitchen-cloudstack/pull/34)) ([5cefeab](https://github.com/test-kitchen/kitchen-cloudstack/commit/5cefeab))
* Update actions/checkout action to v4 ([#37](https://github.com/test-kitchen/kitchen-cloudstack/pull/37)) ([d6a7fb6](https://github.com/test-kitchen/kitchen-cloudstack/commit/d6a7fb6))
* chore(deps): update actions/checkout action to v6 ([#40](https://github.com/test-kitchen/kitchen-cloudstack/pull/40)) ([2559de5](https://github.com/test-kitchen/kitchen-cloudstack/commit/2559de5))
* Fix typos ([#43](https://github.com/test-kitchen/kitchen-cloudstack/pull/43)) ([436308c](https://github.com/test-kitchen/kitchen-cloudstack/commit/436308c))
* Update actions/checkout action to v7 ([#42](https://github.com/test-kitchen/kitchen-cloudstack/pull/42)) ([cde61dd](https://github.com/test-kitchen/kitchen-cloudstack/commit/cde61dd))
* Docs: rewrite README for new users and split contributor docs ([#45](https://github.com/test-kitchen/kitchen-cloudstack/pull/45)) ([1fcd96d](https://github.com/test-kitchen/kitchen-cloudstack/commit/1fcd96d))
* Require Ruby 3.1+ and modernize CI ([#44](https://github.com/test-kitchen/kitchen-cloudstack/pull/44)) ([0ea4f63](https://github.com/test-kitchen/kitchen-cloudstack/commit/0ea4f63))
* Rewrite the driver for modern Test Kitchen ([#46](https://github.com/test-kitchen/kitchen-cloudstack/pull/46)) ([38e5a2d](https://github.com/test-kitchen/kitchen-cloudstack/commit/38e5a2d))
* docs: bring CONTRIBUTING up to date and tidy dead config ([#48](https://github.com/test-kitchen/kitchen-cloudstack/pull/48)) ([430f728](https://github.com/test-kitchen/kitchen-cloudstack/commit/430f728))
* Standardize renovate configuration ([#55](https://github.com/test-kitchen/kitchen-cloudstack/pull/55)) ([cc6b4f8](https://github.com/test-kitchen/kitchen-cloudstack/commit/cc6b4f8))


### Modern Test Kitchen support

The driver was built on `Kitchen::Driver::SSHBase`, which Test Kitchen removed
in 4.0, so the gem installed successfully and then failed to load with a
`NameError`. It is now built on `Kitchen::Driver::Base` and the transport API,
and works with current Test Kitchen, Cinc Workstation and Chef Workstation.

The driver no longer opens its own SSH connections. It determines an address and
credentials, puts them into instance state, and lets the configured transport
connect.

### Windows and WinRM

Setting `transport: name: winrm` is now enough to build Windows instances. Port
forwarding and firewall rules follow the transport's port (5985/5986 rather than
22), and the password CloudStack generates for a password-enabled template is
handed to WinRM automatically.

### `kitchen list` reports real instance state

The driver implements `status`, so Test Kitchen reports state from CloudStack
rather than assuming. An instance destroyed outside Test Kitchen is now
reported accurately.

### Breaking changes

- Requires `test-kitchen >= 3.0`.
- The driver no longer copies `~/.ssh/id_rsa.pub` into every instance's
  `authorized_keys`. It was a workaround for the old SSH handling; the transport
  is now given real credentials instead. If you relied on it, add the key
  through `cloudstack_userdata` or a CloudStack keypair.
- `username` and `port` are no longer defaulted to `root` and `22` by the
  driver. Set on the driver they behave as before; left unset, your `transport:`
  configuration now applies instead of being silently overridden.
- The `name` driver option has been removed. It never had any effect — the
  driver set it but read `server_name` when deploying.

### Bug fixes

- Asynchronous CloudStack jobs are now polled to completion consistently. Four
  of the six job checks tested `jobstatus == 0`, treating "still running" as
  success and logging an error on the successful result, so failures to create
  port forwarding rules, firewall rules, and to release public addresses were
  silently ignored.
- Fixed the rescue clauses in teardown, which referenced
  `Fog::Compute::Cloudstack::BadRequest`. No such constant exists — it is
  `Fog::Cloudstack::Compute::BadRequest` — so an error during teardown raised
  `NameError` from the rescue itself instead of being handled.
- Fixed an infinite loop in instance name generation. The truncation loop ran
  until the name fit in 64 characters, but each branch stopped shortening at a
  floor totalling 67 characters, so a login longer than 16 characters hung
  `kitchen create` forever.
- Fixed a `NameError` in `associate_public_ip` when address allocation failed,
  where the return value was only assigned on the success path.
- Job ids are now passed to fog as strings rather than hashes. Fog mutates a
  hash argument in place, which the old code worked around by re-cloning the
  hash on every poll.

### Other

- Added `cloudstack_firewall_cidr` to narrow the firewall rule's source range,
  which was previously always `0.0.0.0/0`.
- Added `cloudstack_job_poll_interval` and `cloudstack_job_timeout`. CloudStack
  jobs previously polled forever with no timeout.
- Added an RSpec suite. The gem previously had no tests.

## 0.24.0 and earlier

See the [commit history](https://github.com/test-kitchen/kitchen-cloudstack/commits/main).
