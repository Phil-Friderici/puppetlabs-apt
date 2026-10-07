# frozen_string_literal: true

require 'open-uri'
begin
  require 'net/ftp'
rescue LoadError
  # Ruby 3.0 changed net-ftp to a default gem
end
require 'tempfile'

# Puppet registers the provider and its methods in this DSL block.
Puppet::Type.type(:apt_key).provide(:apt_key) do # rubocop:disable Metrics/BlockLength
  desc 'apt-key provider for apt_key resource'

  confine    'os.family': :debian
  defaultfor 'os.family': :debian
  commands   apt_key: 'apt-key'
  commands   gpg: '/usr/bin/gpg'

  def self.instances
    cli_args = ['adv', '--no-tty', '--list-keys', '--with-colons', '--fingerprint', '--fixed-list-mode']
    key_output = apt_key(cli_args).encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '')
    key_output.split("\n").slice_before { |line| line.start_with?('pub') }.filter_map do |lines|
      instance_from_lines(lines)
    end
  end

  def self.instance_from_lines(lines)
    fpr_lines = lines.select { |line| line.start_with?('fpr') }
    return unless lines.first.start_with?('pub') && !fpr_lines.empty?

    line_hash = key_line_hash(lines.first, fpr_lines)
    sub_lines = lines.select { |line| line.start_with?('sub') }
    new(key_properties(line_hash).merge(expired: line_hash[:key_expired] || subkeys_all_expired(sub_lines)))
  end

  def self.key_properties(line_hash)
    {
      name: line_hash[:key_fingerprint],
      id: line_hash[:key_long],
      fingerprint: line_hash[:key_fingerprint],
      short: line_hash[:key_short],
      long: line_hash[:key_long],
      ensure: :present,
    }.merge(key_metadata(line_hash))
  end

  def self.key_metadata(line_hash)
    {
      expiry: line_hash[:key_expiry]&.strftime('%Y-%m-%d'),
      size: line_hash[:key_size],
      type: line_hash[:key_type],
      created: line_hash[:key_created].strftime('%Y-%m-%d'),
    }
  end

  def self.prefetch(resources)
    apt_keys = instances
    resources.each_key do |name|
      property = { 40 => :fingerprint, 16 => :long, 8 => :short }[name.length]
      next unless property

      provider = apt_keys.find { |key| key.public_send(property) == name }
      resources[name].provider = provider if provider
    end
  end

  def self.subkeys_all_expired(sub_lines)
    return false if sub_lines.empty?

    sub_lines.each do |line|
      return false if line.split(':')[1] == '-'
    end
    true
  end

  def self.key_line_hash(pub_line, fpr_lines)
    pub_split = pub_line.split(':')
    fingerprint = fpr_lines.first.split(':').last
    {
      key_fingerprint: fingerprint,
      key_long: fingerprint[-16..], # last 16 characters of fingerprint
      key_short: fingerprint[-8..], # last 8 characters of fingerprint
    }.merge(key_line_metadata(pub_split))
  end

  def self.key_line_metadata(pub_split)
    {
      key_size: pub_split[2],
      key_type: { '1' => :rsa, '17' => :dsa, '18' => :ecc, '19' => :ecdsa }[pub_split[3]],
      key_created: Time.at(pub_split[5].to_i),
      key_expired: pub_split[1] == 'e',
      key_expiry: pub_split[6].empty? ? nil : Time.at(pub_split[6].to_i),
    }
  end

  def source_to_file(value)
    parsed_value = URI.parse(value)
    if parsed_value.scheme.nil?
      local_source_file(value)
    else
      remote_source_file(parsed_value)
    end
  end

  def local_source_file(value)
    raise(_('The file %{_value} does not exist') % { _value: value }) unless File.exist?(value)

    # Return a closed file object, like tempfile, so the caller can use #path.
    file = File.open(value, 'r')
    file.close
    file
  end

  def remote_source_file(parsed_value)
    tempfile(download_source(parsed_value))
  end

  def download_source(parsed_value)
    exceptions = [OpenURI::HTTPError]
    exceptions << Net::FTPPermError if defined?(Net::FTPPermError)
    read_remote_source(parsed_value)
  rescue *exceptions => e
    raise(_('%{_e} for %{_resource}') % { _e: e.message, _resource: resource[:source] })
  rescue SocketError
    raise(_('could not resolve %{_resource}') % { _resource: resource[:source] })
  end

  def read_remote_source(parsed_value)
    # Only send basic auth if URL contains userinfo; empty auth can cause HTTP 400.
    if parsed_value.userinfo.nil?
      parsed_value.open(**remote_source_options(parsed_value)).read
    else
      user_pass = parsed_value.userinfo.split(':')
      parsed_value.userinfo = ''
      parsed_value.open(http_basic_authentication: user_pass).read
    end
  end

  def remote_source_options(parsed_value)
    return {} unless parsed_value.scheme == 'https' && resource[:weak_ssl] == true

    { ssl_verify_mode: OpenSSL::SSL::VERIFY_NONE }
  end

  # The tempfile method needs to return the tempfile object to the caller, so
  # that it doesn't get deleted by the GC immediately after it returns.  We
  # want the caller to control when it goes out of scope.
  def tempfile(content)
    file = Tempfile.new('apt_key')
    file.write content
    file.close
    verify_fingerprint(file) if name.size == 40
    file
  end

  def verify_fingerprint(file)
    # confirm that the fingerprint from the file, matches the long key that is in the manifest
    unless File.executable? command(:gpg)
      warning('/usr/bin/gpg cannot be found for verification of the id.')
      return
    end
    return if fingerprint_matches?(file)

    raise(_('The id in your manifest %{_resource} and the fingerprint from content/source don\'t match. Check for an error in the id and content/source is legitimate.') % { _resource: resource[:name] }) # rubocop:disable Layout/LineLength
  end

  def fingerprint_matches?(file)
    extracted_key = execute(["#{command(:gpg)} --no-tty --with-fingerprint --with-colons #{file.path} | awk -F: '/^fpr:/ { print $10 }'"], failonfail: false)
    extracted_key.chomp.each_line.any? { |line| line.chomp == name }
  end

  def exists?
    # report expired keys as non-existing when refresh => true
    @property_hash[:ensure] == :present && !(resource[:refresh] && @property_hash[:expired])
  end

  def create
    if resource[:source].nil? && resource[:content].nil?
      command = receive_key_command
    else
      key_file = resource_key_file
      command = ['add', key_file.path]
    end
    apt_key(command)
    @property_hash[:ensure] = :present
  end

  def receive_key_command
    # --recv-keys must be the last argument.
    command = ['adv', '--no-tty', '--keyserver', resource[:server]]
    command.push('--keyserver-options', resource[:options]) unless resource[:options].nil?
    command.push('--recv-keys', resource[:id])
  end

  def resource_key_file
    return tempfile(resource[:content]) if resource[:content]
    return source_to_file(resource[:source]) if resource[:source]

    raise(_('an unexpected condition occurred while trying to add the key: %{_resource}') % { _resource: resource[:id] })
  end

  def destroy
    loop do
      apt_key('del', resource.provider.short)
      r = execute(["#{command(:apt_key)} list | grep '/#{resource.provider.short}\s'"], failonfail: false)
      break unless r.exitstatus.zero?
    end
    @property_hash.clear
  end

  def read_only(_value)
    raise(_('This is a read-only property.'))
  end

  mk_resource_methods

  # Alias the setters of read-only properties
  # to the read_only function.
  alias_method :created=, :read_only
  alias_method :expired=, :read_only
  alias_method :expiry=, :read_only
  alias_method :size=, :read_only
  alias_method :type=, :read_only
end
