# Logstash Input for CloudWatch Logs

[![Gem][ico-version]][link-rubygems]
[![Downloads][ico-downloads]][link-rubygems]
[![Software License][ico-license]](LICENSE.md)
[![Build Status][ico-travis]][link-travis]

> Stream events from CloudWatch Logs.

### Purpose
Specify an individual log group or array of groups, and this plugin will scan
all log streams in that group, and pull in any new log events.

Optionally, you may set the `log_group_prefix` parameter to true
which will scan for all log groups matching the specified prefix(s)
and ingest all logs available in all of the matching groups.

## Usage

### Parameters
| Parameter | Input Type | Required | Default |
|-----------|------------|----------|---------|
| log_group | string or Array of strings | Yes | |
| log_group_prefix | boolean | No | `false` |
| start_position | `beginning`, `end`, or an Integer | No | `beginning` |
| sincedb_path | string | No | `$HOME/.sincedb*` |
| interval | number | No | 60 |
| retry_limit | number | No | 3 |
| backoff_time | number | No | 0 |
| max_failed_runs | number | No | 0 |
| aws_credentials_file | string | No | |
| access_key_id | string | No | |
| secret_access_key | string | No | |
| session_token | string | No | |
| region | string | No | `us-east-1` |
| codec | string | No | `plain` |

#### `start_position`
The `start_position` setting allows you to specify where to begin processing
a newly encountered log group on plugin boot. Whether the group is 'new' is
determined by whether or not the log group has a previously existing entry in
the sincedb file.

Valid options for `start_position` are:
* `beginning` - Reads from the beginning of the group (default)
* `end` - Sets the sincedb to now, and reads any new messages going forward
* Integer - Number of seconds in the past to begin reading at

#### `retry_limit`

The maximum number of times to retry failed requests. Only ~ 500 level server errors and certain ~ 400 level
client errors are retried. Generally, these are throttling errors, data checksum errors, networking errors,
timeout errors and auth errors from expired credentials. The client's default is 3.
Refer to the [Constructor Details](https://docs.aws.amazon.com/sdk-for-ruby/v2/api/Aws/CloudWatchLogs/Client.html).

Important: This setting is part of the client configuration. It does not provide custom logic.
Usage consideration: If you're encountering ThrottlingExceptions you wouldn't want to retry the failed
request. So setting retry_limit to 0 to disable automatic retries and configuring `backoff_time`
may be a better choice.

#### `backoff_time`

The time the plugin waits after it encounters a violations of the service quota and the next run.
The backoff time is multiplied by the failed runs until it was reset.
Value is in seconds.

#### `max_failed_runs`

The maximum number of failed runs before the total backoff time is reset.
Must be specified in conjunction with backoff_time
By default this setting is disabled.

#### Logstash Default config params
Other standard logstash parameters are available such as:
* `add_field`
* `type`
* `tags`

### Example

    input {
        cloudwatch_logs {
            log_group => [ "/aws/lambda/my-lambda" ]
            access_key_id => "AKIAXXXXXX" 
            secret_access_key => "SECRET"
        }
    }

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
