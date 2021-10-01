# frozen_string_literal: true

require 'logstash/inputs/base'
require 'logstash/namespace'
require 'logstash/plugin_mixins/aws_config'
require 'logstash/timestamp'
require 'time'
require 'stud/interval'
require 'aws-sdk'
require 'logstash/inputs/cloudwatch_logs/patch'
require 'fileutils'

Aws.eager_autoload!

module LogStash
  module Inputs
    # This class is responsible for fetching logs from cloudwatch
    class CloudWatchLogs < LogStash::Inputs::Base
      include LogStash::PluginMixins::AwsConfig::V2

      config_name 'cloudwatch_logs'

      default :codec, 'plain'

      # Log group of the log streams
      config :log_group, validate: :string

      # Log stream(s) you want to fetch
      config :log_streams, validate: :string, list: true

      # Controls the behaviour if specified log streams do not exist.
      # When set to `true` the plugin will log a warning and continue.
      # When set to `false` the plugin will exit.
      config :ignore_unavailable, validate: :boolean, default: false

      # The Cloudwatch Logs API let's you fetch up to 10000 events or 10 MB worth of network traffic per request.
      # If there are more events/byte to fetch, the response will be paginated.
      # When reading from way back in the past (configured via `start_position`) in a high volume log environment
      # processing a log stream can block the remaining ones until all logs from that stream were processed.
      # With this setting you can define the maximum number of pages the plugin will request for each log stream.
      # Any value <= 0 will disable this setting.
      config :max_pages, validate: :number, default: 0

      # Whether logging of the aws ruby client should be enabled or not
      # The logs will include the requests to the cloudwatch api
      config :enable_client_logging, validate: :boolean, default: false

      # The maximum number of times to retry failed requests. Only ~ 500 level server errors and certain ~ 400 level
      # client errors are retried. Generally, these are throttling errors, data checksum errors, networking errors,
      # timeout errors and auth errors from expired credentials. The client's default is 3.
      # Check Constructor Details at https://docs.aws.amazon.com/sdk-for-ruby/v2/api/Aws/CloudWatchLogs/Client.html
      # Important: This setting is part of the aws ruby client configuration and does not affect any custom logic.
      # Usage consideration:
      # When you're encountering ThrottlingExceptions it doesn't make sense to let the client retry the same request
      # two more times. This would put even more pressure on competing pipelines that use this plugin.
      # Therefore it is highly recommended to set `retry_limit` to 0 and configure `backoff_time` unless you are sure
      # to not reach the service quota.
      config :retry_limit, validate: :number, default: 3

      # The time the plugin waits after it encounters violations of the service quota and the next run.
      # The backoff time is multiplied by the failed runs until it is reset when a future request succeeds.
      # Value is in seconds.
      config :backoff_time, validate: :number, default: 0

      # The maximum number of failed runs before the total backoff time is reset.
      # Must be specified in conjunction with :backoff_time
      # By default this setting is disabled.
      config :max_failed_runs, validate: :number, default: 0

      # Where to write the since database. Should be a path with filename not just a directory.
      config :since_db_path, validate: :string, default: nil

      # Interval to wait after a run is finished.
      # Value is in seconds.
      config :interval, validate: :number, default: 60

      # When a new log stream is encountered at initial plugin start (not already in the since_db),
      # allow configuration to specify where to begin ingestion on this stream.
      # Valid options are: `beginning`, `end`, or an integer,
      # representing the number of seconds before now to read back from.
      config :start_position, default: 'beginning'

      CLIENT_LOG_PATTERN = '[:client_class :http_request_method :http_request_endpoint]'\
                           '[:http_response_status_code; :time seconds; :retries retries]'\
                           '[:operation(:request_params)] :error_class :error_message'

      def create_default_since_db_path
        require 'digest/sha2'
        @logger.info('since_db_path not specified. Creating default location...')

        settings = defined?(LogStash::SETTINGS) ? LogStash::SETTINGS : nil
        root_path = ::File.join(settings.get_value('path.data'), 'plugins', 'inputs', 'cloudwatch_logs')

        FileUtils.mkdir_p(root_path)

        @since_db_path = ::File.join(root_path, ".sincedb_#{Digest::SHA2.hexdigest(@streams.join(','))}")
        @logger.info("Created since_db_path: #{@since_db_path}")
      end

      def register
        @logger.debug("Registering cloudwatch_logs input for log group #{@log_group}")
        @since_db = {}

        # tracks the number of failed runs due to violation of the service quota. Influences the throttling delay.
        @failed_runs = 0

        check_start_position_validity
        check_backoff_settings
        configure_aws_client
        validate_log_streams

        create_default_since_db_path if @since_db_path.nil?
      end

      def configure_aws_client
        Aws::ConfigService::Client.new(aws_options_hash)

        client_config = aws_options_hash.merge({ retry_limit: @retry_limit }) # base config
        if @enable_client_logging
          client_config.merge!({ logger: @logger, log_formatter: Aws::Log::Formatter.new(CLIENT_LOG_PATTERN) })
        end

        @client = Aws::CloudWatchLogs::Client.new(client_config)
      end

      def validate_log_streams
        params = {
          log_group_name: @log_group
        }

        resp = @client.describe_log_streams(params)

        available_log_streams = []
        resp.log_streams.each do |hash|
          available_log_streams.append(hash.log_stream_name)
        end
        unavailable_log_streams = @log_streams - available_log_streams

        return if unavailable_log_streams.empty?

        unless @ignore_unavailable
          raise LogStash::ConfigurationError, 'Some of the specified log streams are not available.'\
                                              'Exiting because :ignore_unavailable is set to false!'
        end

        @logger.warn("The log streams #{unavailable_log_streams} are not available."\
                     'Plugin will ignore them and continue.')
        @log_streams.keep_if { |s| !unavailable_log_streams.include?(s) }
      end

      def check_backoff_settings
        if @max_failed_runs.positive? && @backoff_time.zero?
          raise LogStash::ConfigurationError, 'max_failed_runs must be used in conjunction with backoff_time!'
        end

        raise LogStash::ConfigurationError, 'backoff_time has to be a positive integer!' if @backoff_time.negative?
      end

      def check_start_position_validity
        raise LogStash::ConfigurationError, 'No start_position specified!' unless @start_position

        return if @start_position =~ /^(beginning|end)$/
        return if @start_position.is_a? Integer

        raise LogStash::ConfigurationError,
              "start_position '#{@start_position}' is invalid! Must be `beginning`, `end`, or an integer."
      end

      def backoff?
        @backoff_time.positive?
      end

      def max_failed_runs_reached?
        @failed_runs == @max_failed_runs
      end

      def reset_failed_runs
        @logger.debug('Resetting failed runs counter to 0.')
        @failed_runs = 0
      end

      def throttle
        @failed_runs += 1

        if max_failed_runs_reached?
          @logger.info('Maximum number of failed runs reached. Resetting backoff delay')
          @failed_runs = 0
        else
          sleep_duration = @failed_runs * @backoff_time

          @logger.warn("Sleeping for #{sleep_duration} seconds")
          Stud.stoppable_sleep((sleep_duration)) { stop? }
        end
      end

      def run(queue)
        @queue = queue
        since_db_read
        determine_start_position(@log_streams, @since_db)

        until stop?
          begin
            @log_streams.each do |stream|
              process_stream(stream)
            end
          rescue Aws::CloudWatchLogs::Errors::ThrottlingException
            @logger.warn('Reached service quota.')
            throttle if backoff?
          end

          Stud.stoppable_sleep(@interval) { stop? }
        end
      end

      def process_stream(stream)
        num_pages = 0
        next_token = nil

        loop do
          @since_db[stream] = 0 unless @since_db.member?(stream)

          params = {
            log_group_name: @log_group,
            log_stream_names: %W[#{stream}],
            start_time: @since_db[stream],
            next_token: next_token,
            interleaved: true
          }
          @logger.debug("Fetching events for stream #{stream} with token #{next_token}")

          resp = @client.filter_log_events(params)

          @logger.debug("Fetched #{resp.events.size} events for stream #{stream}")

          resp.events.each do |event|
            process_log(event, stream)
          end

          since_db_write
          reset_failed_runs if backoff? && @failed_runs.positive?

          next_token = resp.next_token
          num_pages += 1 # no need to handle values <= 0

          break if next_token.nil? || num_pages == @max_pages
        end
      end

      def process_log(log, stream)
        @codec.decode(log.message.to_str) do |event|
          event.set('@timestamp', parse_time(log.timestamp))
          event.set('[cloudwatch_logs][ingestion_time]', parse_time(log.ingestion_time))
          event.set('[cloudwatch_logs][log_group]', @log_group)
          event.set('[cloudwatch_logs][log_stream]', stream)
          event.set('[cloudwatch_logs][event_id]', log.event_id)
          decorate(event)

          @queue << event
          @since_db[stream] = log.timestamp + 1
        end
      end

      def parse_time(data)
        LogStash::Timestamp.at(data.to_i / 1000, (data.to_i % 1000) * 1000)
      end

      def since_db_write
        IO.write(@since_db_path, serialize_since_db_hash, 0)
      rescue Errno::EACCES
        # probably no file handles free, maybe it will work next time
        @logger.error("since_db_write: error: #{@since_db_path}: #{$ERROR_INFO}")
      end

      def serialize_since_db_hash
        @since_db.map do |stream, timestamp|
          [stream, timestamp].join(' ')
        end.join("\n") + "\n"
      end

      def since_db_read
        ::File.open(@since_db_path) do |db|
          db.each do |entry|
            stream, timestamp = entry.split(' ', 2)
            @since_db[stream] = timestamp.to_i
          end
        end
      rescue Errno::ENOENT # No existing since_db to load
        @logger.debug("since_db_read: error: #{@since_db_path}: #{$ERROR_INFO}")
      end

      def determine_start_position(streams, since_db)
        streams.each do |stream|
          next unless since_db.member?(stream)

          since_db[stream] = case @start_position
                             when 'beginning'
                               0
                             when 'end'
                               DateTime.now.strftime('%Q')
                             else
                               DateTime.now.strftime('%Q').to_i - (@start_position * 1000)
                             end
        end
      end
    end
  end
end
