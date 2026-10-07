# frozen_string_literal: true

require 'spec_helper_acceptance'

describe 'apt::backports' do
  context 'when using defaults' do
    let(:pp) do
      <<-MANIFEST
        include apt::backports
      MANIFEST
    end

    it 'applies idempotently' do # rubocop:disable RSpec/NoExpectationExample -- idempotent_apply checks for changes.
      retry_on_error_matching do
        idempotent_apply(pp)
      end
    end

    it 'provides backports apt sources' do # rubocop:disable RSpec/NoExpectationExample -- run_shell checks exit status.
      run_shell('apt-cache policy | grep --quiet backports')
    end
  end
end
