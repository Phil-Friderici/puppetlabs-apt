#!/opt/puppetlabs/puppet/bin/ruby
# frozen_string_literal: true

require 'json'
require 'open3'
require 'puppet'

def apt_get(action)
  stdout, stderr, status = Open3.capture3(*apt_get_command(action))
  raise Puppet::Error, stderr if status != 0

  { status: stdout.strip }
end

def apt_get_command(action)
  cmd = ['apt-get', action]
  return cmd unless ['upgrade', 'dist-upgrade', 'autoremove'].include?(action)

  ENV['DEBIAN_FRONTEND'] = 'noninteractive'
  cmd.concat(['-y', '-o', 'Dpkg::Options="--force-confdef"', '-o', 'Dpkg::Options="--force-confold"'])
end

params = JSON.parse($stdin.read)
action = params['action']

begin
  result = apt_get(action)
  puts result.to_json
  exit 0
rescue Puppet::Error => e
  puts({ status: 'failure', error: e.message }.to_json)
  exit 1
end
