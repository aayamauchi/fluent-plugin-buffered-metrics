module Fluent
  class GraphiteMetricsOutput < BufferedOutput

    Plugin.register_output('graphite_metrics', self)

    def initialize
      super
    end

    config_param :url, :string, :default => nil
    config_param :socket_settings, :hash,
      :default => { 'proto' => 'tcp', 'location' => 'localhost', 'port' => 12003 }
    config_param :prefix, :string, :default => nil
    config_param :instance_id, :string, :default => nil
    config_param :counter_maps, :hash, :default => {}
    config_param :counter_defaults, :array, :default => []
    config_param :metric_maps, :hash, :default => {}
    config_param :metric_defaults, :array, :default => []

    def configure(conf)
      super(conf) {
        @url = conf.delete('url')
        @socket_settings = conf.delete('socket_settings')
        @prefix = conf.delete('prefix')
        @counter_maps = conf.delete('counter_maps')
        @counter_defaults = conf.delete('counter_defaults')
        @metric_maps = conf.delete('metric_maps')
        @metric_defaults = conf.delete('metric_defaults')
      }

      # I'd really prefer using an url specification.
      unless @url.nil? or @url.empty?
        @url.split(':').each_with_index do |val,i|
          if i == 0
            @socket_settings['proto'] = val
          elsif i == 1
            @socket_settings['location'] = val.slice(2..-1)
          elsif i == 2
            @socket_settings['port'] = val
          end
        end
      end

      @base_entry = { }

      @base_entry['prefix'] = @prefix unless @prefix.nil? or @prefix.empty?

      if ['udp','tcp','unix'].include?(@socket_settings['proto'])
        require 'socket'
        @socket_settings['port'] ||= 12003 unless @socket_settings['proto'] == 'unix'
      end

    end

    def encoding_workaround(data)
      data.each do |k,v|
        if v.is_a?(String)
          data[k] = v.force_encoding('UTF-8')
        elsif v.is_a?(Hash) or v.is_a?(Array)
          data[k] = encoding_workaround(v)
        end
      end

      return data
    end

    def format(tag, time, record)
      { 'tag' => tag, 'time' => time, 'record' => record }.to_msgpack
    end

    def write(chunk)

      timestamp = Time.now.to_i
      data = []

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
              data << @base_entry.merge({ 'collected_at' => event['time'].to_i }).merge(eval(v))
            end
          end
        end

      end

      @counter_defaults.each do |e|
        count_data[e['name']] = e['value'] unless count_data.key?(e['name'])
      end

      count_data.each do |name,value|
        data << @base_entry.merge({
          'name' => name,
          'value' => value,
          'collected_at' => timestamp
        })
      end

      @metric_defaults.each do |e|
        if not metric_data.key?(e['name'])
          data << @base_entry.merge({'collected_at' => timestamp}).merge(e)
        end
      end

      post(serialize(data)) unless data.empty?

    end

    # The module started life posting to the Stackdriver API.  Reformulate
    # and push in Graphite API format instead of having to reformulate all
    # of the parsing.

    def serialize(data)
      # Make a stand-alone serializer so that it's a trivial matter to
      # respecify for a different metrics collecting backend.
      ret_val = ''
      data.group_by{|e| e['collected_at']}.sort.each do |t,vals|
        vals.each do |e|
          ret_val += sprintf("%s%s %s %i\n",e.key?('prefix') ? e['prefix'] + '.' : '',e['name'],e['value'].to_s,t)
        end
      end

      return ret_val
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
