module Fluent
  class BufferedMetricsOutput < BufferedOutput

    Plugin.register_output('buffered_metrics', self)

    unless method_defined?(:log)
      define_method('log') { $log }
    end

    def initialize
      super
      require 'fluent/metrics_backends'
    end

    config_param :metrics_backend, :string, :default => 'graphite'
    config_param :url, :string, :default => nil
    config_param :prefix, :string, :default => nil
    config_param :instance_id, :string, :default => nil
    config_param :counter_maps, :hash, :default => {}
    config_param :counter_defaults, :array, :default => []
    config_param :metric_maps, :hash, :default => {}
    config_param :metric_defaults, :array, :default => []
    config_param :retries, :hash, :default => { 'max' => 4, 'wait' => '1s' }

    def configure(conf)
      super(conf) {
        @url = conf.delete('url')
        @metrics_backend = conf.delete('metrics_backend')
        @prefix = conf.delete('prefix')
        @counter_maps = conf.delete('counter_maps')
        @counter_defaults = conf.delete('counter_defaults')
        @metric_maps = conf.delete('metric_maps')
        @metric_defaults = conf.delete('metric_defaults')
        @retries = conf.delete('retries')
      }

      @base_entry = { }

      @base_entry['prefix'] = @prefix unless @prefix.nil? or @prefix.empty?

      begin
        backend_name = @metrics_backend
        @metrics_backend = Object.const_get(
          sprintf('Fluent::MetricsBackend%s',backend_name.capitalize)
        ).new
      rescue => e
        @router.emit_error_event(tag, Engine.now, {'time' => time, 'record' => record}, e)
      end

      begin
        @metrics_backend.set_connection_parameters(@url)
      rescue => e
        $log.error "Unable to set connection parameters from #{@url}."
        raise e
      end

    end

    def format(tag, time, record)
      # This is the formatter for entries getting added to the buffer,
      # not the formatter for metric data.
      { 'tag' => tag, 'time' => time, 'record' => record }.to_msgpack
    end

    def write(chunk)

      # The default timestamp really needs to set from the chunk
      # metadata.  However, there is no way to do this prior to
      # v0.14.  Putting the the VERSION conditional settitng, but
      # I don't really have a way to test it, at the moment.
      if chunk.methods.include?(/metadata/)
        # This should work for v0.14 and above and is preferable.
        timestamp = chunk.metadata.timekey.to_f
      else
        timestamp = Time.now.to_f
      end

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

      if @metrics_backend.buffer?
        @metrics_backend.buffer_flush(retries)
      end

    end

    # The module started life posting to the Stackdriver API.  Reformulate
    # and push in Graphite API format instead of having to reformulate all
    # of the parsing.

  end
end
