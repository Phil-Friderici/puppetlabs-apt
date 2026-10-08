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
      expect(retry_on_error_matching { idempotent_apply(pp) }).to be_truthy
    end

    it 'provides backports apt sources' do
      expect(run_shell('apt-cache policy | grep --quiet backports')).to be_truthy
    end
  end
end
