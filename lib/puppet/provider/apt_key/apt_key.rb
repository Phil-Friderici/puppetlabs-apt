# frozen_string_literal: true

require 'open-uri'
begin
  require 'net/ftp'
rescue LoadError
  # Ruby 3.0 changed net-ftp to a default gem
end
require 'tempfile'

# Puppet's provider API defines this implementation in a single DSL block.
# rubocop:disable Metrics/BlockLength
Puppet::Type.type(:apt_key).provide(:apt_key) do
  desc 'apt-key provider for apt_key resource'

  confine    'os.family': :debian
  defaultfor 'os.family': :debian
  commands   apt_key: 'apt-key'
  commands   gpg: '/usr/bin/gpg'

  def self.instances
    cli_args = ['adv', '--no-tty', '--list-keys', '--with-colons', '--fingerprint', '--fixed-list-mode']
    key_output = apt_key(cli_args).encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '')
    key_output.split("\n").slice_before { |line| line.start_with?('pub') }.filter_map do |key_lines|
      instance_from_lines(key_lines)
    end
  end

  def self.instance_from_lines(key_lines)
    return unless key_lines.first.start_with?('pub')

    pub_line = key_lines.first
    fpr_lines = key_lines.select { |line| line.start_with?('fpr') }
    return if fpr_lines.empty?

    line_hash = key_line_hash(pub_line, fpr_lines)
    new(**instance_attributes(line_hash, key_lines.select { |line| line.start_with?('sub') }))
  end

  def self.instance_attributes(line_hash, sub_lines)
    {
      name: line_hash[:key_fingerprint],
      id: line_hash[:key_long],
      fingerprint: line_hash[:key_fingerprint],
      short: line_hash[:key_short],
      long: line_hash[:key_long],
      ensure: :present,
      expired: line_hash[:key_expired] || subkeys_all_expired(sub_lines),
      expiry: line_hash[:key_expiry]&.strftime('%Y-%m-%d'),
      size: line_hash[:key_size],
      type: line_hash[:key_type],
      created: line_hash[:key_created].strftime('%Y-%m-%d'),
    }
  end

  def self.prefetch(resources)
    apt_keys = instances
    resources.each { |name, resource| prefetch_key(resource, apt_keys, name) }
  end

  def self.prefetch_key(resource, apt_keys, name)
    attribute = { 40 => :fingerprint, 16 => :long, 8 => :short }[name.length]
    provider = apt_keys.find { |key| key.public_send(attribute) == name } if attribute
    resource.provider = provider if provider
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
    fpr_split = fpr_lines.first.split(':')

    fingerprint = fpr_split.last
    key_type = { '1' => :rsa, '17' => :dsa, '18' => :ecc, '19' => :ecdsa }[pub_split[3]]
    {
      key_fingerprint: fingerprint,
      key_long: fingerprint[-16..], # last 16 characters of fingerprint
      key_short: fingerprint[-8..], # last 8 characters of fingerprint
      key_size: pub_split[2],
      key_type: key_type,
      key_created: Time.at(pub_split[5].to_i),
      key_expired: pub_split[1] == 'e',
      key_expiry: pub_split[6].empty? ? nil : Time.at(pub_split[6].to_i),
    }
  end

  def source_to_file(value)
    parsed_value = URI.parse(value)
    return local_source_file(value) if parsed_value.scheme.nil?

    tempfile(download_key(parsed_value))
  end

  def local_source_file(value)
    raise(_('The file %{_value} does not exist') % { _value: value }) unless File.exist?(value)

    file = File.open(value, 'r')
    file.close
    file
  end

  def download_key(parsed_value)
    exceptions = [OpenURI::HTTPError]
    exceptions << Net::FTPPermError if defined?(Net::FTPPermError)

    fetch_key(parsed_value)
  rescue *exceptions => e
    raise(_('%{_e} for %{_resource}') % { _e: e.message, _resource: resource[:source] })
  rescue SocketError
    raise(_('could not resolve %{_resource}') % { _resource: resource[:source] })
  end

  def fetch_key(parsed_value)
    if parsed_value.userinfo.nil?
      options = { ssl_verify_mode: OpenSSL::SSL::VERIFY_NONE } if parsed_value.scheme == 'https' && resource[:weak_ssl] == true
      options ? OpenURI.open_uri(parsed_value, **options).read : parsed_value.read
    else
      user_pass = parsed_value.userinfo.split(':')
      parsed_value.userinfo = ''
      OpenURI.open_uri(parsed_value, http_basic_authentication: user_pass).read
    end
  end

  # The tempfile method needs to return the tempfile object to the caller, so
  # that it doesn't get deleted by the GC immediately after it returns.  We
  # want the caller to control when it goes out of scope.
  def tempfile(content)
    file = Tempfile.new('apt_key')
    file.write content
    file.close
    verify_fingerprint(file)
    file
  end

  def verify_fingerprint(file)
    if name.size == 40
      if File.executable? command(:gpg)
        extracted_key = execute(["#{command(:gpg)} --no-tty --with-fingerprint --with-colons #{file.path} | awk -F: '/^fpr:/ { print $10 }'"], failonfail: false)
        extracted_key = extracted_key.chomp

        found_match = false
        extracted_key.each_line do |line|
          found_match = true if line.chomp == name
        end
        unless found_match
          raise(_('The id in your manifest %{_resource} and the fingerprint from content/source don\'t match. Check for an error in the id and content/source is legitimate.') % { _resource: resource[:name] }) # rubocop:disable Layout/LineLength
        end
      else
        warning('/usr/bin/gpg cannot be found for verification of the id.')
      end
    end
  end

  def exists?
    # report expired keys as non-existing when refresh => true
    @property_hash[:ensure] == :present && !(resource[:refresh] && @property_hash[:expired])
  end

  def create
    apt_key(create_command)
    @property_hash[:ensure] = :present
  end

  def create_command
    command = []
    if resource[:source].nil? && resource[:content].nil?
      # Breaking up the command like this is needed because it blows up
      # if --recv-keys isn't the last argument.
      command.push('adv', '--no-tty', '--keyserver', resource[:server])
      command.push('--keyserver-options', resource[:options]) unless resource[:options].nil?
      command.push('--recv-keys', resource[:id])
    elsif resource[:content]
      key_file = tempfile(resource[:content])
      command.push('add', key_file.path)
    elsif resource[:source]
      key_file = source_to_file(resource[:source])
      command.push('add', key_file.path)
    # In case we really screwed up, better safe than sorry.
    else
      raise(_('an unexpected condition occurred while trying to add the key: %{_resource}') % { _resource: resource[:id] })
    end
    command
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
# rubocop:enable Metrics/BlockLength
