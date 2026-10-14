# frozen_string_literal: true

require 'spec_helper'

describe 'apt::params' do
  let(:facts) do
    {
      os: {
        family: 'Debian',
        name: 'Debian',
        release: { major: '12', full: '12.0' },
        distro: { codename: 'bookworm', id: 'Debian' },
      },
    }
  end

  let(:post_condition) do
    <<~PUPPET
      $expected = {
        'conf'    => { 'path' => '/etc/apt/apt.conf.d', 'ext' => '' },
        'pref'    => { 'path' => '/etc/apt/preferences.d', 'ext' => '.pref' },
        'list'    => { 'path' => '/etc/apt/sources.list.d', 'ext' => '.list' },
        'sources' => { 'path' => '/etc/apt/sources.list.d', 'ext' => '.sources' },
      }
      if $apt::params::config_files != $expected {
        fail('Unexpected apt::params::config_files defaults')
      }
    PUPPET
  end

  it { is_expected.to compile.with_all_deps }
  it { is_expected.not_to contain_class('apt') }
end
