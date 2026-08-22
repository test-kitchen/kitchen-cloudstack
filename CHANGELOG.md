# kitchen-cloudstack Changelog

## 1.0.0

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
