module Fluent
  class BufferedMetricsOutput < BufferedOutput

    Plugin.register_output('buffered_metrics', self)

    unless method_defined?(:log)
      define_method('log') { $log }
    end

    config_param :metrics_backend, :string, :default => 'graphite'
    config_param :url, :string, :default => nil
    config_param :http_headers, :array, :default => []
    config_param :prefix, :string, :default => nil
    config_param :instance_id, :string, :default => nil
    config_param :sum_maps, :hash, :default => {}
    config_param :sum_defaults, :array, :default => []
    config_param :metric_maps, :hash, :default => {}
    config_param :metric_defaults, :array, :default => []

    # The following are overrides for the paramaters inherited from
    # the superclass to them more sensible defaults. Since this is
    # likely to be run farily frequently, don't allow for long waits.
    config_param :retry_limit, :integer, :default => 4
    config_param :retry_wait, :time, :default => 1.0
    config_param :max_retry_wait, :time, :default => 5.0

    def initialize
      super
      require 'fluent/metrics_backends'
    end

    def configure(conf)
      super(conf) {
        @url = conf.delete('url')
        @http_headers = conf.delete('http_headers')
        @metrics_backend = conf.delete('metrics_backend')
        @prefix = conf.delete('prefix')
        @sum_maps = conf.delete('sum_maps')
        @sum_defaults = conf.delete('sum_defaults')
        @metric_maps = conf.delete('metric_maps')
        @metric_defaults = conf.delete('metric_defaults')
      }

      @base_entry = {}

      unless @prefix.nil?

        begin
          @prefix = eval(@prefix)
        rescue Exception
          @prefix = eval('"'+@prefix+'"')
        end

        @base_entry['prefix'] = @prefix unless @prefix.empty?

      end

      @sum_maps.each do |k,v|
        @sum_maps[k] = [ v ] unless v.is_a?(Array)
      end

      @metric_maps.each do |k,v|
        @metric_maps[k] = [ v ] unless v.is_a?(Array)
      end

      begin
        backend_name = @metrics_backend
        @metrics_backend = Object.const_get(
          sprintf('Fluent::MetricsBackend%s',backend_name.capitalize)
        ).new(@url,@http_headers)

      rescue => e
        log.error "Error initializing metrics backend #{backend_name}"
        raise e
      end

    end

    def format(tag, time, record)
      { 'tag' => tag, 'time' => time, 'record' => record }.to_msgpack
    end

    def derive_metrics(chunk)
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

      sum_data = {}
      metric_data = {}

      chunk.msgpack_each do |event|
        @sum_maps.each do |k,v|

          begin
            incr = eval(k)
            if incr.is_a?(Numeric)
              v.each do |e|
                begin
                  name = eval(e)
                rescue Exception
                  name = eval('"'+e+'"')
                end
                sum_data[name] ||= 0
                sum_data[name] += incr
              end
            end
          rescue Exception => e
            log.error "Failed to process sum_map (#{k},#{v}) for event: #{event}: #{e.trace}"
          end

        end

        @metric_maps.each do |k,v|

          begin
            if eval(k)
              v.each do |e|
                val = eval(e)
                if val.is_a?(Hash) and not val.empty?
                  @metrics_backend.buffer_append_entry(
                    @base_entry.merge(val),
                    event['time']
                  )
                end
              end
            end
          rescue Exception => e
            log.error "Failed to process metric_map (#{k},#{v}) for event: #{event}: #{e.trace}"
          end

        end

      end

      @sum_defaults.each do |e|
        if e.key?('name') and not e['name'].nil? and not e['name'].empty?
          sum_data[e['name']] = e['value'] unless sum_data.key?(e['name'])
        end
      end

      @metrics_backend.buffer_append_array_of_hashes(
        sum_data.map {|name,value|
          @base_entry.merge({ 'name' => name, 'value' => value, 'time' => timestamp })
        }
      )

      @metrics_backend.buffer_append_array_of_hashes(
         @metric_defaults.map {|e|
           if e.key?('name') and not e['name'].nil? and not e['name'].empty?
             @base_entry.merge(e).merge({'time' => timestamp}) unless metric_data.key?(e['name'])
          end
         }
      )

    end

    def write(chunk)

      # The superclass BufferedOutput provides the retry logic.  If the
      # buffer already has content this must be a retry after a failed
      # flush, so don't re-scan the chunk for the metrics.
      derive_metrics(chunk) unless @metrics_backend.buffer?
      @metrics_backend.buffer_flush if @metrics_backend.buffer?

    end

  end
end
