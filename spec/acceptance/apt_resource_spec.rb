# frozen_string_literal: true

require 'spec_helper_acceptance'

describe 'apt resources' do
  # Verify list-format source parameters produce the expected named source entry.
  context 'when writing list-format source options' do
    let(:checks) do
      pp = <<-MANIFEST
      apt::source { 'acceptance-list':
        location      => 'https://example.invalid/debian',
        release       => 'stable',
        repos         => 'main',
        architecture  => 'amd64',
        allow_unsigned => true,
        notify_update => false,
      }
      MANIFEST

      [
        retry_on_error_matching { idempotent_apply(pp) },
        run_shell("grep -F 'deb [arch=amd64 trusted=yes] https://example.invalid/debian stable main' /etc/apt/sources.list.d/acceptance-list.list"),
      ]
    end

    it 'writes list-format source options to the named file' do
      expect(checks).to all(be_truthy)
    end
  end

  # Verify deb822 output, enabled state, and ensure-absent cleanup.
  context 'when managing a deb822 source lifecycle' do
    let(:checks) do
      present_pp = <<-MANIFEST
      apt::source { 'acceptance-deb822':
        source_format => 'sources',
        location      => ['https://example.invalid/debian'],
        release       => ['stable'],
        repos         => ['main', 'contrib'],
        types         => ['deb', 'deb-src'],
        enabled       => false,
        notify_update => false,
      }
      MANIFEST
      absent_pp = <<-MANIFEST
      apt::source { 'acceptance-deb822':
        source_format => 'sources',
        ensure        => absent,
        notify_update => false,
      }
      MANIFEST

      [
        retry_on_error_matching { idempotent_apply(present_pp) },
        run_shell("grep -F 'Enabled: no' /etc/apt/sources.list.d/acceptance-deb822.sources"),
        run_shell("grep -F 'Types: deb deb-src' /etc/apt/sources.list.d/acceptance-deb822.sources"),
        apply_manifest(absent_pp, catch_failures: true),
        run_shell('test ! -e /etc/apt/sources.list.d/acceptance-deb822.sources'),
      ]
    end

    it 'manages a deb822 source lifecycle' do
      expect(checks).to all(be_truthy)
    end
  end

  # Verify pin priorities and removal are reflected in APT preference files.
  context 'when managing pin priority and removal' do
    let(:checks) do
      present_pp = <<-MANIFEST
      include apt

      apt::pin { 'acceptance-priority':
        packages => ['bash', 'curl'],
        origin   => 'example.invalid',
        priority => 990,
      }
      MANIFEST
      absent_pp = <<-MANIFEST
      include apt

      apt::pin { 'acceptance-priority':
        ensure => absent,
      }
      MANIFEST

      [
        retry_on_error_matching { idempotent_apply(present_pp) },
        run_shell("grep -F 'Package: bash curl' /etc/apt/preferences.d/acceptance-priority.pref"),
        run_shell("grep -F 'Pin-Priority: 990' /etc/apt/preferences.d/acceptance-priority.pref"),
        apply_manifest(absent_pp, catch_failures: true),
        run_shell('test ! -e /etc/apt/preferences.d/acceptance-priority.pref'),
      ]
    end

    it 'manages pin priority and removal' do
      expect(checks).to all(be_truthy)
    end
  end

  # Verify apt::conf maps priorities and ensure-absent to apt.conf.d files.
  context 'when managing apt configuration files' do
    let(:checks) do
      present_pp = <<-MANIFEST
      include apt

      apt::conf { 'acceptance':
        content       => 'Acquire::Retries "2";',
        priority      => 42,
        notify_update => false,
      }
      MANIFEST
      absent_pp = <<-MANIFEST
      include apt

      apt::conf { 'acceptance':
        ensure        => absent,
        priority      => 42,
        notify_update => false,
      }
      MANIFEST

      [
        retry_on_error_matching { idempotent_apply(present_pp) },
        run_shell("grep -F 'Acquire::Retries \"2\";' /etc/apt/apt.conf.d/42acceptance"),
        apply_manifest(absent_pp, catch_failures: true),
        run_shell('test ! -e /etc/apt/apt.conf.d/42acceptance'),
      ]
    end

    it 'manages apt configuration files' do
      expect(checks).to all(be_truthy)
    end
  end

  # Verify direct apt::setting resources honor file priority and removal.
  context 'when managing direct apt settings' do
    let(:checks) do
      present_pp = <<-MANIFEST
      include apt

      apt::setting { 'conf-acceptance-setting':
        ensure        => present,
        priority      => 43,
        content       => 'Acquire::Retries "3";',
        notify_update => false,
      }
      MANIFEST
      absent_pp = <<-MANIFEST
      include apt

      apt::setting { 'conf-acceptance-setting':
        ensure        => absent,
        priority      => 43,
        notify_update => false,
      }
      MANIFEST

      [
        retry_on_error_matching { idempotent_apply(present_pp) },
        run_shell("grep -F 'Acquire::Retries \"3\";' /etc/apt/apt.conf.d/43acceptance-setting"),
        apply_manifest(absent_pp, catch_failures: true),
        run_shell('test ! -e /etc/apt/apt.conf.d/43acceptance-setting'),
      ]
    end

    it 'manages direct apt settings' do
      expect(checks).to all(be_truthy)
    end
  end

  # Verify auth credentials use restrictive permissions and can be removed.
  context 'when managing authentication configuration' do
    let(:checks) do
      present_pp = <<-MANIFEST
      include apt

      apt::auth { 'acceptance-auth':
        machine  => 'packages.example.invalid',
        login    => 'acceptance-user',
        password => 'acceptance-test-password',
      }
      MANIFEST
      absent_pp = <<-MANIFEST
      include apt

      apt::auth { 'acceptance-auth':
        ensure   => absent,
        machine  => 'packages.example.invalid',
        login    => 'acceptance-user',
        password => 'acceptance-test-password',
      }
      MANIFEST

      [
        retry_on_error_matching { idempotent_apply(present_pp) },
        run_shell("grep -F 'machine packages.example.invalid' /etc/apt/auth.conf.d/acceptance-auth.conf"),
        run_shell("grep -Fx 'login acceptance-user' /etc/apt/auth.conf.d/acceptance-auth.conf"),
        run_shell("grep -Fx 'password acceptance-test-password' /etc/apt/auth.conf.d/acceptance-auth.conf"),
        run_shell('test "$(stat -c %a /etc/apt/auth.conf.d/acceptance-auth.conf)" = 600'),
        apply_manifest(absent_pp, catch_failures: true),
        run_shell('test ! -e /etc/apt/auth.conf.d/acceptance-auth.conf'),
      ]
    end

    it 'manages authentication configuration securely' do
      expect(checks).to all(be_truthy)
    end
  end

  # Verify apt-mark hold and unhold actions alter the package selection state.
  context 'when holding and unholding a package' do
    let(:checks) do
      hold_pp = <<-MANIFEST
      apt::mark { 'bash':
        setting => 'hold',
      }
      MANIFEST
      unhold_pp = <<-MANIFEST
      apt::mark { 'bash':
        setting => 'unhold',
      }
      MANIFEST

      [
        apply_manifest(hold_pp, catch_failures: true),
        run_shell("apt-mark showhold | grep -Fx 'bash'"),
        apply_manifest(unhold_pp, catch_failures: true),
        run_shell("! apt-mark showhold | grep -Fx 'bash'"),
      ]
    end

    it 'holds and unholds an installed package' do
      expect(checks).to all(be_truthy)
    end
  end
end
