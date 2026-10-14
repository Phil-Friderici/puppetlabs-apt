# frozen_string_literal: true

require 'spec_helper'

describe 'apt::params' do
  let(:pre_condition) do
    <<~PUPPET
      include apt::params
      notify { 'params_sources_list_d': message => $apt::params::sources_list_d }
      notify { 'params_conf_d': message => $apt::params::conf_d }
      notify { 'params_preferences_d': message => $apt::params::preferences_d }
      apt::setting { 'conf-params': content => 'content', notify_update => false }
      apt::setting { 'pref-params': content => 'content', notify_update => false }
      apt::setting { 'list-params': content => 'content', notify_update => false }
      apt::setting { 'sources-params': content => 'content', notify_update => false }
    PUPPET
  end

  it { is_expected.to compile }
  it { is_expected.to contain_notify('params_sources_list_d').with_message('/etc/apt/sources.list.d') }
  it { is_expected.to contain_notify('params_conf_d').with_message('/etc/apt/apt.conf.d') }
  it { is_expected.to contain_notify('params_preferences_d').with_message('/etc/apt/preferences.d') }
  it { is_expected.to contain_file('/etc/apt/apt.conf.d/50params') }
  it { is_expected.to contain_file('/etc/apt/preferences.d/params.pref') }
  it { is_expected.to contain_file('/etc/apt/sources.list.d/params.list') }
  it { is_expected.to contain_file('/etc/apt/sources.list.d/params.sources') }
end
