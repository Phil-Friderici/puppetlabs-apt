# frozen_string_literal: true

require 'spec_helper_acceptance'

describe 'apt::backports' do
  context 'when using defaults' do
    let(:pp) do
      <<-MANIFEST
        include apt::backports
      MANIFEST
    end

    it 'applies idempotently' do
      expect do
        retry_on_error_matching do
          idempotent_apply(pp)
        end
      end.not_to raise_error
    end

    it 'provides backports apt sources' do
      expect do
        run_shell('apt-cache policy | grep --quiet backports')
      end.not_to raise_error
    end
  end
end
