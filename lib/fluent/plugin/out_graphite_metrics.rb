module Fluent
  class GraphiteMetricsOutput < BufferedOutput

    Plugin.register_output('graphite_metrics', self)

    def initialize
      super
      require 'fluent/metrics_serializer'
    end

    config_param :metric_format, :string, :default => 'graphite'
    config_param :url, :string, :default => nil
    config_param :prefix, :string, :default => nil
    config_param :instance_id, :string, :default => nil
    config_param :counter_maps, :hash, :default => {}
    config_param :counter_defaults, :array, :default => []
    config_param :metric_maps, :hash, :default => {}
    config_param :metric_defaults, :array, :default => []

    def configure(conf)
      super(conf) {
        @url = conf.delete('url')
        @metric_format = conf.delete('metric_format')
        @prefix = conf.delete('prefix')
        @counter_maps = conf.delete('counter_maps')
        @counter_defaults = conf.delete('counter_defaults')
        @metric_maps = conf.delete('metric_maps')
        @metric_defaults = conf.delete('metric_defaults')
      }

      #@metrics_serializer = MetricsSerializer.instance_method(@metrics_format)

      @base_entry = { }

      @base_entry['prefix'] = @prefix unless @prefix.nil? or @prefix.empty?

      begin
        @metrics_backend = Object.const_get(
          sprintf('Fluent::MetricsBackend%s',@metric_format.capitalize)
        ).new
      rescue => e
        $log.error "MetricsBackend cless for #{@metric_format} could not be instantiated."
        raise e
      end

      begin
        @metrics_backend.set_connection_parameters(@url)
      rescue => e
        $log.err "Unable to set connection paramaters from #{@url}."
        raise e
      end

    end

    def format(tag, time, record)
      # This is the formatter for entries getting added to the buffer,
      # not the formatter for metric data.
      { 'tag' => tag, 'time' => time, 'record' => record }.to_msgpack
    end

    def write(chunk)

      timestamp = Time.now.to_i

      count_data = {}
      metric_data = {}

      chunk.msgpack_each do |event|
        @counter_maps.each do |k,v|
          if eval(k)
            begin
              name = eval(v) || eval('"'+v+'"')
            rescue
              name = eval('"'+v+'"')
            end
            count_data[name] ||= 0
            count_data[name] += 1
          end
        end

        @metric_maps.each do |k,v|
          if eval(k)
            if eval(v)
#              @metrics_backend.buffer_append_entry(
#                @base_entry.merge({ 'collected_at' => event['time'].to_i }).merge(eval(v))
#              )
              @metrics_backend.buffer_append_entry(
                @base_entry.merge(eval(v)),
                event['time'].to_i
              )
            end
          end
        end

      end

      @counter_defaults.each do |e|
        count_data[e['name']] = e['value'] unless count_data.key?(e['name'])
      end

      count_data.each do |name,value|
        @metrics_backend.buffer_append_entry(
          @base_entry.merge({ 'name' => name, 'value' => value }),
          timestamp
        )
      end

      @metric_defaults.each do |e|
        if not metric_data.key?(e['name'])
          @metrics_backend.buffer_append_entry(
            @base_entry.merge(e),
            timestamp
          )
        end
      end

      if @metric_backend.buffer?
        @metric_backend.connection_open
        @metric_backend.buffer_flush
        @metric_backend.connection_close
      end

    end

    # The module started life posting to the Stackdriver API.  Reformulate
    # and push in Graphite API format instead of having to reformulate all
    # of the parsing.

    def serialize(data)
      @metrics_backend.serialize_array_of_hashes(data)
    end

    def post(serialized_data)

      if @socket_settings['proto'] == 'tcp'
        sock = TCPSocket.new(@socket_settings['location'], @socket_settings['port'])
      elsif @socket_settings['proto'] == 'udp'
        sock = UDPSocket.new(@socket_settings['location'], @socket_settings['port'])
      elsif @socket_settings['proto'] == 'unix'
        sock = UNIXsocket.new(@socket_settings['location'])
      elsif @socket_settings['proto'] == 'file'
        sock = File.open(@socket_settings['location'],'a')
      else
        $log.error "socket_settings is not defined"
      end

      sock.write(serialized_data)
      sock.close()

    end

  end
end
