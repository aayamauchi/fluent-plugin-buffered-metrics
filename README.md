# Fluentd plugin for deriving metrics from output buffer chunks

## Overview
The buffered_metrics plugin started off as something originally written to write metrics to the old Stackdriver v1.0 API.  The intended purpose is to be able to derive metrics on scheduled intervals, not in real time as individual events pass through the Fluentd processing pipeline.  It is implemented as a subclass of the BufferedOutput class and is derives metrics from logs on a per-chunk basis, with the specified buffer flushing interval serving as the metrics collection and publishing interval.  It is kind of hacky and relies on Ruby evals in an attempt to make the metrics derivations as generic and flexible as possible.

The metrics backend has been completely reworked as a set of subclasses in n effort to separate the metrics derivation from the metrics publishing.  This was done in an attempt to avoid backend conversion work, going forward, since it should now be possible to swap a new metrics backend into place without having to touch the parsers.

Currently, the graphite backend is known to work and the statsd backend should work, but hasn't really been tested.  However, the statsd backend has bene hard-coded to "count" data types, since buffered collection for statsd doesn't make a lot of sense since timestamps cannot be preserved.

## Installation
```bash
gem install fluent-plugin-buffered-metrics
```

If using the td-agent installation, use the following.

```bash
/opt/td-agent/embedded/bin/gem install fluent-plugin-buffered-metrics
```

## Configuration

Using this will probably require using the Fluentd copy output plugin.  Using the Fluentd copy_ex plugin (fluent-plugin-copy_ex) is highly recommended so that output chains do not short-circuit prior to the metrics handling.  Putting this output at the end of the chain is also highly recommended.

### Parameters

`metrics_backend`: name of the metrics backend, currently either 'graphite' or 'statsd' (defaults to 'graphite')

`url`: endpoint for metrics publication (defaults to 'tcp://localhost:2003' for graphite and 'udp://localhost:8125' for statsd)

`prefix`: used prepend all metric names (optional)

`sum_maps`: a JSON serialized hash where the keys are Ruby expressions which evaluate to either a Numeric or non-Numeric type and the values are arrays with the the names (Ruby expresssion which evalate to strings) of the metrics to add the value to, when Numeric. (optional)

`metric_maps`: a JSON serialized hash where the keys evaluate to Booleans ad the values evaluate to metric hashes (optional)

`counter_defaults`: a JSON serialized array contain default values for metrics which should be sent if there are no occurences of the metric in a buffer chunk (optional)

`metric_defaults`: a JSON serialized array contain default values for metrics which should be sent if there are no occurences of the metric in a buffer chunk (optional)

#### Notes

The `url` parameter, in particular, is not something which is typically used in plugins such as this.  In particular, there is *no* hard-coded requirement for the endpoint to be a network socket, regardless of how the metrics backend is typically configured, with individual `host`, `port`, and `proto` parameters required. By using a single `url` parameter, any valid URL can be specified (so long as the handler has been implemented).  For instancee, an URL such as "file:///var/tmp/test.out" could be used in any configuration, even if the metrics backend is typically never configured in this way.  The primary reason for doing this is to allow for a simple way to debug configurations prior to putting them into live service without having to set up an ad hoc port listener or packet sniff the transmission just to see if the outputs are even in the correct format.

### Example configuration

Note that the following is at test configuration, appending to a file on the local filesystem prior to publishing anything to the live backend.
```
<match **>
  @type copy_ex
  <store ignore_error>
    [your stand log output configuration(s)]
  </store>
  <store ignore_error>
    @type buffered_metrics
    metrics_backend graphite
    prefix fluentd.<hostname>.5m
    #url tcp://localhost:2003
    url file:///var/tmp/graphite_test.out
    sum_defaults [{"-.-.-.count":0},{"-.-.-.bytes":0}]
    sum_maps {"event['record'].empty? ? false : 1":["-.-.-.count","(['tag','facility','level'].map {|t| event['record'][t] || '-'}+['count']).join('.')"],"event['record'].empty? ? false : event.to_s.length":["-.-.-.bytes","(['tag','facility','level'].map {|t| event['record'][t] || '-'}+['bytes']).join('.')"]}
    metric_maps {}
    metric_defaults []
    flush_interval 5m
    # Make this a working configuration
    [standard BufferedOutput parameters]
  </store>
</source>
```

Admittedly, the input specification is rather ugly, but there is really no "pretty" way to specify the inputs in a way which preserves the flexibility.  The "maps" are intended to be a "data-driven programming" inputs, where keys are the matching conditions and the values are the actions on matches.

Note that events are processed using the following data structure.  The following represents the data structure as JSON, but the event is *not* serialized for processing -- the processing is not based on regex parsing a JSON string serialization of the event.  The Fluentd event metadata (`tag` and `timestamp`) are available, as well as the actual event record data in the `record` data structue.

```JSON
  {
    "tag": <Fluentd event tag>,
    "timestamp": <Fluentd event timestamp>.
    "record": { <keys/values> }
  }
```

#### sum_maps:
```JSON
  {
     "event[record].empty? ? false : 1" : [
        "-.-.-.count",
        "([tag,facility,level].map {|t| event[record][t] || -}+[count]).join('.')"
     ],
     "event[record].empty? ? false : event.to_s.length" : [
        "-.-.-.bytes",
        "([tag,facility,level].map {|t| event[record][t] || -}+[bytes]).join('.')"
     ]
  }
```

The `event[record].empty? ? false : 1` key is a Ruby expression which evaluates to `false` (a Boolean type -- not Numeric) when it should do anything with this particular entry in the buffer chunk, and a `1` (an Integer type -- definitely Numeric).  It may be a bit convoluted, but this implements counters (ie. the Numeric value can be anything, including values derived data in the event).

The first element in the array, `-.-.-.count` is not a Ruby expression, so it does not dynamically evaluate to anything.  Every time the key evaulates to "1", the `<prefix>.-.-.-.count` is incremented.

The second element in the array, `([tag,facility,level].map {|t| event[record][t] || -}+[count]).join('.')`, is a Ruby expression, and the name will be dynamically set based on event data.  In this case, all events are expected to have `tag`, `facility`, and `level` keys in the record.  When Ruby evaluates this expression, the metric name becomes `<prefix>.<record tag value>.<record facility>.<record level>`.

So, even though there is only one event matching condition, two distinct metrics (a total, and a subtotal depending on `tag`, `facility`, and `level`) are incremented on every match.  The second key, `event[record].empty? ? false : event.to_s.length`, acts in a similar way, except that the increment value is not the value "1" (it is not a counter), but rather the (approximate) size of the event (in bytes).

#### sum_defaults:
```JSON
  [
     {
        "-.-.-.count" : 0
     },
     {
        "-.-.-.bytes" : 0
     }
  ]
```

The "defaults" specifications are needed if there are metrics which need to be sent with every metrics publication, even it none of the matches are met and the metric is never created during the run.  This may be more of an artifact, as this was initially done for Stackdriver, which had real issues with gaps in metrics series.