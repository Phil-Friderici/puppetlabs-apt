# Copilot instructions

## Project structure

This Puppet module manages APT configuration on Debian-family systems. Puppet classes and defined types in `manifests/` compose resources for sources, keys, pins, preferences, proxies, and package-list updates; `apt` is the main class and is required when using the module's other resources. `types/` contains structured Puppet data types.

Ruby integration lives in `lib/`: custom Facter facts report APT state, while `lib/puppet/type/apt_key.rb` and `lib/puppet/provider/apt_key/apt_key.rb` implement the legacy key resource. `tasks/` contains Bolt task entry points. Specs are RSpec/rspec-puppet tests, grouped into class, defined-type, unit, and acceptance coverage; acceptance tests use Litmus.

Prefer `apt::keyring` for new key management. The README documents `apt::key` as deprecated on recent Debian and Ubuntu releases.

## Test and lint commands

Run commands from the repository root after installing the bundle:

- Full unit/catalog suite: `bundle exec rake spec`
- A single spec file: `bundle exec rspec spec/defines/source_spec.rb` (replace with the target spec path)
- RuboCop: `bundle exec rubocop` or `bundle exec rubocop path/to/file.rb`
- See available Rake tasks: `bundle exec rake -T`

The RuboCop configuration is `.rubocop.yml` with inherited suppressions in `.rubocop_todo.yml`; it enables the configured RuboCop plugins and enforces a 200-character line maximum, LF endings, and project-specific style/RSpec rules. For offense reports, run RuboCop on the requested checkout and report its actual output rather than inferring violations from text searches. Check configuration exclusions and TODO suppressions before describing an offense.

Acceptance tests require a Litmus environment; follow the acceptance-test setup linked from the Development section of `README.md`.

## Repository-specific conventions

- Keep changes scoped to the requested branch and files. Before branch-specific analysis or edits, verify the current checkout/branch and inspect the actual files there.
- Specs use rspec-puppet catalog matchers and shared Puppet facts; preserve those fixtures and resource behavior when updating tests.
- Keep Puppet-facing behavior and Ruby provider/fact behavior aligned: resource declarations are in `manifests/`, while execution and fact logic is in `lib/`.
- Regenerate `REFERENCE.md` after changes that alter documented Puppet parameters or types: `bundle exec puppet strings generate --format markdown --out REFERENCE.md`.
