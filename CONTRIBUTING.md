# Contributing to kitchen-cloudstack

Thanks for your interest in improving kitchen-cloudstack. Bug reports, feature requests, and pull requests are all welcome.

## The most valuable contribution right now

The driver subclasses `Kitchen::Driver::SSHBase`, which was removed in Test
Kitchen 4.0. That means the driver cannot be used with a current Test Kitchen,
including the one bundled in Cinc Workstation and Chef Workstation, and users
have to pin `test-kitchen < 4.0`.

Porting the driver onto the modern driver and transport API — as
[kitchen-rackspace](https://github.com/test-kitchen/kitchen-rackspace) did —
would be the single most useful change to this repository.

## Reporting issues

Report bugs and request features on the [issue tracker](https://github.com/test-kitchen/kitchen-cloudstack/issues). For bugs, please include:

- the version of kitchen-cloudstack and Test Kitchen you are using
- your CloudStack or CloudPlatform version
- your `kitchen.yml` with API keys and internal URLs removed
- the output of the failing command, ideally with `-l debug`

## Development setup

Clone the repository and install the dependencies:

```sh
git clone https://github.com/test-kitchen/kitchen-cloudstack.git
cd kitchen-cloudstack
bundle install
```

## Tests and linting

Be aware of the current state of the tooling before you start:

- **There are no unit tests.** The repository contains no spec or test files,
  so changes have to be verified manually against a real CloudStack deployment.
- **The Rakefile depends on unmaintained tools.** The default `rake` task runs
  `cane`, `tailor`, and `countloc`. These are no longer maintained and do not
  work on modern Ruby, so `bundle exec rake` is unlikely to succeed.
- **CI is out of date.** `.github/workflows/ci.yml` tests Ruby 2.5 to 3.0, all
  of which are end of life, and its push trigger still refers to a `master`
  branch that no longer exists.

Adding unit tests and replacing the dead linters with
[Cookstyle](https://github.com/chef/cookstyle) would be very welcome, and can be
done independently of the `SSHBase` port described above.

## Manual testing against CloudStack

Until there are unit tests, any change needs to be exercised against a real
deployment. You will need API credentials, and a template, service offering, and
zone ID to deploy against.

Export the credentials rather than putting them in `kitchen.yml`:

```sh
export CLOUDSTACK_API_KEY="..."
export CLOUDSTACK_SECRET_KEY="..."
```

Then run `kitchen test` against a pinned Test Kitchen. Afterwards, confirm in the
CloudStack UI that no VMs were left behind — a run that fails partway through can
leave one running. Setting `cloudstack_expunge: true` makes cleanup complete
rather than leaving VMs in the Destroyed state.

## Submitting changes

1. Fork the repository.
2. Create a feature branch off `main`.
3. Make your change.
4. Describe how you verified it, since there are no automated tests to rely on.
5. Push the branch to your fork and open a pull request.

Please keep pull requests focused on a single change — it makes review much
faster. Update the documentation in `README.md` when you add or change a
configuration option.

## Release process

Releases are handled by the maintainers.

1. Update `lib/kitchen/driver/cloudstack_version.rb` with the new version.
2. Update `CHANGELOG.md`.
3. Build and push the gem with `rake build` and `gem push`.
