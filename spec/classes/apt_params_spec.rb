# frozen_string_literal: true

require 'spec_helper'

describe 'apt::params' do
  let(:pre_condition) do
    <<~PUPPET
      include apt::params
      $expected = {
        'conf'    => { 'path' => '/etc/apt/apt.conf.d', 'ext' => '' },
        'pref'    => { 'path' => '/etc/apt/preferences.d', 'ext' => '.pref' },
        'list'    => { 'path' => '/etc/apt/sources.list.d', 'ext' => '.list' },
        'sources' => { 'path' => '/etc/apt/sources.list.d', 'ext' => '.sources' },
      }
      if $apt::params::config_files != $expected {
        fail('Unexpected apt::params::config_files defaults')
      }
      notify { 'params_sources_list_d': message => $apt::params::sources_list_d }
      notify { 'params_conf_d': message => $apt::params::conf_d }
      notify { 'params_preferences_d': message => $apt::params::preferences_d }
    PUPPET
  end

  it { is_expected.to compile }
  it { is_expected.to contain_notify('params_sources_list_d').with_message('/etc/apt/sources.list.d') }
  it { is_expected.to contain_notify('params_conf_d').with_message('/etc/apt/apt.conf.d') }
  it { is_expected.to contain_notify('params_preferences_d').with_message('/etc/apt/preferences.d') }
end
