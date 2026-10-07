# frozen_string_literal: true

require 'spec_helper_acceptance'

describe 'apt class' do
  context 'with default parameters' do
    # Using puppet_apply as a helper
    it 'works with no errors' do # rubocop:disable RSpec/NoExpectationExample -- apply_manifest checks exit status and idempotency.
      pp = <<-MANIFEST
      class { 'apt': }
      MANIFEST

      # Run it twice and test for idempotency
      apply_manifest(pp, catch_failures: true)
      apply_manifest(pp, catch_changes: true)
    end
  end
end
