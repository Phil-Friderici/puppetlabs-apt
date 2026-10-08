# frozen_string_literal: true

require 'spec_helper_acceptance'

describe 'apt class' do
  context 'with default parameters' do
    # Using puppet_apply as a helper
    it 'works with no errors' do
      pp = <<-MANIFEST
      class { 'apt': }
      MANIFEST

      # Run it twice and test for idempotency
      expect do
        apply_manifest(pp, catch_failures: true)
        apply_manifest(pp, catch_changes: true)
      end.not_to raise_error
    end
  end
end
