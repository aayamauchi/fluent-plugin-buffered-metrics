# buffered_metrics plugin for Fleuntd with a flexible metrics backend

## Overview
The buffered_metrics pLugin started off as something originally written to write metrics to the old Stackdriver v1.0 API.  It is a subclass of the BufferedOutput class and is designed to derive metrics from logs on a per-chunk basis, with the specified buffer flushing interval working as the metrics publishing interval.

The metrics backend has been completely reworked as a set of classes and can be completely so it can be completely swapped out on a per-instance basis.  This was done in an attempt to avoid backend conversion work, going forward, since the parsing metrics parsing is essentially independent from the backend publisher.  This plugin avoids subclassing any currently available metrics plugin, since they all seem to lock in to a specific backend metrics collector -- making the metrics parsing consistent without regard to the specific backend collector was a design goal for this plugin.

Note that the output type is also flexible.  For instance, most backends that I've seen for this require network settings and are hard-coded to open network sockets for their outputs.  However, this has been extended, here, to allow for any type of socket, and even some things (such as HTTP POST outputs) as the the backend.  For instance, something as simple as specifying the backend as "file:///var/tmp/metrics.testing" for debugging purposes is trivial with this plugin, whereas it is generally unpossible to do this with just about any network output plugin as they are invariably hard-coded to only use network sockets.

Currently, the graphite backend is known to work and the statsd backend should work, but hasn't really been tested.

## Installation
```bash
gem install fluent-plugin-buffered-metrics
```

If using the td-agent installation, use the following.

```bash
/opt/td-agent/embedded/bin/gem install fluent-plugin-buffered-metrics
```

## Configuration

Using this will probably require using the Fluentd copy output plugin.  Using the Fluentd copy_ex plugin (fluent-plugin-copy_ex) would probably be a better idea, so the failures with output configuration will not 'short-circuit' the normal log processing chain.  If the standard copy plugin is use, then the metrics processor(s) really should be configured last in the chain -- after the standard log processing.

### Parameters

`metrics_backend`: name of the metrics backend, currently either 'graphite' or 'statsd' (required)

`url`: where metrics are published (defaults to 'tcp://localhost:2003' for graphite and 'udp://localhost:8125' for statsd)

`counter_maps`: a JSON serialized hash where the keys are Ruby expressions which evaluate to Booleans and the values are either strings, or Ruby expressions which evalute to strings and are the name of the counter metric which is incremented when the key evaluates to True (optional, defaults to {})

`metric_maps`: a JSON serialized hash where the keys evaluate to Booleans ad the values evaluate to metric hashes (optinoal, defaults to {})

`counter_defaults`: a JSON serialized array contain default values for metrics which should be sent if there are no occurences of the metric in a buffer chunk (optional, defaults to [] -- likely not really needed as this was more of a requirement for legacy Stackdriver since it didn't really deal with gaps in the data very well)

`metric_defaults`: a JSON serialized array contain default values for metrics which should be sent if there are no occurences of the metric in a buffer chunk (optional, defaults to [] -- likely not really needed as this was more of a requirement for legacy Stackdriver since it didn't really deal with gaps in the data very well)

### Example configuration

```
<match **>
  @type copy_ex # using copy_ex instead of copy is strongly recommended
  <store ignore_error>
  [your stand log output configuration(s)]
  </store>
  <store ignore_error>
    @type buffered_metrics
    metrics_backend graphite
    prefix fluentd.legacy.scratch.us-east-1.TRUNCATED_INSTANCE_ID
    url <defaults to tcp://localhost:2003 for graphite>
    http_headers <defaults to [] -- used for http/https POST outputs which are not yet fully implemenent or tested>
    counter_maps { "true": [ "(['tag','level'].map {|t| event['record'][t]}+['log','count']).join('.')", "total.log.count" ] }
    metric_maps {}
    counter_defaults []
    metric_defaults []
    flush_interval 5m
    # Make this a working configuration
    [standard BufferedOutput parameters]
  </store>
  <store ignore_error>
    @type buffered_metrics
    metrics_backend statsd
    url <defaults to udp://localhost:8125 for statsd>
    http_headers <defaults to [] -- used for http/https POST outputs which are not yet fully implemenent or tested>
    counter_maps { "true": [ "(['tag','level'].map {|t| event['record'][t]}+['log','count']).join('.')", "total.log.count" ] }
    metric_maps {}
    counter_defaults []
    metric_defaults []
    flush_interval 5m
    [other standard BufferedOutput parameters]
  </store>
</source>
```
