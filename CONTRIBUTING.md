# Contributing to kitchen-cloudstack

Thanks for your interest in improving kitchen-cloudstack. Bug reports, feature requests, and pull requests are all welcome.

## The most valuable contribution right now

**Testing against a real CloudStack deployment.** The driver was rewritten onto
the modern Test Kitchen driver and transport API, and it is covered by unit
tests, but those tests stub the CloudStack API. Nobody has yet confirmed the
rewrite end to end against real hardware.

The Windows and WinRM support is the least proven part. It works by setting the
transport to WinRM and letting the driver forward the transport's port and hand
over the password CloudStack generates, but it has not been run against a real
Windows template. If you have a CloudStack deployment, running `kitchen test`
against it — on Linux or Windows — and reporting what happened is genuinely the
most useful thing you can do for this project.

Other changes that would be welcome:

- Wrapping CloudStack API errors in `Kitchen::ActionFailed`, so that bad
  credentials produce a readable message rather than a
  `CloudstackClient::ApiError` and a stack trace.
- Making `create` idempotent, so that running it against an instance that
  already exists in state does not deploy a second one.
- Looking up templates, service offerings, zones and networks by name rather
  than requiring UUIDs in `kitchen.yml`.

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

Run the tests with:

```sh
bundle exec rake
```

That runs RSpec, which is also the default Rake task. To run the linter:

```sh
bundle exec cookstyle --chefstyle
```

CI runs both, plus `markdownlint` and `yamllint`, and runs the tests against
every Ruby from 3.1 to 4.0. All of it must pass before a pull request can merge.

### How the tests are organised

Specs live under `spec/`:

- `spec/kitchen/driver/cloudstack_spec.rb` covers the driver itself — what ends
  up in instance state, how `create`, `destroy` and `status` behave, and how the
  configured transport determines which port is forwarded.
- `spec/kitchen/driver/cloudstack/` covers each supporting class in isolation.
  `ServerOptions` and `Credentials` are plain objects and are tested directly.
- `spec/integration/lifecycle_spec.rb` runs a full create/status/destroy cycle
  through real Test Kitchen and a real `cloudstack_client`, stubbing only the
  HTTP layer, so request signing, response parsing and plugin wiring are all
  exercised.

Unit specs inject a fake client rather than stubbing `CloudstackClient::Client`
globally.
If you add behaviour that talks to CloudStack, prefer the same approach: it
keeps the tests fast and makes it obvious which API calls a change actually
makes.

## Manual testing against CloudStack

Automated tests cannot prove a change works against a real deployment, so
anything that touches the CloudStack API is worth exercising for real. You will
need API credentials, and a template, service offering, and zone ID to deploy
against.

Export the credentials rather than putting them in `kitchen.yml`:

```sh
export CLOUDSTACK_API_KEY="..."
export CLOUDSTACK_SECRET_KEY="..."
```

Then run `kitchen test`. Afterwards, confirm in the CloudStack UI that no VMs
were left behind — a run that fails partway through can leave one running.
Setting `cloudstack_expunge: true` makes cleanup complete rather than leaving
VMs in the Destroyed state.

## Submitting changes

1. Fork the repository.
2. Create a feature branch off `main`.
3. Make your change, with tests covering it.
4. Run `bundle exec rake` and `bundle exec cookstyle --chefstyle`.
5. Push the branch to your fork and open a pull request.

Please keep pull requests focused on a single change — it makes review much
faster. Update the documentation in `README.md` when you add or change a
configuration option, and note user-visible changes in `CHANGELOG.md`.

## Release process

Releases are automated with
[release-please](https://github.com/googleapis/release-please). Merging to
`main` opens a release pull request that updates the version and changelog;
merging that pull request tags the release and publishes the gem to RubyGems
and GitHub Packages.
