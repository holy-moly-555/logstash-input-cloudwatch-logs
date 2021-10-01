# Logstash Input for CloudWatch Logs

[![Gem][ico-version]][link-rubygems]
[![Downloads][ico-downloads]][link-rubygems]
[![Software License][ico-license]](LICENSE.md)
[![Build Status][ico-travis]][link-travis]

> Stream events from CloudWatch Logs.

## Usage

Specify an individual log stream or array of streams to periodically fetch log events.

### Parameters

| Parameter | Input Type | Required | Default |
|-----------|------------|----------|---------|
| log_group | string | Yes | |
| log_streams | string or Array of strings | Yes | |
| ignore_unavailable | boolean | No | false |
| max_pages | integer | No | 0 |
| enable_client_logging | boolean | No | false |
| retry_limit | integer | No | 3 |
| backoff_time | integer | No | 0 |
| max_failed_runs | integer | No | 0 |
| since_db_path | string | No | `${path.data}/plugins/inputs/cloudwatch_logs/.sincedb_*` |
| interval | integer | No | 60 |
| start_position | `beginning`, `end` or an integer | No | `beginning` |
| aws_credentials_file | string | No | |
| access_key_id | string | No | |
| secret_access_key | string | No | |
| session_token | string | No | |
| region | string | No | `eu-central-1` |
| codec | string | No | `plain` |

#### `ignore_unavailable`

Controls the behaviour if specified log streams do not exist.

- when set to `true` the plugin will log a warning and continue.
- when set to `false` the plugin will exit.

#### `max_pages`

The Cloudwatch Logs API let's you fetch up to 10000 events or 10 MB worth of network traffic per request.
If there are more events/byte to fetch, the response will be paginated.

When reading from way back in the past (configured via `start_position`) in a high volume log environment
processing a log stream can block the remaining ones until all logs from that stream were processed.

With this setting you can define the maximum number of pages the plugin will request for each log stream.
Any value equal or less than zero will disable this setting.

#### `enable_client_logging`

Whether logging of the aws ruby client should be enabled or not.
The logs will include the requests to the cloudwatch api.

#### `retry_limit`

The maximum number of times to retry failed requests. Only ~ 500 level server errors and certain ~ 400 level
client errors are retried. Generally, these are throttling errors, data checksum errors, networking errors,
timeout errors and auth errors from expired credentials. The client's default is 3.
Check the [Constructor Details](https://docs.aws.amazon.com/sdk-for-ruby/v2/api/Aws/CloudWatchLogs/Client.html)

Important: This setting is part of the aws ruby client configuration and does not affect any custom logic.

Usage consideration:
When you're encountering ThrottlingExceptions it doesn't make sense to let the client retry the same request
two more times. This would put even more pressure on competing pipelines that use this plugin as well.
Therefore it is highly recommended to set `retry_limit` to 0 and configure `backoff_time` unless you are sure
to not reach the service quota.

#### `backoff_time`

The time the plugin waits after it encounters violations of the service quota and the next run.
The backoff time is multiplied by the failed runs until it is reset when a future request succeeds.
Value is in seconds.

#### `max_failed_runs`

The maximum number of failed runs before the total backoff time is reset.
Must be specified in conjunction with backoff_time.
By default this setting is disabled.

#### `since_db_path`

Where to write the since database. Should be a path with filename not just a directory.

#### `interval`

Interval to wait after a run is finished. Value is in seconds.

#### `start_position`

The `start_position` setting allows you to specify where to begin processing
a newly encountered log stream on plugin boot. Whether the group is 'new' is
determined by whether or not the log stream has a previously existing entry in
the since_db file.

Valid options for `start_position` are:
* `beginning` - Reads from the beginning of the stream (default)
* `end` - Sets the since_db to now and reads any new messages going forward
* integer - Number of seconds in the past to begin reading at

#### Logstash Default config params
Other standard logstash parameters are available such as:
* `add_field`
* `type`
* `tags`

#### Example configuration

```ruby
input {
  cloudwatch_logs {
    access_key_id => "AKIAXXXXXX"
    secret_access_key => "SECRET"
    region => "eu-central-1"

    log_group => "my-app-prod"
    log_streams => ["app.log.json", "tomcat-access.log", "apache-error.log"]
    retry_limit => 0
    interval => 30
    start_position => 3600  # 1 hour ago
    since_db_path => "/usr/share/logstash/pipeline/my-app/.cloudwatch_last_run"
  }
}
```

## Development
The [default logstash README](DEVELOPER.md) which contains development directions and other information has been moved to [DEVELOPER.md](DEVELOPER.md).

## Contributing

All contributions are welcome: ideas, patches, documentation, bug reports, complaints, and even something you drew up on a napkin.

Programming is not a required skill. Whatever you've seen about open source and maintainers or community members  saying "send patches or die" - you will not see that here.

It is more important to the community that you are able to contribute.

For more information about contributing, see the [CONTRIBUTING](https://github.com/elasticsearch/logstash/blob/master/CONTRIBUTING.md) file.

[ico-version]: https://img.shields.io/gem/v/logstash-input-cloudwatch_logs.svg?style=flat-square
[ico-downloads]: https://img.shields.io/gem/dt/logstash-input-cloudwatch_logs.svg?style=flat-square
[ico-license]: https://img.shields.io/badge/License-Apache%202.0-blue.svg?style=flat-square
[ico-travis]: https://img.shields.io/travis/lukewaite/logstash-input-cloudwatch-logs.svg?style=flat-square

[link-rubygems]: https://rubygems.org/gems/logstash-input-cloudwatch_logs
[link-travis]: https://travis-ci.org/lukewaite/logstash-input-cloudwatch_logs
