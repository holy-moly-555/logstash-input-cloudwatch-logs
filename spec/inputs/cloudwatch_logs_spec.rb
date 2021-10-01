# frozen_string_literal: true
#
require 'logstash/devutils/rspec/spec_helper'
require 'logstash/inputs/cloudwatch_logs'
require 'aws-sdk-resources'
require 'aws-sdk'

describe LogStash::Inputs::CloudWatchLogs do
  let(:config) {
    {
      'access_key_id' => '1234',
      'secret_access_key' => 'secret',
      'log_group' => ['sample-log-group'],
      'log_streams' => ['sample-log-stream-1', 'sample-log-stream-1'],
      'ignore_unavailable' => true,
      'region' => 'us-east-1'
    }
  }

  before do
    Aws.config[:stub_responses] = true
    Thread.abort_on_exception = true
  end

  describe '#register' do
    context 'default config' do
      subject { LogStash::Inputs::CloudWatchLogs.new(config) }

      it 'registers succesfully' do
        expect { subject.register }.to_not raise_error
      end
    end

    context 'start_position set to end' do
      subject { LogStash::Inputs::CloudWatchLogs.new(config.merge({ 'start_position' => 'end' })) }

      it 'registers succesfully' do
        expect { subject.register }.to_not raise_error
      end
    end

    context 'start_position set to an integer' do
      subject { LogStash::Inputs::CloudWatchLogs.new(config.merge({ 'start_position' => 100 })) }

      it 'registers succesfully' do
        expect { subject.register }.to_not raise_error
      end
    end

    context 'start_position invalid' do
      subject { LogStash::Inputs::CloudWatchLogs.new(config.merge({ 'start_position' => 'invalid start position' })) }

      it 'raises a configuration error' do
        expect { subject.register }.to raise_error(LogStash::ConfigurationError)
      end
    end

    context 'retry_limit set to an integer' do
      subject { LogStash::Inputs::CloudWatchLogs.new(config.merge({ 'retry_limit' => 1 })) }

      it 'registers successfully' do
        expect { subject.register }.to_not raise_error
      end
    end

    context 'backoff_time set to an integer' do
      subject { LogStash::Inputs::CloudWatchLogs.new(config.merge({ 'backoff_time' => 10 })) }

      it 'registers successfully' do
        expect { subject.register }.to_not raise_error
      end
    end

    context 'backoff_time set to a negative integer' do
      subject { LogStash::Inputs::CloudWatchLogs.new(config.merge({ 'backoff_time' => -1 })) }

      it 'raises a configuration error' do
        expect { subject.register }.to raise_error(LogStash::ConfigurationError)
      end
    end

    context 'max_failed_runs set without backoff_time' do
      subject { LogStash::Inputs::CloudWatchLogs.new(config.merge({ 'max_failed_runs' => 2 })) }

      it 'raises a configuration error' do
        expect { subject.register }.to raise_error(LogStash::ConfigurationError)
      end
    end

    context 'max_failed_runs set to an integer' do
      subject { LogStash::Inputs::CloudWatchLogs.new(config.merge({ 'backoff_time' => 5, 'max_failed_runs' => 2 })) }

      it 'registers successfully' do
        expect { subject.register }.to_not raise_error
      end
    end
  end

  describe '#determine_start_position' do
    context 'start_position set to an integer' do
      sincedb = {}
      subject { LogStash::Inputs::CloudWatchLogs.new(config.merge({ 'start_position' => 100 })) }

      it 'successfully parses the start position' do
        expect { subject.determine_start_position(['test'], sincedb) }.to_not raise_error
      end
    end
  end
end
